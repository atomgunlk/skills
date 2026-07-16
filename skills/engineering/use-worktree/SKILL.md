---
name: use-worktree
description: Use when working with Git worktrees — triggers include "create worktree", "add worktree", "sibling worktree", or a plan file path. ALWAYS use for managing Git worktrees.
---

# use-worktree

Create a sibling Git worktree for a new branch, without polluting the main checkout.

## Running the script

The script is bundled with this skill at `scripts/create-worktree.sh` — resolve it
**relative to the directory containing this SKILL.md** (do NOT reconstruct the git
commands inline, and do NOT resolve it relative to your current working directory):

```bash
WT=$(<skill-dir>/scripts/create-worktree.sh <branch> [base] [slug])
cd "$WT"
```

- `branch` — new branch, e.g. `feat/abc-1234-foo` (required)
- `base` — fork point (optional; default: origin's default branch)
- `slug` — worktree dir name (optional; default: branch with `/`→`-`)

**Detached mode** — no new branch, checkout at a commit (e.g. a PR head SHA; fetch it first):

```bash
WT=$(<skill-dir>/scripts/create-worktree.sh --detach <commitish> [slug])
```

The script fetches origin, creates the worktree as a sibling of the **main** checkout
(`<repo>.worktrees/<slug>`), and prints the worktree path to stdout (diagnostics go to
stderr), so `cd "$(…)"` lands you in it. It works even when invoked from inside another
worktree — it anchors on the shared git dir.

## Examples

```bash
# New feature branch from origin's default branch
WT=$(<skill-dir>/scripts/create-worktree.sh feat/abc-1234-foo)

# Fork from a specific base
WT=$(<skill-dir>/scripts/create-worktree.sh fix/hotfix-login origin/release/1.2)

# Custom directory name for the worktree
WT=$(<skill-dir>/scripts/create-worktree.sh feat/abc-1234-foo "" abc-1234)

# Detached checkout of a PR head for review (no branch created)
WT=$(<skill-dir>/scripts/create-worktree.sh --detach "$HEAD_SHA" review-pr-42)
```

## Optional: direnv users

direnv only fires in interactive shells. If the repo uses direnv, tooling run in the new
worktree from a non-interactive shell (e.g. an agent's Bash tool) won't have env files
loaded — prefix with:

```bash
direnv exec "$WT" <command>
```
