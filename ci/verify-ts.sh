#!/usr/bin/env bash
# Check a generated main of anytype-ts: typecheck and lint pass, and no unit test
# fails that does not also fail on plain upstream. Run from the checkout of the result.
set -euo pipefail
base=${FORK_BASE:-refs/fork-main/upstream}
export NODE_OPTIONS=--max-old-space-size=8192

# Middleware protobufs for the pinned middleware version (same files update.sh installs).
mwv=$(cat middleware.version)
curl -fsSL -o addon.tar.gz "https://github.com/anyproto/anytype-heart/releases/download/v$mwv/js_v${mwv}_linux-amd64.tar.gz"
tar -zxf addon.tar.gz
rm -rf dist/lib/pb dist/lib/pkg dist/lib/protos addon.tar.gz grpc-server
mv protobuf/* dist/lib/
mkdir -p dist/lib/json/generated
[ -d json ] && mv json/* dist/lib/json/generated/
rm -rf protobuf json relations

bun install --frozen-lockfile --ignore-scripts
bash scripts/generate-protos.sh --from-dist

echo "::group::typecheck"; bun run typecheck; echo "::endgroup::"
echo "::group::lint"; bun run lint; echo "::endgroup::"

# Unit tests: upstream itself has failing tests, so only new failures count.
failing() { sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -E '^ *(×|✗|FAIL) ' | sed -E 's/ [0-9]+ms$//' | sort -u; }
bunx vitest run > /tmp/vitest-main.txt 2>&1 || true
tail -5 /tmp/vitest-main.txt
if ! grep -q 'failed' /tmp/vitest-main.txt; then exit 0; fi

wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" "$base"
ln -s "$PWD/node_modules" "$wt/node_modules"
rm -rf "$wt/dist/lib" && cp -r dist/lib "$wt/dist/lib"
cp src/ts/lib/api/service.ts "$wt/src/ts/lib/api/service.ts"
[ -d middleware ] && cp -r middleware "$wt/" || true
(cd "$wt" && bunx vitest run > /tmp/vitest-base.txt 2>&1 || true)
git worktree remove --force "$wt"

new=$(comm -23 <(failing /tmp/vitest-main.txt) <(failing /tmp/vitest-base.txt))
if [ -n "$new" ]; then
	echo "Tests failing on main but not on upstream:"
	echo "$new"
	exit 1
fi
echo "all failing tests also fail on upstream"
