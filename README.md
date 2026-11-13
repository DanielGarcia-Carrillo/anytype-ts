# Fork `main`: one big branch

`main` on this fork is the one branch for all fork work:

    upstream  +  every fork change, each as its own commit  +  upstream merged in over time

When a change is ready for upstream, cherry-pick its commit(s) onto a fresh branch from
upstream and open the PR from there. Nothing is pushed to the upstream repository
automatically, and only after Daniel has checked the change.

## Rules

- **One logical change per commit, with a clear message**, so it can be cherry-picked later.
  Fix-ups for an earlier change say which change they belong to.
- **Make the right change, even if it touches code another fork change touched.**
  There are no separate long-lived feature branches to keep apart any more.
- **Work lands through PRs into main** (short-lived `dgc--<title>` branches from main), or by
  pushing straight to main for small things. CI checks both.
- **Upstream comes in by merge, never by rebase or force-push**, so commit ids stay stable.
- No Linear issue references and no session links in commits or PRs.

## CI (`.github/workflows/fork-main.yml` on main; scripts on this `fork-tools` branch)

Upstream's own workflows are not on main: they need upstream's secrets and runners.

| Event | What happens |
| --- | --- |
| PR into main, push to main | Builds and tests the result. |
| "Run workflow" on the Actions tab | Merges the latest upstream into main, builds and tests it, and pushes main only if everything passes. A conflict or a failure leaves main as it was and turns the run red. |

There is no schedule: main takes upstream only when you run the workflow.

The checks (`ci/verify-*.sh`):
- **heart:** `go build ./...`, plus `go test` for every package the fork changes.
- **ts:** typecheck and lint, plus unit tests. Upstream already has failing tests, so only tests that pass on upstream and fail on main count.
- **kotlin:** `assembleDebug`, plus unit tests for every module the fork changes.

Needs the `FORK_TOKEN` secret (classic token: `repo`, `workflow`, `read:packages`).

## By hand

Merge upstream locally (full clone, on main):

    git fetch origin fork-tools && git archive origin/fork-tools | tar -x -C /tmp/fork-tools
    /tmp/fork-tools/sync-upstream.sh <upstream-url> <upstream-branch>
    git push origin HEAD:main

On a conflict the script stops and lists the files; merge `refs/fork-main/upstream` by hand,
fix them, and push.
