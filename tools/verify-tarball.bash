#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# verify-tarball.bash - check the signature of a PHP agent tarball against the tarball signing key.
#
# usage: verify-tarball.bash [--fingerprints-url <url>] <tarball> <signature>
#
# The signature is the detached .asc file that is published next to the tarball. The fingerprint
# of the tarball signing key and the place of its public key are taken from
# release-data/signing-key-fingerprints.json of newrelic-php-agent (the entry with the purpose
# "tarball"). The public key is downloaded from that place, and its fingerprint must be the listed
# one. The script exits with a non-zero status unless the signature is valid and made by that key.

set -euo pipefail

FINGERPRINTS_URL=https://raw.githubusercontent.com/newrelic/newrelic-php-agent/main/release-data/signing-key-fingerprints.json

if [[ ${1:-} = --fingerprints-url ]]; then
  FINGERPRINTS_URL=${2:?--fingerprints-url needs a URL}
  shift 2
fi

if [[ $# -ne 2 ]]; then
  echo "usage: $(basename "$0") [--fingerprints-url <url>] <tarball> <signature>" >&2
  exit 2
fi
TARBALL=$1
SIGNATURE=$2

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v jq > /dev/null || fail 'jq is not installed'
[[ -f $TARBALL ]] || fail "tarball not found: $TARBALL"
[[ -f $SIGNATURE ]] || fail "signature not found: $SIGNATURE"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The fingerprint and the place of the public key of the tarball signing key
# --retry repeats timeouts and server errors, not a missing file
CURL=(curl -fsSL --retry 3 --retry-delay "${RETRY_DELAY:-5}")
"${CURL[@]}" -o "$WORK/fingerprints.json" "$FINGERPRINTS_URL" || fail "cannot download $FINGERPRINTS_URL"
FINGERPRINT=$(jq -r '[.keys[] | select(.purpose == "tarball" and (.status // "active") == "active")][0].fingerprint // empty' "$WORK/fingerprints.json")
KEY_URL=$(jq -r '[.keys[] | select(.purpose == "tarball" and (.status // "active") == "active")][0].public_key_url // empty' "$WORK/fingerprints.json")
[[ -n $FINGERPRINT && -n $KEY_URL ]] || fail "$FINGERPRINTS_URL lists no tarball signing key"

"${CURL[@]}" -o "$WORK/key.asc" "$KEY_URL" || fail "cannot download the public key from $KEY_URL"

# A fresh keyring that holds only the public key.
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --import "$WORK/key.asc" 2> /dev/null || fail "cannot import the public key from $KEY_URL"
IMPORTED=$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr:/ {print $10; exit}')
[[ $IMPORTED = "$FINGERPRINT" ]] || fail "the public key at $KEY_URL is $IMPORTED, not the listed key $FINGERPRINT"

# The primary key fingerprint is the last field of the VALIDSIG status line. The pattern is anchored with
# $ so that the fingerprint must be that field: gpg prints no fingerprint in the fields before it except the
# one of the signing key, and the keyring holds only the key whose fingerprint was compared above. The anchor
# is a safeguard that real gpg output cannot test.
STATUS=$(gpg --batch --status-fd 1 --verify "$SIGNATURE" "$TARBALL" 2> /dev/null || true)
grep -q "^\[GNUPG:\] VALIDSIG .* $FINGERPRINT\$" <<< "$STATUS" \
  || fail "the signature $SIGNATURE is not a valid signature of $TARBALL by the key $FINGERPRINT"
# gpg also prints VALIDSIG for a revoked or an expired key, next to one of these lines.
if grep -qE '^\[GNUPG:\] (REVKEYSIG|EXPKEYSIG|KEYEXPIRED|EXPSIG) ' <<< "$STATUS"; then
  fail "the key $FINGERPRINT is revoked or expired, or the signature has expired"
fi

echo "verified $(basename "$TARBALL") signed by $FINGERPRINT"
