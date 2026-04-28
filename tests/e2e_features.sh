#!/usr/bin/env bash
# Smoke for new features: --json, sync, --ticket/--slug, glob negation.
set -euo pipefail

SCRIPT="${SCRIPT:-$(cd "$(dirname "$0")/.." && pwd)/scripts/worktree-manager.sh}"
TMP="$(mktemp -d -t super-worktree-feat.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

(
  cd "$TMP"
  git init -q -b main
  printf 'init\n' > README.md
  git add README.md
  git commit -q -m init
  printf 'FOO=bar\n'  > .env
  printf 'sample\n'   > .env.example
  printf 'creds\n'    > credentials.json

  cat > .super-worktree.json <<'JSON'
{
  "$schema": "./schemas/super-worktree.schema.json",
  "version": 1,
  "sync": {
    "copyFiles": [".env", ".env.*", "!.env.example", "credentials.json"],
    "copyDepth": 2
  }
}
JSON

  echo "==> create with --ticket and --slug"
  NO_SPAWN=1 bash "$SCRIPT" create --ticket TEST-1 --slug "test feature"

  expected_branch="test-1-test-feature"
  test -d "$TMP/.worktrees/$expected_branch" || { echo "missing $expected_branch"; exit 1; }
  echo "  branch=$expected_branch ok"

  echo "==> verify negation excluded .env.example"
  test ! -f "$TMP/.worktrees/$expected_branch/.env.example" || { echo "negate failed"; exit 1; }
  test -f "$TMP/.worktrees/$expected_branch/.env"
  test -f "$TMP/.worktrees/$expected_branch/credentials.json"

  echo "==> list --json"
  bash "$SCRIPT" list --json | jq .

  echo "==> status --json"
  bash "$SCRIPT" status --json | jq .

  echo "==> rotate .env and run sync"
  printf 'FOO=updated\n' > .env
  NO_SPAWN=1 bash "$SCRIPT" sync "$expected_branch"
  grep -q updated "$TMP/.worktrees/$expected_branch/.env" || { echo "sync failed"; exit 1; }

  echo "==> delete"
  bash "$SCRIPT" delete "$expected_branch"
)

echo "ALL OK"
