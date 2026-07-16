#!/usr/bin/env bash
# Create a sibling git worktree for a branch.
#
# Usage: create-worktree.sh <branch> [base] [slug]
#   branch  new branch to create (e.g. feat/abc-1234-foo)
#   base    branch to fork from (default: origin's default branch, e.g. origin/dev)
#   slug    worktree dir name (default: branch with '/' -> '-')
#
# Layout: <parent>/<repo>.worktrees/<slug>  — sibling of the MAIN checkout,
# anchored via --git-common-dir so it works even when invoked from a worktree.
#
# Contract: diagnostics -> stderr; on success the worktree's absolute path is
# the ONLY thing printed to stdout, so callers can:  cd "$(create-worktree.sh ...)"
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

BRANCH="${1:-}"
[ -n "$BRANCH" ] || die "branch name required — usage: create-worktree.sh <branch> [base] [slug]"
BASE="${2:-}"
SLUG="${3:-${BRANCH//\//-}}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

log "fetching origin…"
git fetch origin --quiet
# Clear registrations whose dirs were deleted without 'worktree remove' — otherwise
# 'worktree add' dies with "missing but already registered" (and leaks the new branch).
git worktree prune

# MAIN checkout = dir containing the shared git dir (correct even from a linked worktree).
COMMON="$(git rev-parse --git-common-dir)"
case "$COMMON" in /*) ;; *) COMMON="$(pwd)/$COMMON" ;; esac
MAIN="$(cd "$(dirname "$COMMON")" && pwd)"

# Default base = origin's default branch (e.g. origin/dev); fall back to current branch.
if [ -z "$BASE" ]; then
  if BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    :
  else
    cur="$(git rev-parse --abbrev-ref HEAD)"
    BASE="origin/$cur"
    log "origin/HEAD unknown; defaulting base to $BASE"
  fi
fi
git rev-parse --verify --quiet "$BASE" >/dev/null || die "base ref not found: $BASE (try 'git fetch origin')"

WT="$MAIN.worktrees/$SLUG"
[ -e "$WT" ] && die "worktree path already exists: $WT"

log "creating worktree: $WT  (branch $BRANCH from $BASE)"
git worktree add "$WT" -b "$BRANCH" "$BASE" >&2

printf '%s\n' "$WT"
