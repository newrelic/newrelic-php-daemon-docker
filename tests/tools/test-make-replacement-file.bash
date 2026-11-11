#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# test-make-replacement-file.bash - run tools/make-replacement-file.bash on release data served from a
# local directory. It needs no token and no network.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
MAKE="$HERE/../../tools/make-replacement-file.bash"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0
expect() { # expect <ok|fail> <description> <command...>
  local WANT=$1 WHAT=$2 STATUS
  shift 2
  "$@" > "$WORK/out.txt" 2>&1
  STATUS=$?
  if { [[ $WANT = ok ]] && [[ $STATUS -eq 0 ]]; } || { [[ $WANT = fail ]] && [[ $STATUS -ne 0 ]]; }; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAILED: %s (wanted %s, exit %s)\n' "$WHAT" "$WANT" "$STATUS"
    sed 's/^/    /' "$WORK/out.txt"
  fi
}

SERVED="$WORK/served"
mkdir -p "$SERVED/schema"
cat > "$SERVED/schema/daemon-image-digests.schema.json" << 'JSON'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["first_image_version", "images"],
  "properties": {
    "first_image_version": {"type": "string"},
    "images": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["digest", "platforms", "pushed", "version"],
        "properties": {
          "version": {"type": "string", "pattern": "^[0-9]+(\\.[0-9]+)+$"},
          "digest": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
          "pushed": {"type": "string"},
          "platforms": {"type": "object", "minProperties": 1, "additionalProperties": {"type": "string"}}
        }
      }
    }
  }
}
JSON
D1="sha256:$(printf 'a%.0s' $(seq 64))"
D2="sha256:$(printf 'b%.0s' $(seq 64))"
printf '{\n  "first_image_version": "9.2.0",\n  "images": [\n    {\n      "digest": "%s",\n      "platforms": {\n        "linux/amd64": "%s"\n      },\n      "pushed": "2026-10-21T17:28:13Z",\n      "version": "12.12.0"\n    }\n  ]\n}\n' "$D1" "$D1" > "$SERVED/daemon-image-digests.json"
printf '{"digest": "%s", "platforms": {"linux/amd64": "%s"}, "pushed": "2026-11-07T10:00:00Z", "version": "12.13.0"}' "$D2" "$D2" > "$WORK/entry.json"
export RELEASE_DATA_BASE="file://$SERVED" RETRY_DELAY=0

expect ok 'the file is made' "$MAKE" --entry "$WORK/entry.json" --title 'chore(release-data): add daemon image digest for 12.13.0.1' "$WORK/out"
expect ok 'the new image comes first and the field is kept' \
  test "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['first_image_version'], ' '.join(i['version'] for i in d['images']))" "$WORK/out/daemon-image-digests.json")" = '9.2.0 12.13.0 12.12.0'
expect ok 'the diff only adds lines' bash -c "! grep -q '^-[^-]' $WORK/out/change.diff && grep -q '^+.*12.13.0' $WORK/out/change.diff"
expect ok 'the note has the title' grep -qF 'add daemon image digest for 12.13.0.1' "$WORK/out/NOTE.md"
expect ok 'no work files are left' test "$(ls "$WORK/out" | LC_ALL=C sort | tr '\n' ' ')" = 'NOTE.md change.diff daemon-image-digests.json '
expect fail 'a missing entry file fails' "$MAKE" --entry "$WORK/none.json" --title t "$WORK/x1"
expect fail 'no title fails' "$MAKE" --entry "$WORK/entry.json" "$WORK/x2"
expect fail 'a bad entry fails' "$MAKE" --entry <(echo '{"version": "1"}') --title t "$WORK/x3"
COMMIT=0123456789abcdef0123456789abcdef01234567
expect ok 'a given commit is written to BASE_COMMIT' bash -c "'$MAKE' --commit $COMMIT --entry '$WORK/entry.json' --title t '$WORK/c1' > /dev/null && test \"\$(cat '$WORK/c1/BASE_COMMIT')\" = $COMMIT"
expect ok 'a given commit is named in NOTE.md and change.diff' bash -c "grep -q $COMMIT '$WORK/c1/NOTE.md' && grep -q $COMMIT '$WORK/c1/change.diff'"
expect fail 'a commit that is not a full hash fails' "$MAKE" --commit abc123 --entry "$WORK/entry.json" --title t "$WORK/c2"
rm "$SERVED/daemon-image-digests.json"
expect fail 'a file that is not served fails' "$MAKE" --entry "$WORK/entry.json" --title t "$WORK/x4"
expect ok 'a failed run leaves no output directory' test ! -e "$WORK/x4"
mkdir "$WORK/x5" && echo keep > "$WORK/x5/other.txt"
expect fail 'a failed run in an existing directory fails' "$MAKE" --entry "$WORK/entry.json" --title t "$WORK/x5"
expect ok 'a failed run in an existing directory removes only what it made' test "$(ls "$WORK/x5" | tr '\n' ' ')" = 'other.txt '

printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
