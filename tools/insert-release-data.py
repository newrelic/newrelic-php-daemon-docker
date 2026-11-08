#!/usr/bin/env python3

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

"""Add the entry of one image to release-data/daemon-image-digests.json.

usage: insert-release-data.py <data-file> <entry-file> <schema-file>

<entry-file> holds the entry of one image as written by digest-entry.bash. The entry is inserted
in version order, newest first, comparing the version numbers part by part (12.10.0 is newer than
12.9.0). A recorded digest never changes: if the file has an entry with the same version, the file
stays as it is when the digests are the same, and the script stops when they differ.

The file is written in a fixed format (sorted keys, two-space indent), so that the change to the
file is only the new entry. The script stops without writing anything if
  * the file or the result does not match the schema (a time must be a real time and a string
    must not end in a newline, which Python's regular expression search would accept for "$"),
  * the file is not in that format, or its entries are not in version order (rewriting it would
    change more than the new entry),
  * the entry has a version that is not made of numbers separated by dots,
  * the file has an entry with the same version and other digests.
"""

import datetime
import json
import re
import sys

import jsonschema
from jsonschema import exceptions, validators

DATE_TIME = re.compile(r"^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-](\d{2}):(\d{2}))$")


def pattern(validator, regex, instance, schema):
    """The keyword pattern. jsonschema searches with re.search, where "$" also matches before a
    trailing newline; in ECMA-262, which JSON Schema uses, it does not."""
    if validator.is_type(instance, "string") and (instance.endswith("\n") or not re.search(regex, instance)):
        yield exceptions.ValidationError("%r does not match %r" % (instance, regex))


Validator = validators.extend(jsonschema.Draft202012Validator, {"pattern": pattern})
FORMATS = jsonschema.FormatChecker()


@FORMATS.checks("date-time")
def is_date_time(value):
    """A time as RFC 3339 writes it, with a real date and time (jsonschema needs another package for this)."""
    match = DATE_TIME.fullmatch(value) if isinstance(value, str) else None
    if not match:
        return False
    try:
        datetime.datetime.strptime(match.group(1) + "T" + match.group(2), "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return False
    return match.group(5) is None or (int(match.group(5)) < 24 and int(match.group(6)) < 60)


def validate(instance, schema):
    """Validate with the stricter pattern and with the formats date and date-time checked."""
    Validator.check_schema(schema)
    Validator(schema, format_checker=FORMATS).validate(instance)


def version_key(version):
    """Return the version as a tuple of numbers, so that 12.10.0 sorts after 12.9.0."""
    try:
        return tuple(int(part) for part in version.split("."))
    except ValueError:
        raise SystemExit("the version %r is not made of numbers separated by dots" % version)


def dump(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def list_name(data):
    """Return the name of the list of entries in the file: images or releases."""
    for name in ("images", "releases"):
        if name in data:
            return name
    raise SystemExit("the file has neither an images nor a releases list")


def insert(data, entry):
    """Return data with the entry added in version order, and the replaced entry or None."""
    name = list_name(data)
    replaced = None
    kept = []
    for existing in data[name]:
        if existing["version"] == entry["version"]:
            replaced = existing
        else:
            kept.append(existing)
    kept.append(entry)
    kept.sort(key=lambda item: version_key(item["version"]), reverse=True)
    # keep the other top-level fields, such as first_image_version
    return dict(data, **{name: kept}), replaced


def without_time(entry):
    """Return the entry without the field that is a time, not a digest."""
    return {key: value for key, value in entry.items() if key != "pushed"}


def main(argv):
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    data_file, entry_file, schema_file = argv[1:4]

    with open(schema_file) as handle:
        schema = json.load(handle)
    with open(data_file) as handle:
        text = handle.read()
    data = json.loads(text)
    with open(entry_file) as handle:
        entry = json.load(handle)
    name = list_name(data)

    # Check the entry on its own: the schema describes the whole file.
    validate(dict(data, **{name: [entry]}), schema)
    validate(data, schema)

    # The file must already be in the format this script writes and in version order.
    # Otherwise rewriting it would change more than the new entry.
    if text != dump(data):
        raise SystemExit("%s is not in the format this script writes (sorted keys, two-space indent); "
                         "fix it first" % data_file)
    versions = [version_key(item["version"]) for item in data[name]]
    if versions != sorted(versions, reverse=True) or len(set(versions)) != len(versions):
        raise SystemExit("%s is not in version order, newest first, without duplicates; fix it first" % data_file)

    result, replaced = insert(data, entry)
    # A digest that is recorded does not change. The time of the push is not a digest and is not compared.
    if replaced is not None:
        if without_time(replaced) != without_time(entry):
            raise SystemExit("::error::%s has an entry for %s with other digests than the new one; "
                             "a recorded digest must not be replaced, find out why the image changed"
                             % (data_file, entry["version"]))
        print("unchanged %s in %s: the same digests are recorded already" % (entry["version"], data_file))
        return 0
    validate(result, schema)

    # Nothing but the new entry may change.
    others_before = [item for item in data[name] if item["version"] != entry["version"]]
    others_after = [item for item in result[name] if item["version"] != entry["version"]]
    if others_before != others_after:
        raise SystemExit("the other entries would change; not writing")

    with open(data_file, "w") as handle:
        handle.write(dump(result))
    print("%s %s in %s" % ("replaced" if replaced else "added", entry["version"], data_file))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
