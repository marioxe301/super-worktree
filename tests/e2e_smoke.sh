#!/usr/bin/env bash
# Smoke E2E test for super-worktree. Self-contained; exits non-zero on failure.
set -euo pipefail

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/scripts/worktree-manager.sh}"
TMP="$(mktemp -d -t super-worktree-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

(
  cd "$TMP"
  git init -q -b main
  printf 'init\n' > README.md
  git add README.md
  git commit -q -m init
  printf 'FOO=bar\n' > .env

  echo "==> create testing-branch"
  NO_SPAWN=1 bash "$SCRIPT" create testing-branch

  echo "==> list"
  bash "$SCRIPT" list

  echo "==> status"
  bash "$SCRIPT" status

  echo "==> verify metadata"
  test -f "$TMP/.worktrees/.metadata/testing-branch.json"
  jq . "$TMP/.worktrees/.metadata/testing-branch.json"

  echo "==> verify .env copied"
  test -f "$TMP/.worktrees/testing-branch/.env"
  grep -q FOO=bar "$TMP/.worktrees/testing-branch/.env"

  echo "==> verify .git/info/exclude entry"
  grep -qx '.worktrees/' "$TMP/.git/info/exclude"

  echo "==> delete testing-branch"
  bash "$SCRIPT" delete testing-branch

  echo "==> prune"
  bash "$SCRIPT" prune

  echo "==> assert worktree gone"
  test ! -d "$TMP/.worktrees/testing-branch"
  test ! -f "$TMP/.worktrees/.metadata/testing-branch.json"
)

echo "ALL OK"
