#!/usr/bin/env sh

# usage: ./merge_script_then_plumelib.sh [--verbose] <clone_dir> <branch-1> <branch-2> <merge_script> <plumelib_strategy>
# First runs a merge script, then runs Plume-lib Merging to improve the result of the merge script.
# <clone_dir> must contain a clone of a repository.
# <merge_script> takes arguments <clone_dir> <branch-1> <branch-2>.
# Return code is 0 for merge success, 1 for merge failure, 2 for script failure.
# For merge failure, also outputs "Conflict" and aborts the merge.

set -o nounset

VERBOSE=
## Enable for debugging
# VERBOSE=--verbose

if [ "$1" = "--verbose" ] ; then
  VERBOSE="$1"
  shift
fi

if [ "$#" -ne 5 ]; then
  echo "Usage: $0 [--verbose] CLONE_DIR BRANCH1 BRANCH2 MERGE_SCRIPT PLUMELIB_STRATEGY" >&2
  exit 2
fi

clone_dir=$1
branch1=$2
branch2=$3
merge_script=$4
plumelib_strategy=$5 # e.g., "--only-adjacent"

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd -P)"


## Perform merge

echo "$0: Merging $branch1 and $branch2 with merge_script=$merge_script and plumelib_strategy=$plumelib_strategy"

cd "$clone_dir" || { echo "$0: cannot cd to $clone_dir"; exit 2; }

if [ -n "$VERBOSE" ] ; then
  echo "$0: about to run: git checkout $branch1 in $(pwd)"
fi
git checkout "$branch1" --force
if [ -n "$VERBOSE" ] ; then
  echo "$0: ran: git checkout $branch1 in $(pwd)"
fi
git config --local merge.conflictstyle diff3
git config --local mergetool.prompt false

if [ -n "$VERBOSE" ] ; then
  echo "$0: about to run: $merge_script $clone_dir $branch1 $branch2 in $(pwd)"
fi

# shellcheck disable=SC2086
$merge_script "$clone_dir" "$branch1" "$branch2"

if [ -n "$VERBOSE" ] ; then
  echo "$0: ran: $merge_script $clone_dir $branch1 $branch2 in $(pwd)"
fi

## Now, run Plume-lib Merging to improve the result of `$merge_script`.

git config --local merge.tool merge-plumelib
# shellcheck disable=SC2016
git config --local mergetool.merge-plumelib.cmd "$SCRIPTDIR/merging/src/main/sh/merge-tool.sh $VERBOSE $plumelib_strategy"' ${LOCAL} ${BASE} ${REMOTE} ${MERGED}'
git config --local mergetool.merge-plumelib.trustExitCode true

case "$plumelib_strategy" in
    *"--no-java-imports"* | *"--only-adjacent"* | *"--only-annotations"* | *"--only-version-numbers"*)
        # The "imports" merger is not being used, so don't use the "--all" command-line option.
        all_arg=""
        ;;
    *)
        # The "imports" merger is being used, so use the "--all" command-line option.
        all_arg="--all"
        ;;
esac

if [ -n "$VERBOSE" ] ; then
  echo "$0: about to run: git-mergetool.sh $all_arg --tool=merge-plumelib in $(pwd)"
  git-mergetool.sh --verbose $all_arg --tool=merge-plumelib
  echo "$0: ran: git-mergetool.sh $all_arg --tool=merge-plumelib in $(pwd)"
else
  git-mergetool.sh $all_arg --tool=merge-plumelib
fi

# Check if there are still conflicts
diffs=$(git diff --name-only --diff-filter=U | sort)
if [ -z "$diffs" ]; then
    git add .
    if [ -n "$VERBOSE" ] ; then
      echo "$0: about to run: git commit in $(pwd)"
    fi
    git commit -m "Resolved conflicts by calling: git-mergetool.sh $all_arg --tool=merge-plumelib"
    if [ -n "$VERBOSE" ] ; then
      echo "$0: ran: git commit in $(pwd)"
    fi
    exit 0
fi
echo "$0: exiting with status 1"
echo "$0: diffs=$diffs"
echo "$0: Conflict after running in $(pwd):"
echo "  $merge_script $clone_dir $branch1 $branch2"
echo "  git-mergetool.sh $all_arg --tool=merge-plumelib"
exit 1
