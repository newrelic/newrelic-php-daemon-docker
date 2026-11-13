#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# test-digest-entry.bash - run tools/digest-entry.bash with stubs for the docker and curl commands.
# It needs no network and no registry.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ENTRY="$HERE/../../tools/digest-entry.bash"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

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

# The manifest list of a tag: two platforms, one with a variant, and an attestation manifest.
cat > index.json << 'JSON'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:aaaa", "size": 1, "platform": {"architecture": "amd64", "os": "linux"}},
    {"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:bbbb", "size": 1, "platform": {"architecture": "arm64", "os": "linux"}},
    {"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:cccc", "size": 1, "platform": {"architecture": "arm", "os": "linux", "variant": "v7"}},
    {"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:dddd", "size": 1, "platform": {"architecture": "unknown", "os": "unknown"}}
  ]
}
JSON
printf '%s' "$(cat index.json)" > index.raw
DIGEST="sha256:$(sha256sum index.raw | awk '{print $1}')"
api() { printf '{"name":"12.12.0","digest":"%s","tag_last_pushed":"2026-10-21T17:28:13.952123Z"}' "$1"; }
api "$DIGEST" > api-ok.json
api "sha256:0000" > api-stale.json
printf '{"name":"12.12.0","digest":"%s","tag_last_pushed":null}' "$DIGEST" > api-nopush.json

mkdir bin
cat > bin/docker << 'STUB'
#!/usr/bin/env bash
[[ -z ${STUB_DOCKER_FAIL:-} ]] || exit 1
# STUB_DOCKER_FAIL_TIMES: the first calls fail
if [[ -n ${STUB_DOCKER_FAIL_TIMES:-} ]]; then
  N=$(cat "$STUB_DIR/docker-count" 2> /dev/null || echo 0)
  echo $((N + 1)) > "$STUB_DIR/docker-count"
  [[ $N -ge $STUB_DOCKER_FAIL_TIMES ]] || exit 1
fi
cat "$STUB_INDEX"
STUB
cat > bin/curl << 'STUB'
#!/usr/bin/env bash
[[ -z ${STUB_CURL_FAIL:-} ]] || exit 22
# STUB_API_FILES: a list of files, one for each call; the last one is used again
COUNT_FILE="$STUB_DIR/curl-count"
N=$(cat "$COUNT_FILE" 2> /dev/null || echo 0)
N=$((N + 1))
echo "$N" > "$COUNT_FILE"
FILE=$(echo "$STUB_API_FILES" | tr ' ' '\n' | sed -n "${N}p")
[[ -n $FILE ]] || FILE=$(echo "$STUB_API_FILES" | tr ' ' '\n' | tail -n 1)
cat "$FILE"
STUB
chmod +x bin/docker bin/curl
export PATH="$WORK/bin:$PATH" STUB_INDEX="$WORK/index.raw" STUB_DIR="$WORK" HUB_WAIT=0 HUB_TRIES=3

reset() { rm -f "$WORK/curl-count" "$WORK/docker-count"; }

reset; export STUB_API_FILES="$WORK/api-ok.json"
"$ENTRY" 12.12.0 > entry.json 2> /dev/null
expect ok 'the entry is made' test -s entry.json
expect ok 'the digest is the hash of the manifest list' test "$(jq -r .digest entry.json)" = "$DIGEST"
expect ok 'the version is the tag' test "$(jq -r .version entry.json)" = 12.12.0
expect ok 'the push time is the one of the API' test "$(jq -r .pushed entry.json)" = 2026-10-21T17:28:13.952123Z
expect ok 'the platforms, with the variant, without the attestation' \
  test "$(jq -c '.platforms' entry.json)" = '{"linux/amd64":"sha256:aaaa","linux/arm/v7":"sha256:cccc","linux/arm64":"sha256:bbbb"}'
expect ok 'only the four fields' test "$(jq -c 'keys' entry.json)" = '["digest","platforms","pushed","version"]'

reset; expect ok 'the expected digest is the digest' "$ENTRY" 12.12.0 "$DIGEST"
reset; expect fail 'another expected digest' "$ENTRY" 12.12.0 sha256:0000
reset; expect fail 'a tag that is not a version' "$ENTRY" latest
reset; expect fail 'no tag' "$ENTRY"
reset; "$ENTRY" --version 12.12.0.41 > entry-v.json 2> warn.txt
expect ok '--version takes the agent version and gives the entry of its tag' cmp entry.json entry-v.json
expect ok '--version without an expected digest warns' grep -q 'no expected digest' warn.txt
reset; "$ENTRY" --version 12.12.0.41 "$DIGEST" > /dev/null 2> warn.txt
expect ok '--version with the expected digest does not warn' bash -c '! grep -q "no expected digest" warn.txt'
reset; "$ENTRY" 12.12.0 > /dev/null 2> warn.txt
expect ok 'the positional tag does not warn' bash -c '! grep -q "no expected digest" warn.txt'
reset; expect fail '--version with another expected digest' "$ENTRY" --version 12.12.0.41 sha256:0000
reset; expect fail '--version with a tag (three numbers)' "$ENTRY" --version 12.12.0
reset; "$ENTRY" --version 12.12.0 > /dev/null 2> warn.txt
expect ok '--version with a tag says that it wants the agent version' grep -q 'not an agent version' warn.txt
reset; expect fail '--version with a fifth number' "$ENTRY" --version 12.12.0.41.1
reset; expect fail '--version without a version' "$ENTRY" --version
reset; expect fail '--version with something that is not a version' "$ENTRY" --version latest
reset; STUB_DOCKER_FAIL=1 expect fail 'the manifest cannot be read' "$ENTRY" 12.12.0
reset; STUB_DOCKER_FAIL_TIMES=2 expect ok 'the manifest is read on the third try' "$ENTRY" 12.12.0
reset; STUB_DOCKER_FAIL_TIMES=3 expect fail 'the manifest cannot be read in three tries' "$ENTRY" 12.12.0
reset; STUB_CURL_FAIL=1 expect fail 'the API cannot be read' "$ENTRY" 12.12.0

reset; export STUB_API_FILES="$WORK/api-stale.json"
expect fail 'the API keeps another digest' "$ENTRY" 12.12.0
reset; export STUB_API_FILES="$WORK/api-stale.json $WORK/api-stale.json $WORK/api-ok.json"
expect ok 'the API shows the push on the third try' "$ENTRY" 12.12.0
reset; export STUB_API_FILES="$WORK/api-stale.json $WORK/api-stale.json $WORK/api-stale.json $WORK/api-ok.json"
expect fail 'the API shows the push after the last try' "$ENTRY" 12.12.0
reset; export STUB_API_FILES="$WORK/api-nopush.json"
expect fail 'the API has no push time' "$ENTRY" 12.12.0

printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
