#!/usr/bin/env bash
# Rebuild this fork's generated branch (usually `main`) from scratch:
# the upstream branch, plus every patch branch listed in fork.conf, merged in order.
#
# Usage (from any checkout of the fork, `origin` = the fork):
#   ./generate-main.sh [--config FILE] [--dry-run | --preview | --push] [--sync-mirror]
#
#   --dry-run      build the branch locally and report (default)
#   --preview      push the result to <target>-preview instead of <target>
#   --push         force-push the result to <target> (with lease on the old tip)
#   --sync-mirror  also fast-forward the mirror branch to upstream (never forced)
#   --allow-drop   push even if commits on the old <target> are missing from the result
#   --config FILE  read this config instead of origin/fork-tools:fork.conf
#
# Exit codes: 0 ok, 2 merge conflict, 3 missing branch, 4 would drop commits, 1 other error.
set -euo pipefail

mode=dry-run
sync_mirror=0
allow_drop=0
config=""
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) mode=dry-run ;;
		--preview) mode=preview ;;
		--push) mode=push ;;
		--sync-mirror) sync_mirror=1 ;;
		--allow-drop) allow_drop=1 ;;
		--config) config="$2"; shift ;;
		-h|--help) sed -n '2,17p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 1 ;;
	esac
	shift
done

repo=$(git rev-parse --show-toplevel)
cd "$repo"

git fetch --quiet origin '+refs/heads/*:refs/remotes/origin/*'

if [ -n "$config" ]; then
	conf=$(cat "$config")
else
	conf=$(git show origin/fork-tools:fork.conf)
fi

upstream_url=""; upstream_branch=""; target=main; mirror=""
patches=()
while read -r key value rest; do
	case "$key" in
		''|\#*) continue ;;
		upstream) upstream_url="$value"; upstream_branch="${rest%% *}" ;;
		target) target="$value" ;;
		mirror) mirror="$value" ;;
		patch) patches+=("$value") ;;
		*) echo "fork.conf: unknown key '$key'" >&2; exit 1 ;;
	esac
done <<< "$conf"

[ -n "$upstream_url" ] && [ -n "$upstream_branch" ] || { echo "fork.conf: missing 'upstream <url> <branch>'" >&2; exit 1; }

upstream_ref=refs/fork-main/upstream
git fetch --quiet "$upstream_url" "+refs/heads/$upstream_branch:$upstream_ref"
upstream_sha=$(git rev-parse "$upstream_ref")
echo "upstream  $upstream_url $upstream_branch @ ${upstream_sha:0:10}"

for p in "${patches[@]}"; do
	git rev-parse --verify --quiet "refs/remotes/origin/$p" >/dev/null || { echo "missing patch branch on the fork: $p" >&2; exit 3; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/fork-main.XXXXXX")
cleanup() { git worktree remove --force "$work" >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT
git worktree add --quiet --detach "$work" "$upstream_sha"

# Commit identity for the merge commits, if the checkout has none.
git -C "$work" config user.name >/dev/null || export GIT_AUTHOR_NAME="Fork main generator" GIT_COMMITTER_NAME="Fork main generator"
git -C "$work" config user.email >/dev/null || export GIT_AUTHOR_EMAIL="fork-main@users.noreply.github.com" GIT_COMMITTER_EMAIL="fork-main@users.noreply.github.com"

for p in "${patches[@]}"; do
	sha=$(git rev-parse "refs/remotes/origin/$p")
	if git -C "$work" merge-base --is-ancestor "$sha" HEAD; then
		echo "patch     $p @ ${sha:0:10}: already contained (merged upstream?), skipped"
		continue
	fi
	if out=$(git -C "$work" merge --no-ff --no-edit -m "Fork: merge $p" "$sha" 2>&1); then
		echo "patch     $p @ ${sha:0:10}: merged"
	elif git -C "$work" rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
		echo "CONFLICT  $p @ ${sha:0:10} does not merge cleanly onto upstream + earlier patches:" >&2
		git -C "$work" diff --name-only --diff-filter=U | sed 's/^/            /' >&2
		git -C "$work" merge --abort || true
		echo "Rebase $p onto upstream/$upstream_branch (or reorder fork.conf) and run again. $target was not changed." >&2
		exit 2
	else
		echo "merge of $p failed: $out" >&2
		echo "(A shallow clone can cause this; run 'git fetch --unshallow origin' first.)" >&2
		exit 1
	fi
done

result=$(git -C "$work" rev-parse HEAD)
old=$(git rev-parse --verify --quiet "refs/remotes/origin/$target" || true)
echo "result    ${result:0:10} (${#patches[@]} patch branches on upstream)"

if [ -n "$old" ] && [ "$(git rev-parse "$old^{tree}")" = "$(git rev-parse "$result^{tree}")" ]; then
	same_tree=1
	echo "$target    ${old:0:10} already has the same content"
else
	same_tree=0
fi

# Safety net: refuse to drop work. Any non-merge commit on the old branch whose change
# is not in the result (by patch id) was added outside fork.conf, for example a PR
# merged straight into the generated branch. Add its branch to fork.conf, or pass
# --allow-drop if you removed a patch on purpose.
if [ -n "$old" ] && [ "$allow_drop" = 0 ]; then
	dropped=$(git log --no-merges --cherry-pick --right-only --format='%h %s' "$result...$old")
	if [ -n "$dropped" ]; then
		echo "DROPPED   these commits on $target would be lost:" >&2
		echo "$dropped" | sed 's/^/            /' >&2
		if [ "$mode" != dry-run ]; then
			echo "Add their branch to fork.conf, or rerun with --allow-drop. $target was not changed." >&2
			exit 4
		fi
	fi
fi

case "$mode" in
	dry-run)
		echo "dry run: nothing pushed. Inspect with: git log --oneline --graph $result" ;;
	preview)
		git push --force origin "$result:refs/heads/$target-preview"
		echo "pushed to $target-preview" ;;
	push)
		if [ "$same_tree" = 1 ]; then
			echo "$target unchanged"
		elif [ -n "$old" ]; then
			git push --force-with-lease="refs/heads/$target:$old" origin "$result:refs/heads/$target"
			echo "$target: ${old:0:10} -> ${result:0:10}"
		else
			git push origin "$result:refs/heads/$target"
			echo "$target created at ${result:0:10}"
		fi ;;
esac

if [ "$sync_mirror" = 1 ] && [ -n "$mirror" ]; then
	mirror_old=$(git rev-parse --verify --quiet "refs/remotes/origin/$mirror" || true)
	if [ "$mirror_old" = "$upstream_sha" ]; then
		echo "mirror    $mirror already at upstream"
	elif [ -z "$mirror_old" ] || git merge-base --is-ancestor "$mirror_old" "$upstream_sha"; then
		if [ "$mode" = dry-run ]; then
			echo "mirror    $mirror would fast-forward to ${upstream_sha:0:10}"
		else
			git push origin "$upstream_sha:refs/heads/$mirror"
			echo "mirror    $mirror fast-forwarded to ${upstream_sha:0:10}"
		fi
	else
		echo "mirror    $mirror has commits upstream does not; left alone" >&2
	fi
fi
