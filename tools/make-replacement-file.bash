#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# make-replacement-file.bash - build the complete new release-data/daemon-image-digests.json of the
#                              agent repository, so that a pull request can be opened by hand when the
#                              workflow could not open it.
#
# usage: make-replacement-file.bash [--ref <branch>] [--commit <sha>] --entry <entry-file> --title <pull-request-title> \
#                                   <output-dir>
#
# The script needs no token: the agent repository is public. It reads the commit that the branch
# (default main) points to, downloads the file and its schema at that commit, adds the entry with
# insert-release-data.py and writes, in <output-dir>:
#   daemon-image-digests.json   the complete new file, to be copied to release-data/ in the agent repository
#   NOTE.md                     what to do with it, the pull request title and the commit it is based on
#   BASE_COMMIT                 that commit (not written when it is not known); --commit <sha> starts from a given commit
#   change.diff                 the difference to the file at that commit
# The environment variable RELEASE_DATA_BASE replaces the place the files are downloaded from (a URL
# of the directory that holds the file and schema/), for tests.

set -euo pipefail

TOOLS=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
REPO=newrelic/newrelic-php-agent
REF=main
ENTRY=
TITLE=
FILE=daemon-image-digests.json
SCHEMA=schema/daemon-image-digests.schema.json

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --ref) REF=${2:?}; shift 2 ;;
    --commit) COMMIT=${2:?}; shift 2 ;;
    --entry) ENTRY=${2:?}; shift 2 ;;
    --title) TITLE=${2:?}; shift 2 ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[[ $# -eq 1 ]] || die 'usage: make-replacement-file.bash [--ref <branch>] [--commit <sha>] --entry <entry-file> --title <title> <output-dir>'
OUT=$1
[[ -z ${COMMIT:-} || $COMMIT =~ ^[0-9a-f]{40}$ ]] || die "--commit must be a full commit hash: $COMMIT"
[[ -f $ENTRY ]] || die "entry file not found: $ENTRY"
[[ -n $TITLE ]] || die '--title is required'

# A run that fails leaves nothing behind: a half made output directory would be uploaded as the
# replacement file by a workflow that keeps the output of a failed step.
CREATED=no
[[ -d $OUT ]] || CREATED=yes
cleanup() {
  local STATUS=$?
  if [[ $STATUS -ne 0 ]]; then
    rm -rf "$OUT/work" "$OUT/$FILE.before" "$OUT/$FILE" "$OUT/BASE_COMMIT" "$OUT/change.diff" "$OUT/NOTE.md"
    [[ $CREATED = no ]] || rmdir "$OUT" 2> /dev/null || true
  fi
}
trap cleanup EXIT
mkdir -p "$OUT/work/schema"
if [[ -n ${COMMIT:-} ]]; then
  SHA=$COMMIT
elif [[ -n ${RELEASE_DATA_BASE:-} ]]; then
  SHA="not known (RELEASE_DATA_BASE is set)"
else
  SHA=$(git ls-remote "https://github.com/$REPO" "refs/heads/$REF" | awk '{print $1}')
  [[ -n $SHA ]] || die "cannot read the commit of $REF in $REPO"
fi
if [[ -n ${RELEASE_DATA_BASE:-} ]]; then
  BASE_URL=$RELEASE_DATA_BASE
else
  BASE_URL=https://raw.githubusercontent.com/$REPO/$SHA/release-data
fi
for F in "$FILE" "$SCHEMA"; do
  curl -fsSL --retry 3 --retry-delay "${RETRY_DELAY:-5}" -o "$OUT/work/$F" "$BASE_URL/$F" || die "cannot download $BASE_URL/$F"
done

cp "$OUT/work/$FILE" "$OUT/$FILE.before"
"$TOOLS/insert-release-data.py" "$OUT/work/$FILE" "$ENTRY" "$OUT/work/$SCHEMA"
cp "$OUT/work/$FILE" "$OUT/$FILE"
[[ ! $SHA =~ ^[0-9a-f]{40}$ ]] || printf '%s\n' "$SHA" > "$OUT/BASE_COMMIT"
diff -u --label "$FILE (at $SHA)" --label "$FILE (new)" "$OUT/$FILE.before" "$OUT/$FILE" > "$OUT/change.diff" || true
rm -rf "$OUT/work" "$OUT/$FILE.before"

cat > "$OUT/NOTE.md" << NOTE
# Open this pull request by hand

The workflow could not open the pull request. \`$FILE\` in this directory is the complete new file. To open
the pull request:

1. Branch from \`$REF\` of \`$REPO\`.
2. Copy \`$FILE\` to \`release-data/$FILE\`.
3. Commit and open a pull request against \`$REF\` titled:

       $TITLE

The file is based on commit \`$SHA\` of \`$REF\`. If \`release-data/$FILE\` has changed since then, do not copy
this file over it: add the entry in \`change.diff\` to the current file by hand, in version order, newest first.
NOTE
echo "wrote $OUT/$FILE, $OUT/NOTE.md and $OUT/change.diff"
