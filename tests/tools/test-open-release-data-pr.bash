#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# test-open-release-data-pr.bash - run tools/open-release-data-pr.bash in a clone of a local repository, with a stub in
# place of the gh command. It needs no secrets and no network.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OPEN="$HERE/../../tools/open-release-data-pr.bash"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

check() { # check <description> <command...>: passes if the command succeeds
  local WHAT=$1
  shift
  if "$@" > "$WORK/out.txt" 2>&1; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAILED: %s\n' "$WHAT"
    sed 's/^/    /' "$WORK/out.txt"
  fi
  cp "$WORK/out.txt" "$WORK/last.txt"
}

said() { # said <description> <text>: passes if the output of the last run holds the text
  if grep -q -F -- "$2" "$WORK/last.txt"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAILED: %s\n' "$1"
    sed 's/^/    /' "$WORK/last.txt"
  fi
}

fails() { # fails <command...>: passes if the command fails
  ! "$@"
}

# Stub gh: "pr list" prints $GH_PRS (a json list) through the --jq expression it is given, "repo view" prints an
# owner, "pr create" records its arguments. GH_FAIL makes "pr list" fail.
mkdir "$WORK/bin"
cat > "$WORK/bin/gh" << 'STUB'
#!/bin/bash
echo "gh $*" >> "$GH_LOG"
JQ=
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  [[ ${ARGS[$i]} = --jq ]] && JQ=${ARGS[$((i + 1))]}
done
case "$1 $2" in
  'pr list')
    [[ -z ${GH_FAIL:-} ]] || { echo 'gh: HTTP 502' >&2; exit 1; }
    echo "${GH_PRS:-[]}" | jq -r "$JQ" ;;
  'repo view') echo '{"owner": {"login": "newrelic"}}' | jq -r "$JQ" ;;
  'pr create') echo 'https://github.com/newrelic/newrelic-php-agent/pull/1' ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export GH_LOG="$WORK/gh.log"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

BRANCH=release-data/add-tarball-hashes-1.2.3.4
BODY="$WORK/body.md"
echo 'the description' > "$BODY"

git init -q --bare -b main "$WORK/origin.git"
git init -q -b main "$WORK/seed"
mkdir "$WORK/seed/release-data"
echo '{"v": 0}' > "$WORK/seed/release-data/a.json"
echo '{"v": 0}' > "$WORK/seed/release-data/b.json"
git -C "$WORK/seed" add -A
git -C "$WORK/seed" commit -q -m seed
git -C "$WORK/seed" remote add origin "$WORK/origin.git"
git -C "$WORK/seed" push -q origin main

# newclone <name>: a fresh clone of the repository, in $WORK/<name>
newclone() {
  git clone -q "$WORK/origin.git" "$WORK/$1" 2> /dev/null
  : > "$GH_LOG"
}

# remote_branch_exists: the branch is on the origin
remote_branch_exists() { git -C "$WORK/origin.git" rev-parse -q --verify "refs/heads/$BRANCH" > /dev/null; }
reset_origin() { git -C "$WORK/origin.git" branch -q -D "$BRANCH" 2> /dev/null || true; }
# run <clone> <args...>: run the script in the clone
run() { local C=$1; shift; (cd "$WORK/$C" && "$OPEN" "$@"); }
created() { grep -q '^gh pr create' "$GH_LOG"; }

# no change: nothing is pushed and nothing is opened
newclone c1
check 'no change: succeeds' run c1 --branch "$BRANCH" --title T --body-file "$BODY" release-data
said 'no change: says so' 'already hold these entries'
check 'no change: no branch is pushed' fails remote_branch_exists
check 'no change: no gh call' test ! -s "$GH_LOG"

# a change and no pull request: push the branch and open the pull request
reset_origin
newclone c2
echo '{"v": 1}' > "$WORK/c2/release-data/a.json"
GH_PRS='[]' check 'new pull request: succeeds' run c2 --branch "$BRANCH" --title 'chore: add hashes' --body-file "$BODY" release-data
check 'new pull request: the branch is pushed' remote_branch_exists
check 'new pull request: the commit message is the title' test "$(git -C "$WORK/origin.git" log -1 --format=%s "refs/heads/$BRANCH")" = 'chore: add hashes'
check 'new pull request: the commit holds the change' test "$(git -C "$WORK/origin.git" show "refs/heads/$BRANCH:release-data/a.json")" = '{"v": 1}'
check 'new pull request: opened against main from owner:branch' grep -q -F "gh pr create --base main --head newrelic:$BRANCH --title chore: add hashes --body-file $BODY" "$GH_LOG"

# --commit-message and --base
reset_origin
newclone c3
echo '{"v": 1}' > "$WORK/c3/release-data/a.json"
check 'options: succeeds' run c3 --branch "$BRANCH" --title T --body-file "$BODY" --base release --commit-message 'the message' release-data
check 'options: the commit message is the given one' test "$(git -C "$WORK/origin.git" log -1 --format=%s "refs/heads/$BRANCH")" = 'the message'
check 'options: the base is the given one' grep -q -F -- '--base release ' "$GH_LOG"

# a new file that git does not know yet is a change
reset_origin
newclone c4
echo '{"v": 1}' > "$WORK/c4/release-data/new.json"
check 'new file: succeeds' run c4 --branch "$BRANCH" --title T --body-file "$BODY" release-data
check 'new file: the file is in the commit' test "$(git -C "$WORK/origin.git" show "refs/heads/$BRANCH:release-data/new.json")" = '{"v": 1}'

# seed_branch <clone> <file> <content>: an earlier attempt that pushed the branch with this content
seed_branch() {
  reset_origin
  newclone "$1"
  echo "$3" > "$WORK/$1/release-data/$2"
  GH_PRS='[]' run "$1" --branch "$BRANCH" --title T --body-file "$BODY" release-data > /dev/null 2>&1
}

# an open pull request whose branch already holds the files: nothing to do
seed_branch c5a a.json '{"v": 1}'
newclone c5
echo '{"v": 1}' > "$WORK/c5/release-data/a.json"
GH_PRS='[{"number": 1, "isCrossRepository": false}]' check 'open pull request, same files: succeeds' run c5 --branch "$BRANCH" --title T --body-file "$BODY" release-data
said 'open pull request, same files: says so' 'already has these entries'
check 'open pull request, same files: no pull request is opened' fails created
BEFORE=$(git -C "$WORK/origin.git" rev-parse "refs/heads/$BRANCH")
check 'open pull request, same files: the branch is not touched' test "$(git -C "$WORK/origin.git" rev-parse "refs/heads/$BRANCH")" = "$BEFORE"

# an open pull request whose branch holds another file: the branch is replaced, no second pull request
seed_branch c6a a.json '{"v": 1}'
newclone c6
echo '{"v": 2}' > "$WORK/c6/release-data/b.json"
GH_PRS='[{"number": 1, "isCrossRepository": false}]' check 'open pull request, other files: succeeds' run c6 --branch "$BRANCH" --title T --body-file "$BODY" release-data
said 'open pull request, other files: says it updated the branch' 'updated the branch of the open pull request'
check 'open pull request, other files: the branch holds the files of this run' test "$(git -C "$WORK/origin.git" show "refs/heads/$BRANCH:release-data/b.json")" = '{"v": 2}'
check 'open pull request, other files: the file of the earlier attempt is gone' test "$(git -C "$WORK/origin.git" show "refs/heads/$BRANCH:release-data/a.json")" = '{"v": 0}'
check 'open pull request, other files: no pull request is opened' fails created

# --on-differ fail: an open pull request whose branch holds other content stops the run and leaves the branch alone
seed_branch c6b a.json '{"v": 1}'
newclone c6c
echo '{"v": 2}' > "$WORK/c6c/release-data/b.json"
BEFORE=$(git -C "$WORK/origin.git" rev-parse "refs/heads/$BRANCH")
GH_PRS='[{"number": 1, "isCrossRepository": false}]' check 'on-differ fail, other files: fails' fails run c6c --branch "$BRANCH" --title T --body-file "$BODY" --on-differ fail release-data
said 'on-differ fail, other files: the error says the branch holds other content' 'holds other content than this run'
check 'on-differ fail, other files: the branch is not touched' test "$(git -C "$WORK/origin.git" rev-parse "refs/heads/$BRANCH")" = "$BEFORE"
check 'on-differ fail, other files: no pull request is opened' fails created

# --on-differ fail: the same files, no pull request and a fork pull request are not a difference
seed_branch c6d a.json '{"v": 1}'
newclone c6e
echo '{"v": 1}' > "$WORK/c6e/release-data/a.json"
GH_PRS='[{"number": 1, "isCrossRepository": false}]' check 'on-differ fail, same files: succeeds' run c6e --branch "$BRANCH" --title T --body-file "$BODY" --on-differ fail release-data
reset_origin
newclone c6f
echo '{"v": 1}' > "$WORK/c6f/release-data/a.json"
GH_PRS='[]' check 'on-differ fail, no pull request: succeeds' run c6f --branch "$BRANCH" --title T --body-file "$BODY" --on-differ fail release-data
check 'on-differ fail, no pull request: the pull request is opened' created
reset_origin
newclone c6g
echo '{"v": 1}' > "$WORK/c6g/release-data/a.json"
GH_PRS='[{"number": 9, "isCrossRepository": true}]' check 'on-differ fail, fork pull request: succeeds' run c6g --branch "$BRANCH" --title T --body-file "$BODY" --on-differ fail release-data
check 'on-differ fail, fork pull request: our own pull request is opened' created

# a pull request from a fork with the same branch name is not the pull request of this branch
reset_origin
newclone c7
echo '{"v": 1}' > "$WORK/c7/release-data/a.json"
GH_PRS='[{"number": 9, "isCrossRepository": true}]' check 'fork pull request: succeeds' run c7 --branch "$BRANCH" --title T --body-file "$BODY" release-data
said 'fork pull request: a warning names it' '::warning::1 open pull request(s) from a fork'
check 'fork pull request: the branch is pushed' remote_branch_exists
check 'fork pull request: our own pull request is opened' created

# a fork pull request next to ours does not hide ours
seed_branch c8a a.json '{"v": 1}'
newclone c8
echo '{"v": 1}' > "$WORK/c8/release-data/a.json"
GH_PRS='[{"number": 9, "isCrossRepository": true}, {"number": 1, "isCrossRepository": false}]' check 'fork and own pull request: succeeds' run c8 --branch "$BRANCH" --title T --body-file "$BODY" release-data
said 'fork and own pull request: the fork is reported' 'from a fork'
check 'fork and own pull request: no pull request is opened' fails created

# gh cannot list the pull requests: fail, push nothing
reset_origin
newclone c9
echo '{"v": 1}' > "$WORK/c9/release-data/a.json"
GH_FAIL=1 check 'gh fails: the script fails' fails run c9 --branch "$BRANCH" --title T --body-file "$BODY" release-data
check 'gh fails: nothing is pushed' fails remote_branch_exists

# arguments
check 'no branch is refused' fails run c9 --title T --body-file "$BODY" release-data
check 'no title is refused' fails run c9 --branch "$BRANCH" --body-file "$BODY" release-data
check 'a missing body file is refused' fails run c9 --branch "$BRANCH" --title T --body-file "$WORK/none.md" release-data
check 'an unknown --on-differ value is refused' fails run c9 --branch "$BRANCH" --title T --body-file "$BODY" --on-differ nope release-data
check 'no path is refused' fails run c9 --branch "$BRANCH" --title T --body-file "$BODY"
check 'an unknown option is refused' fails run c9 --nope x --branch "$BRANCH" --title T --body-file "$BODY" release-data

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
