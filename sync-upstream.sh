#!/usr/bin/env bash
# Merge the latest upstream into the current checkout (a new branch made from the fork's main).
# Upstream's workflows merge in like any other file, so the fork keeps running upstream's
# checks next to .github/workflows/fork-main.yml.
#
# Usage: sync-upstream.sh <upstream-url> <upstream-branch>
# Exit codes: 0 merged or already up to date, 2 conflict (nothing committed), 1 other error.
set -euo pipefail
url=$1; branch=$2
[ "$(git rev-parse --is-shallow-repository)" = false ] || { echo "shallow clone: run 'git fetch --unshallow origin' first" >&2; exit 1; }
git fetch --quiet "$url" "+refs/heads/$branch:refs/fork-main/upstream"
up=$(git rev-parse refs/fork-main/upstream)
if git merge-base --is-ancestor "$up" HEAD; then
	echo "already up to date with upstream ${up:0:10}"
	exit 0
fi
if ! git merge --quiet --no-ff --no-commit "$up" >/dev/null 2>&1; then
	left=$(git diff --name-only --diff-filter=U)
	git merge --abort 2>/dev/null || true
	if [ -z "$left" ]; then
		echo "merging upstream ${up:0:10} failed without a conflict; run 'git merge refs/fork-main/upstream' to see why" >&2
		exit 1
	fi
	echo "CONFLICT merging upstream ${up:0:10} into main:" >&2
	echo "$left" | sed 's/^/    /' >&2
	echo "Resolve by hand: merge refs/fork-main/upstream into main, fix the files, push." >&2
	exit 2
fi
git commit -q -m "Merge upstream $branch (${up:0:10})"
echo "merged upstream ${up:0:10}: $(git rev-parse HEAD)"
