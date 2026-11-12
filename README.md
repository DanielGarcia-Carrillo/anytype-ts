# Generated `main` for this fork

`main` on this fork is generated, not edited by hand. It is always:

    upstream default branch  +  every branch listed in fork.conf, merged in order

`generate-main.sh` rebuilds it from scratch each time, so upstream updates never
pile up as merge noise on top of old fork work, and each fork change stays a
separate branch that can still go upstream as its own PR.

## Branches

| Branch | What it is |
| --- | --- |
| `main` | Generated. Build and run this. Force-pushed on every regeneration. |
| `fork-tools` | This branch: the script, `fork.conf` and this README. Not related to upstream history. |
| upstream mirror (`develop` on heart and ts) | Plain copy of upstream, only ever fast-forwarded. |
| `claude/*`, others | Patch branches. Base new ones on upstream, not on `main`. |

## Everyday use

    git fetch origin fork-tools
    git show origin/fork-tools:generate-main.sh > /tmp/generate-main.sh && chmod +x /tmp/generate-main.sh
    /tmp/generate-main.sh               # dry run: builds locally, pushes nothing
    /tmp/generate-main.sh --preview     # push to main-preview to try it first
    /tmp/generate-main.sh --push --sync-mirror

Run it from a full (non-shallow) clone of the fork.

- **Add a change to main:** add `patch <branch>` to `fork.conf` on `fork-tools`, then regenerate.
  Do not merge PRs straight into `main`: the next regeneration would drop them.
  (The script refuses to push if it would drop a commit that is on `main` today; `--allow-drop` overrides.)
- **Take a change out:** delete its line, regenerate with `--allow-drop`.
- **A patch was merged upstream:** the script reports it as "already contained"; delete its line.
- **Conflict:** the script stops and names the branch and files; `main` is untouched.
  Rebase that branch onto upstream (or reorder the list) and run again.
