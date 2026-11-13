#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# test-verify-tarball.bash - run tools/verify-tarball.bash against throwaway keys, with the list of
# signing keys and the public keys served from files. It needs no secrets and no network.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
VERIFY="$HERE/../../tools/verify-tarball.bash"
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

export GNUPGHOME=$(mktemp -d)
gen() {
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key "$1 <$1@example.com>" rsa2048 sign never 2> /dev/null
  gpg --batch --with-colons --list-keys "$1" | awk -F: '/^fpr:/ {print $10; exit}'
}
GOOD=$(gen good)
OTHER=$(gen other)
gpg --batch --armor --export "$GOOD" > good.pub
gpg --batch --armor --export "$OTHER" > other.pub
sign() { gpg --batch --pinentry-mode loopback --passphrase '' --local-user "$1" --detach-sign --armor --yes -o "$3" "$2"; }

echo tarball > t.tar.gz
sign "$GOOD" t.tar.gz t.tar.gz.asc
sign "$OTHER" t.tar.gz other.asc
cp t.tar.gz tampered.tar.gz && echo x >> tampered.tar.gz
# a signature that has expired, made by a key that does not expire: gpg prints VALIDSIG next to EXPSIG
EXPHOME=$(mktemp -d)
FAKED=(--faked-system-time 20200101T000000)
GNUPGHOME=$EXPHOME gpg --batch --quiet "${FAKED[@]}" --pinentry-mode loopback --passphrase '' --quick-generate-key 'expsig <expsig@example.com>' rsa2048 sign never 2> /dev/null
EXPSIG=$(GNUPGHOME=$EXPHOME gpg --batch --with-colons --list-keys expsig | awk -F: '/^fpr:/ {print $10; exit}')
GNUPGHOME=$EXPHOME gpg --batch --armor --export "$EXPSIG" > expsig.pub
GNUPGHOME=$EXPHOME gpg --batch "${FAKED[@]}" --default-sig-expire 1d --pinentry-mode loopback --passphrase '' --local-user "$EXPSIG" --detach-sign --armor --yes -o expsig.asc t.tar.gz 2> /dev/null
rm -rf "$EXPHOME"
unset GNUPGHOME

# The list of signing keys, as release-data/signing-key-fingerprints.json has it: another key comes first
fingerprints() { # fingerprints <file> <tarball fingerprint> <tarball key url>
  cat > "$1" << JSON
{"keys": [
  {"purpose": "apt", "fingerprint": "$OTHER", "public_key_url": "file://$WORK/other.pub"},
  {"purpose": "tarball", "fingerprint": "$2", "public_key_url": "$3"}
]}
JSON
}
fingerprints fp.json "$GOOD" "file://$WORK/good.pub"
fingerprints fp-wrong-key.json "$GOOD" "file://$WORK/other.pub"
fingerprints fp-other-fingerprint.json "$OTHER" "file://$WORK/good.pub"
fingerprints fp-no-key.json "$GOOD" "file://$WORK/missing.pub"
echo '{"keys": [{"purpose": "apt", "fingerprint": "x", "public_key_url": "y"}]}' > fp-no-tarball.json
# After a key rotation the retired key is listed too, here before the active one
cat > fp-retired-first.json << JSON
{"keys": [
  {"purpose": "tarball", "fingerprint": "$OTHER", "public_key_url": "file://$WORK/other.pub", "status": "retired"},
  {"purpose": "tarball", "fingerprint": "$GOOD", "public_key_url": "file://$WORK/good.pub", "status": "active"}
]}
JSON
cat > fp-only-retired.json << JSON
{"keys": [{"purpose": "tarball", "fingerprint": "$GOOD", "public_key_url": "file://$WORK/good.pub", "status": "revoked"}]}
JSON
echo 'not json' > fp-bad.json
fingerprints fp-expsig.json "$EXPSIG" "file://$WORK/expsig.pub"
V() { "$VERIFY" --fingerprints-url "file://$WORK/$1" "${@:2}"; }

expect ok 'a valid signature' V fp.json t.tar.gz t.tar.gz.asc
expect fail 'a signature that has expired' V fp-expsig.json t.tar.gz expsig.asc
expect ok 'the message of an expired signature says so' bash -c "'$VERIFY' --fingerprints-url file://$WORK/fp-expsig.json t.tar.gz expsig.asc 2>&1 | grep -q 'signature has expired'"
expect fail 'a changed tarball' V fp.json tampered.tar.gz t.tar.gz.asc
expect fail 'a signature made by another key' V fp.json t.tar.gz other.asc
expect fail 'the key at the listed place is not the listed key' V fp-wrong-key.json t.tar.gz t.tar.gz.asc
expect fail 'the listed fingerprint is not the key at the listed place' V fp-other-fingerprint.json t.tar.gz t.tar.gz.asc
expect fail 'the public key cannot be downloaded' V fp-no-key.json t.tar.gz t.tar.gz.asc
expect fail 'the list has no tarball key' V fp-no-tarball.json t.tar.gz t.tar.gz.asc
expect ok 'the active key is used when a retired key is listed before it' V fp-retired-first.json t.tar.gz t.tar.gz.asc
expect fail 'a signature made by the retired key fails' V fp-retired-first.json t.tar.gz other.asc
expect fail 'the list has only a revoked tarball key' V fp-only-retired.json t.tar.gz t.tar.gz.asc
expect fail 'the list is not json' V fp-bad.json t.tar.gz t.tar.gz.asc
expect fail 'the list cannot be downloaded' V missing.json t.tar.gz t.tar.gz.asc
expect fail 'a missing signature' V fp.json t.tar.gz missing.asc
expect fail 'a missing tarball' V fp.json missing.tar.gz t.tar.gz.asc
expect fail 'no arguments' "$VERIFY"

# A revoked key and an expired key (fixtures made once: see fixtures/README.md) still give VALIDSIG.
for K in revoked expired; do
  fingerprints "fp-$K.json" "$(cat "$HERE/fixtures/$K.fpr")" "file://$HERE/fixtures/$K.pub"
  expect fail "a signature of a $K key" V "fp-$K.json" "$HERE/fixtures/fixture-data.txt" "$HERE/fixtures/$K.asc"
done

# a server that fails twice with a server error, then serves the files: the downloads are retried
cat > flaky.py << 'PY'
import http.server, sys
count = 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        count += 1
        if count <= 2:
            self.send_response(503)
            self.end_headers()
            return
        data = open(sys.argv[2] + self.path, "rb").read()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
print(server.server_port, flush=True)
server.serve_forever()
PY
python3 flaky.py 0 "$WORK" > flaky.port &
FLAKY_PID=$!
for _ in $(seq 1 50); do [[ -s flaky.port ]] && break; sleep 0.1; done
PORT=$(cat flaky.port)
fingerprints fp-flaky.json "$GOOD" "http://127.0.0.1:$PORT/good.pub"
RETRY_DELAY=0 expect ok 'a server error is retried' "$VERIFY" --fingerprints-url "http://127.0.0.1:$PORT/fp-flaky.json" t.tar.gz t.tar.gz.asc
kill "$FLAKY_PID" 2> /dev/null

printf '%s passed, %s failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
