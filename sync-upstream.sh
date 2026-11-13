#!/usr/bin/env bash
# Merge the latest upstream into the current checkout (the fork's main).
# Upstream's own workflows are dropped: they need upstream's secrets and only fail
# on the fork. The only workflow on main is .github/workflows/fork-main.yml.
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
drop_upstream_workflows() {
	{ git ls-files .github/workflows | grep -v '^\.github/workflows/fork-main\.yml$' || true; } | xargs -r git rm -q -f --ignore-unmatch --
	{ git ls-files --others --exclude-standard .github/workflows || true; } | xargs -r rm -f
}
if ! git merge --quiet --no-ff --no-commit "$up" >/dev/null 2>&1; then
	# Conflicts in upstream workflows are expected (main deleted them); drop those.
	{ git diff --name-only --diff-filter=U | grep '^\.github/workflows/' | grep -v 'fork-main\.yml$' || true; } | xargs -r git rm -q --
	left=$(git diff --name-only --diff-filter=U)
	if [ -n "$left" ]; then
		echo "CONFLICT merging upstream ${up:0:10} into main:" >&2
		echo "$left" | sed 's/^/    /' >&2
		git merge --abort
		echo "Resolve by hand: merge refs/fork-main/upstream into main, fix the files, push." >&2
		exit 2
	fi
fi
drop_upstream_workflows
git commit -q -m "Merge upstream $branch (${up:0:10})"
echo "merged upstream ${up:0:10}: $(git rev-parse HEAD)"
