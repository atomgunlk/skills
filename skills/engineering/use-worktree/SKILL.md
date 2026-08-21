---
name: use-worktree
description: Creates a sibling git worktree at <repo>.worktrees/<slug> — an isolated workspace for starting branch work off the main checkout, or a detached checkout of a PR head to review.
---

# use-worktree

Isolate work in a sibling worktree, leaving the main checkout untouched.

Reach for this over a native worktree tool (`EnterWorktree`) when the worktree must live **outside** the repo as `<repo>.worktrees/<slug>`: nothing to add to `.gitignore`, and it lands in the same place whether invoked from the main checkout, a subdirectory, or another worktree. For a throwaway workspace with harness-managed cleanup, the native tool is the better fit.

## Are you already isolated?

Check before creating anything:

```bash
git rev-parse --git-dir
```

A path ending in `.git/worktrees/<name>` means you are already in a worktree — that is your isolated workspace, work in it. A path ending in plain `.git` means you are in the main checkout, so continue below. Create a second worktree only for a deliberately separate checkout, e.g. reviewing a PR while your feature work stays put.

## Create one

Run the bundled script by absolute path, chained with `&&` so a failed run cannot be mistaken for a landing:

```bash
WT=$(~/.claude/skills/use-worktree/scripts/create-worktree.sh <branch> [base] [slug]) && cd "$WT" && git rev-parse --git-dir
```

- `branch` — new branch, e.g. `feat/abc-1234-foo` (required)
- `base` — fork point (optional; default: origin's default branch)
- `slug` — worktree dir name (optional; default: branch with `/`→`-`)
- `--reuse` — `<branch>` already exists (aborted run, resumed work): check it out here instead of creating it
- `--detach <commitish>` — no new branch, detached checkout at a commit, e.g. a PR head SHA (fetch it first)

**You have landed when** that command prints a path ending in `.git/worktrees/<slug>`. Any other outcome — an error, empty output, a path ending in plain `.git` — leaves you in the main checkout: read the stderr diagnostic, fix the cause, and land before editing a single file.

## Carry the path, not the cwd

Each Bash call starts a fresh shell in the original directory, so neither that `cd` nor `$WT` reaches your next command. Record the printed absolute path and spell it out every time:

```bash
cd /abs/path/repo.worktrees/<slug> && <command>
git -C /abs/path/repo.worktrees/<slug> status     # git alone
```

A command that omits the path runs in the main checkout — the thing this skill exists to prevent.

## Examples

```bash
# New feature branch from origin's default branch
WT=$(~/.claude/skills/use-worktree/scripts/create-worktree.sh feat/abc-1234-foo) && cd "$WT" && git rev-parse --git-dir

# Custom worktree dir name; empty base keeps the default
WT=$(~/.claude/skills/use-worktree/scripts/create-worktree.sh feat/abc-1234-foo "" abc-1234) && cd "$WT" && git rev-parse --git-dir

# Detached checkout of a PR head for review
WT=$(~/.claude/skills/use-worktree/scripts/create-worktree.sh --detach "$HEAD_SHA" review-pr-42) && cd "$WT" && git rev-parse --git-dir
```

## What the script does

Fetches origin when there is one (a local-only or offline repo still works, with a warning on stderr), prunes stale worktree registrations, then creates the worktree as a sibling of the **main** checkout, anchored on the shared git dir.

New branches are created with `--no-track`, so a branch forked from `origin/dev` never reports itself behind `dev` and a bare `git pull` cannot merge `dev` into it. The cost: the first push needs `git push -u origin HEAD`. A branch checked out with `--reuse` keeps whatever upstream it already had.

An existing branch name is a hard error unless you pass `--reuse` — landing on a stale branch from an aborted run is the failure this skill exists to prevent.

## direnv repos

direnv fires only in interactive shells, so tooling run in the new worktree from an agent's Bash tool has no env files loaded. Prefix with `direnv exec /abs/path/repo.worktrees/<slug> <command>`.
