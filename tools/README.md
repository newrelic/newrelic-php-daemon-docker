# Tools

Scripts that the image workflows run. Their tests are in [`tests/tools`](../tests/tools) and run in the `pr_runner`
workflow; they need `bash`, `jq`, `gpg` and python3 with `jsonschema` (install it into a virtual environment from the hashed
[`requirements.txt`](requirements.txt), as the workflows do), and no secrets:

```
python3 -m venv venv && venv/bin/pip install --require-hashes -r tools/requirements.txt
PATH="$PWD/venv/bin:$PATH"
for test in tests/tools/test-*.bash; do bash "$test"; done
python3 -m unittest discover -s tests/tools
```

## Building an image

- `update-docker-image.bash <version>` downloads the musl tarball of the agent version and its `.asc` signature from the
  download site (the public archive, `https://download.newrelic.com/php_agent/archive`; the environment variable `DOWNLOAD_ARCHIVE_URL` replaces it, which the tests use), calls `verify-tarball.bash`, and only then writes the
  SHA-256 hash of the tarball into the Dockerfile
  of the new image directory, commits and tags it. A missing signature or a failed check stops the script before any
  of that.
- `verify-tarball.bash [--fingerprints-url <url>] <tarball> <signature>` checks the detached signature against the
  tarball signing key. The fingerprint and the location of the public key come from
  `release-data/signing-key-fingerprints.json` in the agent repository (the entry for the `tarball` purpose); the key
  must have that fingerprint, and a revoked or expired key does not verify. No copy of the fingerprint or the key is kept in this
  repository, so a key change is made once, in the agent repository (and `main` of that repository is trusted for it).
- `push-docker-image.bash <version>` builds the image from the version's directory and pushes it.

## Recording the image digest

After `push-new-image` pushes an image, its `publish-digest` job adds the digest to
`release-data/daemon-image-digests.json` in the agent repository through a pull request that needs an approval from the
PHP agent team. The [`publish-digest`](../.github/workflows/publish-digest.yml) workflow does the same by hand for an
image that is already published (for example if the pull request could not be opened); it only shows the change unless
`dry-run` is unchecked. Both use the action in [`.github/actions/publish-digest`](../.github/actions/publish-digest/action.yml)
and the `release-data` environment, which holds the token that can open pull requests in the agent repository.
The environment has no required reviewers, because the agent repository's ruleset requires an approval from the PHP agent
team before the pull request can be merged. A re-run replaces the branch of the pull request (the action force-pushes it),
so publish one digest pull request at a time. Use `Re-run failed jobs` on `push-new-image`, never a full re-run: a full
re-run builds and pushes the tag again, and a recorded digest is never replaced, so the new digest fails `publish-digest`.
The by-hand workflow takes an optional `digest`, the one the push reported; without it the digest of the tag is not
cross-checked and the run warns.

- `open-release-data-pr.bash --branch <name> --title <text> --body-file <file> <path>...` runs in a clone of the agent
  repository and pushes the changed files to the branch and opens the pull request. It does nothing if the files have no
  change. Only an open pull request from a branch of the agent repository counts (`gh pr list --head` also matches a pull
  request from a fork with the same branch name, which is reported and left alone). If such a pull request is open and its
  branch already holds the files, it does nothing; if the branch holds other content (an earlier attempt, for example the tag
  was pushed again), `--on-differ fail` (what the action uses) stops with an error and leaves the branch alone, and the
  default `replace` replaces the branch with the commit of this run, which updates the pull request. Its test uses a local bare repository and a `gh` stub.
- `digest-entry.bash (--version <agent-version> | <tag>) [<expected-digest>]` prints the entry for a published tag (`--version 12.12.0.41` checks the four numbers, derives the tag `12.12.0` and warns when no expected digest was given; a caller that has the tag passes it instead): the digest of the tag and the
  digest of the image of each platform, read from the registry manifest, and the push time from the Docker Hub API. It fails if the two
  disagree or if the tag does not have the expected digest (the digest the push reported).
- `make-replacement-file.bash` builds the complete new `daemon-image-digests.json` from the public copy of the agent
  repository. The workflow uploads it as the artifact `replacement-release-data` with a note; if the pull request cannot
  be opened, copy it to `release-data/` in the agent repository and open the pull request by hand.
- `insert-release-data.py <data-file> <entry-file> <schema-file>` adds the entry and validates the result with the
  schema. A recorded digest is never replaced: the same entry leaves the file unchanged, and a different digest for the
  same tag stops with an error.
