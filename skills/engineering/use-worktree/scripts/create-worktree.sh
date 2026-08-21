#!/usr/bin/env bash
# Create a sibling git worktree for a branch.
#
# Usage: create-worktree.sh [--reuse] <branch> [base] [slug]
#        create-worktree.sh --detach <commitish> [slug]
#   branch     new branch to create (e.g. feat/abc-1234-foo)
#   base       branch to fork from (default: origin's default branch, e.g. origin/dev)
#   slug       worktree dir name (default: branch/commitish with '/' -> '-')
#   --detach   no new branch: detached checkout at <commitish> (e.g. a PR head SHA)
#   --reuse    <branch> already exists: check it out here instead of creating it
#
# Layout: <parent>/<repo>.worktrees/<slug>  — sibling of the MAIN checkout,
# anchored via --git-common-dir so it works even when invoked from a worktree.
#
# Contract: diagnostics -> stderr; on success the worktree's absolute path is
# the ONLY thing printed to stdout. On failure stdout stays empty and the exit
# status is non-zero, so callers must chain:  WT=$(create-worktree.sh ...) && cd "$WT"
# ('cd ""' succeeds silently and would leave the caller in the main checkout.)
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

DETACH=0
REUSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --detach) DETACH=1; shift ;;
    --reuse)  REUSE=1;  shift ;;
    *) break ;;
  esac
done

BRANCH="${1:-}"   # branch to create — or commitish when --detach
[ -n "$BRANCH" ] || die "usage: create-worktree.sh [--reuse] <branch> [base] [slug] | --detach <commitish> [slug]"
if [ "$DETACH" = 1 ]; then
  BASE=""
  SLUG="${2:-${BRANCH//\//-}}"
else
  BASE="${2:-}"
  SLUG="${3:-${BRANCH//\//-}}"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

# origin is optional: a local-only or offline repo still gets a worktree, just no fetch.
HAS_ORIGIN=0
git remote get-url origin >/dev/null 2>&1 && HAS_ORIGIN=1
if [ "$HAS_ORIGIN" = 1 ]; then
  log "fetching origin…"
  git fetch origin --quiet || log "warn: fetch failed — continuing with local refs"
else
  log "no origin remote — using local refs"
fi

# Clear registrations whose dirs were deleted without 'worktree remove' — otherwise
# 'worktree add' dies with "missing but already registered".
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
    if [ "$HAS_ORIGIN" = 1 ] && git rev-parse --verify --quiet "origin/$cur" >/dev/null; then
      BASE="origin/$cur"
    else
      BASE="$cur"
    fi
    log "origin/HEAD unknown; defaulting base to $BASE"
  fi
fi
[ "$DETACH" = 1 ] || git rev-parse --verify --quiet "$BASE" >/dev/null || die "base ref not found: $BASE (try 'git fetch origin')"

# An existing branch is checked out only on explicit --reuse: silently landing on a
# stale branch from an aborted run is worse than failing here.
if [ "$DETACH" = 0 ]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    [ "$REUSE" = 1 ] || die "branch already exists: $BRANCH — pass --reuse to check it out here, or pick another name"
  else
    [ "$REUSE" = 0 ] || die "branch not found: $BRANCH — drop --reuse to create it"
  fi
fi

WT="$MAIN.worktrees/$SLUG"
[ -e "$WT" ] && die "worktree path already exists: $WT"

if [ "$DETACH" = 1 ]; then
  git rev-parse --verify --quiet "$BRANCH^{commit}" >/dev/null || die "commit not found: $BRANCH (fetch it first)"
  log "creating detached worktree: $WT  (at $BRANCH)"
  git worktree add --detach "$WT" "$BRANCH" >&2
elif [ "$REUSE" = 1 ]; then
  log "creating worktree: $WT  (existing branch $BRANCH, upstream unchanged)"
  git worktree add "$WT" "$BRANCH" >&2
else
  # --no-track: a feature branch forked from origin/dev must not track origin/dev, or
  # 'git status' reports it behind and a bare 'git pull' merges dev into it.
  log "creating worktree: $WT  (branch $BRANCH from $BASE, no upstream)"
  git worktree add "$WT" -b "$BRANCH" --no-track "$BASE" >&2
fi

printf '%s\n' "$WT"
