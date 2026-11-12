# Generated `main` for this fork

`main` on this fork is generated, not edited by hand. It is always:

    upstream default branch  +  every branch listed in fork.conf, merged in order  +  "Fork: CI"

`generate-main.sh` rebuilds it from scratch, so upstream updates never pile up
as merge noise, and each fork change stays a separate branch. The same inputs
always give the same commit, so CI can check a build and then publish exactly it.

## Rules

- **Nothing goes upstream automatically.** The tools only fetch from anyproto.
  They push to this fork only (`main`, `fork-tools`, the mirror branch) and never
  open PRs. A branch goes upstream only by hand, after Daniel has checked it.
- **main never moves to a broken build.** CI rebuilds it and publishes only if
  the checks pass. Otherwise main stays at its last good build and the run goes red.
- **Do not push to main directly.** Open a PR into main, or add the branch to fork.conf.
- **Do not delete a branch that is listed in fork.conf**, even after its PR merges.

## Branches

| Branch | What it is |
| --- | --- |
| `main` | Generated. Build and run this. Rewritten on every rebuild. Default branch. |
| `fork-tools` | This branch: the script, `fork.conf`, `ci/` and this README. No shared history with upstream. |
| upstream mirror (`develop` on heart and ts) | Plain copy of upstream, only ever fast-forwarded. |
| `claude/*`, others | Patch branches. Base new ones on upstream, not on `main`. |

## CI (`ci/fork-main.yml`, installed into main as `.github/workflows/fork-main.yml`)

Upstream's own workflows are removed from main: they need upstream's secrets and runners.

| Event | What happens |
| --- | --- |
| PR into main opened or updated | Builds main with the PR's branch added and runs the checks. Red if it conflicts or breaks anything. |
| PR merged into main | Adds its branch to fork.conf, rebuilds, checks, publishes. |
| Push to fork-tools, every 6 hours, or "Run workflow" | Rebuilds from the latest upstream, checks, publishes if green. |

The checks (`ci/verify-*.sh`):
- **heart:** `go build ./...`, plus `go test` for every package the patches change.
- **ts:** typecheck and lint, plus unit tests. Upstream already has failing tests, so only tests that pass on upstream and fail on main count.
- **kotlin:** `assembleDebug`, plus unit tests for every module the patches change.

### One-time setup per fork

1. Settings > Actions > General: allow Actions.
2. Settings > Secrets and variables > Actions: add `FORK_TOKEN`, a classic token with
   `repo`, `workflow` and (for kotlin) `read:packages`. It publishes main, because the
   built-in token cannot push workflow files, and it downloads the Android middleware.
3. Settings > General: make `main` the default branch (needed for the schedule).

## By hand

From a full (non-shallow) clone of the fork:

    git fetch origin fork-tools
    git archive origin/fork-tools | tar -x -C /tmp/fork-tools
    /tmp/fork-tools/generate-main.sh               # dry run: builds locally, pushes nothing
    /tmp/fork-tools/generate-main.sh --extra my-branch   # try a branch before listing it
    /tmp/fork-tools/generate-main.sh --push --sync-mirror   # publish without CI checks

- **A patch was merged upstream:** the script reports it as "already contained"; delete its line.
- **Conflict:** the script stops and names the branch and files; main is untouched.
  Rebase that branch onto upstream (or reorder the list) and push it.
- **Take a change out:** delete its line and publish with `--allow-drop`.
