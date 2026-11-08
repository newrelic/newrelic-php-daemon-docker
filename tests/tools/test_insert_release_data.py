#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

"""Tests for insert-release-data.py. Run with: python3 -m unittest discover -s tests/tools"""

import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("insert_release_data", os.path.join(HERE, "..", "..", "tools", "insert-release-data.py"))
insert_release_data = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(insert_release_data)

DIGEST = "sha256:" + "a" * 64

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["first_image_version", "images"],
    "properties": {
        "first_image_version": {"type": "string", "pattern": "^[0-9]+(\\.[0-9]+)+$"},
        "images": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["digest", "platforms", "pushed", "version"],
                "properties": {
                    "version": {"type": "string", "pattern": "^[0-9]+(\\.[0-9]+)+$"},
                    "digest": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
                    "pushed": {"type": "string"},
                    "platforms": {
                        "type": "object",
                        "minProperties": 1,
                        "additionalProperties": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
                    },
                },
            },
        }
    },
}


def entry(version, digest=DIGEST):
    return {
        "version": version,
        "digest": digest,
        "pushed": "2026-10-21T17:28:13.952123Z",
        "platforms": {"linux/amd64": digest, "linux/arm64": digest},
    }


class InsertImageDigest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.schema_file = self.write("schema.json", json.dumps(SCHEMA))

    def write(self, name, text):
        path = os.path.join(self.dir.name, name)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def run_script(self, images, new_entry, raw=None):
        data_file = self.write("data.json", raw if raw is not None else insert_release_data.dump({"first_image_version": "9.2.0", "images": images}))
        entry_file = self.write("entry.json", json.dumps(new_entry))
        status = insert_release_data.main(["x", data_file, entry_file, self.schema_file])
        self.assertEqual(status, 0)
        with open(data_file) as handle:
            return handle.read()

    def versions(self, text):
        return [image["version"] for image in json.loads(text)["images"]]

    def test_adds_to_an_empty_list(self):
        self.assertEqual(self.versions(self.run_script([], entry("12.12.0"))), ["12.12.0"])

    def test_newest_first_by_number_not_by_text(self):
        text = self.run_script([entry("12.9.0"), entry("11.0.0")], entry("12.10.0"))
        self.assertEqual(self.versions(text), ["12.10.0", "12.9.0", "11.0.0"])

    def test_inserts_in_the_middle_and_at_the_end(self):
        text = self.run_script([entry("12.12.0"), entry("12.1.0")], entry("12.9.0"))
        self.assertEqual(self.versions(text), ["12.12.0", "12.9.0", "12.1.0"])
        text = self.run_script([entry("12.12.0")], entry("9.18.0"))
        self.assertEqual(self.versions(text), ["12.12.0", "9.18.0"])

    def test_stops_when_the_same_version_has_another_digest(self):
        other = "sha256:" + "b" * 64
        with self.assertRaises(SystemExit) as stopped:
            self.run_script([entry("12.12.0"), entry("12.1.0")], entry("12.12.0", other))
        self.assertIn("a recorded digest must not be replaced", str(stopped.exception))

    def test_leaves_the_file_as_it_is_when_the_same_digests_are_recorded(self):
        before = insert_release_data.dump({"first_image_version": "9.2.0", "images": [entry("12.12.0"), entry("12.1.0")]})
        after = self.run_script([entry("12.12.0"), entry("12.1.0")], entry("12.12.0"), raw=before)
        self.assertEqual(after, before)

    def test_only_the_new_entry_changes_in_the_text(self):
        before = insert_release_data.dump({"first_image_version": "9.2.0", "images": [entry("12.12.0"), entry("12.1.0")]})
        after = self.run_script([entry("12.12.0"), entry("12.1.0")], entry("12.9.0"), raw=before)
        removed = [line for line in before.splitlines() if line not in after.splitlines()]
        self.assertEqual(removed, [])

    def test_keeps_first_image_version(self):
        before = insert_release_data.dump({"first_image_version": "9.2.0", "images": [entry("12.12.0")]})
        text = self.run_script([], entry("12.13.0"), raw=before)
        self.assertEqual(json.loads(text)["first_image_version"], "9.2.0")
        self.assertEqual([i["version"] for i in json.loads(text)["images"]], ["12.13.0", "12.12.0"])

    def test_stops_on_a_file_that_is_not_in_the_written_format(self):
        with self.assertRaises(SystemExit):
            self.run_script([], entry("12.12.0"), raw=json.dumps({"first_image_version": "9.2.0", "images": []}))

    def test_stops_on_a_file_that_is_not_in_version_order(self):
        raw = insert_release_data.dump({"first_image_version": "9.2.0", "images": [entry("12.1.0"), entry("12.12.0")]})
        with self.assertRaises(SystemExit):
            self.run_script([], entry("12.9.0"), raw=raw)

    def test_stops_on_an_invalid_entry(self):
        with self.assertRaises(Exception):
            self.run_script([], entry("12.12.0", "sha256:xyz"))

    def test_stops_on_a_version_that_is_not_numbers(self):
        with self.assertRaises(Exception):
            self.run_script([], entry("12.12.0-rc1"))

    def test_does_not_write_when_it_stops(self):
        raw = json.dumps({"first_image_version": "9.2.0", "images": []})
        data_file = self.write("data.json", raw)
        entry_file = self.write("entry.json", json.dumps(entry("12.12.0")))
        with self.assertRaises(SystemExit):
            insert_release_data.main(["x", data_file, entry_file, self.schema_file])
        with open(data_file) as handle:
            self.assertEqual(handle.read(), raw)


if __name__ == "__main__":
    unittest.main()
