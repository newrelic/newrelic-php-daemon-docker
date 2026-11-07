#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# digest-entry.bash - print the entry of a published daemon image for the list of image digests
#                     (release-data/daemon-image-digests.json in newrelic-php-agent).
#
# usage: digest-entry.bash <tag> [<expected-digest>]
#
# <tag> is the image tag, which is the agent version without the build number, e.g. 12.12.0.
# The digest of the tag and the digest of the image of each platform are taken from the manifest
# that the registry serves, and the time of the last push from the Docker Hub API. The script fails
# if the registry and the API disagree about the digest, or if the digest is not <expected-digest>
# (the digest that the push reported). Attestation manifests are not platforms and are skipped.
#
# The API can take a few seconds to show a push, so a different digest is checked again up to
# HUB_TRIES times, HUB_WAIT seconds apart, before the script fails.
#
# Environment (for tests): IMAGE (default newrelic/php-daemon), HUB_API (default
# https://hub.docker.com/v2/repositories/newrelic/php-daemon/tags), HUB_TRIES (default 6),
# HUB_WAIT (default 10).

set -euo pipefail

IMAGE=${IMAGE:-newrelic/php-daemon}
HUB_API=${HUB_API:-https://hub.docker.com/v2/repositories/newrelic/php-daemon/tags}
HUB_TRIES=${HUB_TRIES:-6}
HUB_WAIT=${HUB_WAIT:-10}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $(basename "$0") <tag> [<expected-digest>]" >&2
  exit 2
fi
TAG=$1
EXPECTED=${2:-}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ $TAG =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "not an image tag: $TAG"

# The manifest list (the index) of the tag, byte for byte; its hash is the digest of the tag.
RAW=$(docker buildx imagetools inspect "$IMAGE:$TAG" --raw) || fail "cannot read the manifest of $IMAGE:$TAG"
DIGEST="sha256:$(printf '%s' "$RAW" | sha256sum | awk '{print $1}')"

[[ -z $EXPECTED || $EXPECTED = "$DIGEST" ]] || fail "the digest of $IMAGE:$TAG is $DIGEST, not the expected $EXPECTED"

# What the Docker Hub API says about the tag: its digest and when it was last pushed.
for TRY in $(seq 1 "$HUB_TRIES"); do
  INFO=$(curl -fsS --retry 3 --retry-delay "$HUB_WAIT" "$HUB_API/$TAG") || fail "cannot read the tag $TAG from $HUB_API"
  API_DIGEST=$(jq -r '.digest' <<< "$INFO")
  [[ $API_DIGEST = "$DIGEST" ]] && break
  [[ $TRY -eq $HUB_TRIES ]] || sleep "$HUB_WAIT"
done
[[ $API_DIGEST = "$DIGEST" ]] || fail "the registry has $DIGEST for $IMAGE:$TAG but the Docker Hub API has $API_DIGEST"
PUSHED=$(jq -r '.tag_last_pushed' <<< "$INFO")
[[ $PUSHED =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || fail "no push time for $TAG: $PUSHED"

jq -S -n --arg version "$TAG" --arg digest "$DIGEST" --arg pushed "$PUSHED" --argjson index "$RAW" '
  {
    version: $version,
    digest: $digest,
    pushed: $pushed,
    platforms: (
      [ $index.manifests[]
        | select(.platform.os != "unknown")
        | { key: (.platform.os + "/" + .platform.architecture + (if .platform.variant then "/" + .platform.variant else "" end)),
            value: .digest } ]
      | from_entries
    )
  }'
