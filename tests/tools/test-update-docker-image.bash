#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# test-update-docker-image.bash - run tools/update-docker-image.bash in a sandbox: a new git
# repository with a local bare remote, a wget that serves files from a directory, and a throwaway
# signing key in place of the real one. It needs no network and publishes nothing.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../.."
WORK=$(mktemp -d)
VERSION=9.8.7.6
SHORT=9.8.7
TARBALL=newrelic-php5-$VERSION-linux-musl.tar.gz
trap 'rm -rf "$WORK" /tmp/$TARBALL /tmp/$TARBALL.asc' EXIT
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

# Throwaway keys, kept in their own keyring for signing
KEYS=$(mktemp -d)
gen() {
  GNUPGHOME=$KEYS gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key "$1 <$1@example.com>" rsa2048 sign never 2> /dev/null
  GNUPGHOME=$KEYS gpg --batch --with-colons --list-keys "$1" | awk -F: '/^fpr:/ {print $10; exit}'
}
GOOD=$(gen good)
OTHER=$(gen other)
GNUPGHOME=$KEYS gpg --batch --armor --export "$GOOD" > good.pub
sign() { GNUPGHOME=$KEYS gpg --batch --pinentry-mode loopback --passphrase '' --local-user "$1" --detach-sign --armor --yes -o "$3" "$2"; }

# The list of signing keys, with the public key of the throwaway key served from a file
cat > fingerprints.json << JSON
{"keys": [{"purpose": "tarball", "fingerprint": "$GOOD", "public_key_url": "file://$WORK/good.pub"}]}
JSON

# A wget that serves files from $SERVE and fails like a 404 for the rest
mkdir bin serve
cat > bin/wget << 'STUB'
#!/usr/bin/env bash
[[ $1 = -O ]] || exit 2
echo "$3" >> "$SERVE/../requested-urls"
FILE="$SERVE/$(basename "$3")"
[[ -f $FILE ]] || { echo "ERROR 404: Not Found." >&2; exit 8; }
cp "$FILE" "$2"
STUB
chmod +x bin/wget
export PATH="$WORK/bin:$PATH" SERVE="$WORK/serve" DOWNLOAD_ARCHIVE_URL=http://stub.invalid/archive
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A fresh repository with the tools of this repository, except that the pinned key is the throwaway key.
new_repo() { # new_repo <name>
  rm -rf "$1" "$1.git"
  git init -q --bare "$1.git"
  git init -q -b master "$1"
  cp -r "$REPO/tools" "$1/tools"
  cp "$REPO/Dockerfile-template" "$REPO/docker-entrypoint-template" "$1/"
  sed -i.bak "s#^FINGERPRINTS_URL=.*#FINGERPRINTS_URL=file://$WORK/fingerprints.json#" "$1/tools/verify-tarball.bash" && rm "$1/tools/verify-tarball.bash.bak"
  git -C "$1" remote add origin "$WORK/$1.git"
  git -C "$1" add -A
  git -C "$1" commit -q -m init
  git -C "$1" push -q origin master
}
run_update() { (cd "$1" && ./tools/update-docker-image.bash $VERSION); }
run_update_log() { run_update "$1" > "$WORK/$1.log" 2>&1; }
branches_in_remote() { git -C "$1.git" branch --list "$SHORT" | wc -l | tr -d ' '; }

echo "the tarball" > serve/$TARBALL
sign "$GOOD" serve/$TARBALL serve/$TARBALL.asc
SHA=$(sha256sum serve/$TARBALL | awk '{print $1}')

# 1. a tarball with a valid signature
new_repo r1
expect ok 'a valid signature: the script succeeds' run_update r1
expect ok 'a valid signature: the branch is pushed' test "$(branches_in_remote r1)" = 1
expect ok 'a valid signature: the Dockerfile pins the hash of the tarball' grep -q "NEWRELIC_SHA=$SHA" "r1/$SHORT/Dockerfile"
expect ok 'a valid signature: the Dockerfile has the version' grep -q "NEWRELIC_VERSION=$VERSION" "r1/$SHORT/Dockerfile"

expect ok 'a valid signature: the tarball and the signature are downloaded from <archive>/<version>/' \
  test "$(sort "$WORK/requested-urls")" = "http://stub.invalid/archive/$VERSION/$TARBALL
http://stub.invalid/archive/$VERSION/$TARBALL.asc"
rm "$WORK/requested-urls"

# 2. a tarball that was changed after it was signed
echo "changed" >> serve/$TARBALL
new_repo r2
expect fail 'a changed tarball: the script fails' run_update r2
expect ok 'a changed tarball: nothing is pushed' test "$(branches_in_remote r2)" = 0
expect ok 'a changed tarball: no Dockerfile is made' test ! -e "r2/$SHORT"
echo "the tarball" > serve/$TARBALL

# 3. a signature made by another key
sign "$OTHER" serve/$TARBALL serve/$TARBALL.asc
new_repo r3
expect fail 'another key: the script fails' run_update r3
expect ok 'another key: nothing is pushed' test "$(branches_in_remote r3)" = 0

# 4. no signature
rm serve/$TARBALL.asc
new_repo r4
expect fail 'no signature: the script fails' run_update_log r4
expect ok 'no signature: the message says so' grep -q 'signature of the tarball could not be downloaded' "$WORK/r4.log"
expect ok 'no signature: nothing is pushed' test "$(branches_in_remote r4)" = 0

# 5. a version that is not a full version
sign "$GOOD" serve/$TARBALL serve/$TARBALL.asc
new_repo r5
expect fail 'a short version is refused' bash -c "cd r5 && ./tools/update-docker-image.bash 9.8.7"

# 6. no archive URL in the environment, or an empty one: the public archive
sign "$GOOD" serve/$TARBALL serve/$TARBALL.asc
rm -f "$WORK/requested-urls"
new_repo r6
expect ok 'no archive URL: the script succeeds' env -u DOWNLOAD_ARCHIVE_URL bash -c "cd r6 && ./tools/update-docker-image.bash $VERSION"
expect ok 'no archive URL: the tarball and the signature are downloaded from the public archive' \
  test "$(sort "$WORK/requested-urls")" = "https://download.newrelic.com/php_agent/archive/$VERSION/$TARBALL
https://download.newrelic.com/php_agent/archive/$VERSION/$TARBALL.asc"
rm "$WORK/requested-urls"
new_repo r7
expect ok 'an empty archive URL: the script succeeds' env DOWNLOAD_ARCHIVE_URL= bash -c "cd r7 && ./tools/update-docker-image.bash $VERSION"
expect ok 'an empty archive URL: the public archive is used' grep -q '^https://download.newrelic.com/php_agent/archive/' "$WORK/requested-urls"

printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
