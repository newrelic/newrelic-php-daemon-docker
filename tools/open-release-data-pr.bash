#!/usr/bin/env bash

#
# Copyright 2026 New Relic Corporation. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#

# open-release-data-pr.bash - push the changes of files in a clone of the agent repository to a branch and open
#                             a pull request, or update the pull request that an earlier attempt opened.
#                             Used by the publish-digest action.

### Usage: open-release-data-pr.bash --branch <name> --title <text> --body-file <file> \
###                                  [--base <branch>] [--commit-message <text>] [--on-differ fail|replace] <path>...
###        open-release-data-pr.bash [--help]
###
### Arguments:
###   <path>...               the files or directories (relative to the current directory, a clone of the agent
###                           repository) whose changes go into the pull request
###
### Options:
###   --branch <name>         the branch to push the changes to
###   --title <text>          the title of the pull request
###   --body-file <file>      the file that holds the description of the pull request
###   --base <branch>         the branch the pull request is opened against (default: main)
###   --commit-message <text> the message of the commit (default: the title)
###   --on-differ fail|replace what to do if a pull request from the branch is open and its branch holds other
###                           content than the files of this run: replace the branch (default) or fail
###   --help                  print this message and exit
###
### Run it in the clone with GH_TOKEN set to a token that can push and open pull requests. It does nothing if the
### paths hold no change. Only a pull request from a branch of this repository counts: gh matches a branch name
### whatever repository the pull request comes from, so a pull request from a fork with the same branch name is
### reported and left alone. If a pull request from the branch is open and the branch already holds these
### files, nothing is done; if it holds other content (an earlier attempt of another run), the branch is replaced
### with the commit of this run, which updates the pull request, or with --on-differ fail the script stops with
### an error and leaves the branch as it is. If none is open, the pull request is opened with the branch as the head.

set -e
set -o pipefail

# usage [<error message>]: print the usage text (the ### lines above) and exit
usage() {
  local exitstatus=0
  if [[ $# -gt 0 ]]; then
    printf '%s: %s\n\n' "$(basename "$0")" "$*" >&2
    exitstatus=2
  fi
  grep '^###' "$0" | cut -c '5-' >&2
  exit $exitstatus
}

BRANCH=
TITLE=
BODY_FILE=
BASE=main
COMMIT_MESSAGE=
ON_DIFFER=replace

while getopts ':-:' OPTNAME; do
  case $OPTNAME in
    -)
      case $OPTARG in
        help) usage ;;
        branch) BRANCH=${!OPTIND}; OPTIND=$((OPTIND + 1)) ;;
        title) TITLE=${!OPTIND}; OPTIND=$((OPTIND + 1)) ;;
        body-file) BODY_FILE=${!OPTIND}; OPTIND=$((OPTIND + 1)) ;;
        base) BASE=${!OPTIND}; OPTIND=$((OPTIND + 1)) ;;
        commit-message) COMMIT_MESSAGE=${!OPTIND}; OPTIND=$((OPTIND + 1)) ;;
        on-differ) ON_DIFFER=${!OPTIND}; OPTIND=$((OPTIND + 1)) ;;
        *) usage "illegal option -- ${OPTARG%=*}" ;;
      esac
      ;;
    \?) usage "illegal option -- $OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

[[ -n $BRANCH && -n $TITLE && -f $BODY_FILE ]] || usage '--branch, --title and --body-file (an existing file) are required'
[[ $ON_DIFFER = fail || $ON_DIFFER = replace ]] || usage '--on-differ is fail or replace'
[[ $# -gt 0 ]] || usage 'at least one path is required'
[[ -n $COMMIT_MESSAGE ]] || COMMIT_MESSAGE=$TITLE
PATHS=("$@")

if [[ -z $(git status --porcelain -- "${PATHS[@]}") ]]; then
  echo "::notice::${PATHS[*]} already hold these entries"
  exit 0
fi

# A pull request from a fork is not the pull request of this branch.
SAME=$(gh pr list --head "$BRANCH" --state open --json number,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)] | length')
FORKS=$(gh pr list --head "$BRANCH" --state open --json number,isCrossRepository --jq '[.[] | select(.isCrossRepository)] | length')
if [[ $FORKS != 0 ]]; then
  echo "::warning::$FORKS open pull request(s) from a fork use the branch name $BRANCH; they are not the pull request of this run and are left alone"
fi

if [[ $SAME != 0 ]]; then
  if git fetch -q origin "$BRANCH" && git diff --quiet FETCH_HEAD -- "${PATHS[@]}"; then
    echo "::notice::the open pull request from $BRANCH already has these entries"
    exit 0
  fi
  if [[ $ON_DIFFER = fail ]]; then
    echo "::error::the open pull request from $BRANCH holds other content than this run. Close it or update its branch by hand; the branch was not changed."
    exit 1
  fi
fi

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git checkout -q -b "$BRANCH"
git add -- "${PATHS[@]}"
git commit -q -m "$COMMIT_MESSAGE"
git push --force origin "$BRANCH"

if [[ $SAME != 0 ]]; then
  echo "::notice::updated the branch of the open pull request from $BRANCH with the entries of this attempt"
  exit 0
fi

OWNER=$(gh repo view --json owner --jq .owner.login)
gh pr create --base "$BASE" --head "$OWNER:$BRANCH" --title "$TITLE" --body-file "$BODY_FILE"
