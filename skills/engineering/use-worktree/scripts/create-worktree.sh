#!/usr/bin/env bash
# Create a sibling git worktree for a branch.
#
# Usage: create-worktree.sh <branch> [base] [slug]
#        create-worktree.sh --detach <commitish> [slug]
#   branch     new branch to create (e.g. feat/abc-1234-foo)
#   base       branch to fork from (default: origin's default branch, e.g. origin/dev)
#   slug       worktree dir name (default: branch/commitish with '/' -> '-')
#   --detach   no new branch: detached checkout at <commitish> (e.g. a PR head SHA)
#
# Layout: <parent>/<repo>.worktrees/<slug>  — sibling of the MAIN checkout,
# anchored via --git-common-dir so it works even when invoked from a worktree.
#
# Contract: diagnostics -> stderr; on success the worktree's absolute path is
# the ONLY thing printed to stdout, so callers can:  cd "$(create-worktree.sh ...)"
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

DETACH=0
[ "${1:-}" = "--detach" ] && { DETACH=1; shift; }
BRANCH="${1:-}"   # branch to create — or commitish when --detach
[ -n "$BRANCH" ] || die "usage: create-worktree.sh <branch> [base] [slug] | --detach <commitish> [slug]"
if [ "$DETACH" = 1 ]; then
  BASE=""
  SLUG="${2:-${BRANCH//\//-}}"
else
  BASE="${2:-}"
  SLUG="${3:-${BRANCH//\//-}}"
fi

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
if [ "$DETACH" = 0 ] && [ -z "$BASE" ]; then
  if BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    :
  else
    cur="$(git rev-parse --abbrev-ref HEAD)"
    BASE="origin/$cur"
    log "origin/HEAD unknown; defaulting base to $BASE"
  fi
fi
[ "$DETACH" = 1 ] || git rev-parse --verify --quiet "$BASE" >/dev/null || die "base ref not found: $BASE (try 'git fetch origin')"

WT="$MAIN.worktrees/$SLUG"
[ -e "$WT" ] && die "worktree path already exists: $WT"

if [ "$DETACH" = 1 ]; then
  git rev-parse --verify --quiet "$BRANCH^{commit}" >/dev/null || die "commit not found: $BRANCH (fetch it first)"
  log "creating detached worktree: $WT  (at $BRANCH)"
  git worktree add --detach "$WT" "$BRANCH" >&2
else
  log "creating worktree: $WT  (branch $BRANCH from $BASE)"
  git worktree add "$WT" -b "$BRANCH" "$BASE" >&2
fi

printf '%s\n' "$WT"
