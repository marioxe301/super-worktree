#!/usr/bin/env bash
# E2E for workspace mode (multi-repo). Self-contained.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${SCRIPT:-$ROOT/scripts/worktree-manager.sh}"
FIXTURE="$ROOT/tests/fixtures/multi_repo_workspace.sh"
TMP="$(mktemp -d -t sw-ws-e2e.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

bash "$FIXTURE" "$TMP" api ui db
cd "$TMP"

echo "==> 1. workspace list (no features)"
out="$(bash "$SCRIPT" workspace list)"
grep -q "test-workspace" <<<"$out"
grep -q "(none)" <<<"$out"

echo "==> 2. workspace list --json valid"
bash "$SCRIPT" workspace list --json | jq -e '.workspace.name == "test-workspace"' >/dev/null
bash "$SCRIPT" workspace list --json | jq -e '.projects | length == 3' >/dev/null

echo "==> 3. workspace create with default projects"
bash "$SCRIPT" workspace create feat/x >/dev/null
test -d "$TMP/api/.worktrees/feat/x"
test -d "$TMP/ui/.worktrees/feat/x"
test ! -d "$TMP/db/.worktrees/feat/x"

echo "==> 4. symlink hub points at real worktrees"
test -L "$TMP/.worktrees/feat/x/api"
test -L "$TMP/.worktrees/feat/x/ui"
test -f "$TMP/.worktrees/feat/x/api/.env"

echo "==> 5. workspace metadata aggregate"
meta="$TMP/.worktrees/.metadata/feat__x.json"
test -f "$meta"
jq -e '.feature == "feat/x"' "$meta" >/dev/null
jq -e '.projects | length == 2' "$meta" >/dev/null
jq -e '[.projects[].alias] | sort == ["api", "ui"]' "$meta" >/dev/null

echo "==> 6. per-project metadata still written"
test -f "$TMP/api/.worktrees/.metadata/feat__x.json"
jq -e '.baseBranch == "main"' "$TMP/api/.worktrees/.metadata/feat__x.json" >/dev/null

echo "==> 7. .env per project is project-scoped (not cross-pollinated)"
grep -q "X=api" "$TMP/.worktrees/feat/x/api/.env"
grep -q "X=ui"  "$TMP/.worktrees/feat/x/ui/.env"

echo "==> 8. workspace list shows feature"
out="$(bash "$SCRIPT" workspace list)"
grep -q "feat/x" <<<"$out"

echo "==> 9. workspace status reports per-project"
out="$(bash "$SCRIPT" workspace status feat/x)"
grep -q "api" <<<"$out"
grep -q "ui"  <<<"$out"

echo "==> 10. status --json valid"
bash "$SCRIPT" workspace status feat/x --json | jq -e '. | length == 2' >/dev/null

echo "==> 11. workspace sync re-pulls .env after rotation"
echo "X=ROTATED" > "$TMP/api/.env"
bash "$SCRIPT" workspace sync feat/x >/dev/null
grep -q "X=ROTATED" "$TMP/.worktrees/feat/x/api/.env"

echo "==> 12. delete refused while dirty (without --force)"
echo dirty > "$TMP/.worktrees/feat/x/api/dirty.tmp"
{ bash "$SCRIPT" workspace delete feat/x 2>&1 || true; } | grep -q "dirty projects"

echo "==> 13. delete --force removes everything"
bash "$SCRIPT" workspace delete feat/x --force >/dev/null
test ! -d "$TMP/api/.worktrees/feat/x"
test ! -d "$TMP/ui/.worktrees/feat/x"
test ! -e "$TMP/.worktrees/feat/x"
test ! -f "$meta"

echo "==> 14. workspace create --all selects every project"
bash "$SCRIPT" workspace create feat/all --all >/dev/null
test -d "$TMP/api/.worktrees/feat/all"
test -d "$TMP/ui/.worktrees/feat/all"
test -d "$TMP/db/.worktrees/feat/all"

echo "==> 15. duplicate worktree refused"
{ bash "$SCRIPT" workspace create feat/all --all 2>&1 || true; } | grep -q "already exists"

echo "==> 16. bare 'create' at workspace root routes to workspace"
bash "$SCRIPT" create feat/bare --projects db >/dev/null
test -d "$TMP/db/.worktrees/feat/bare"

echo "==> 17. single-repo regression (inside one project)"
( cd "$TMP/api"
  bash "$SCRIPT" create test-single >/dev/null
  test -d "$TMP/api/.worktrees/test-single"
  bash "$SCRIPT" delete test-single >/dev/null
)

echo "==> cleanup"
bash "$SCRIPT" workspace delete feat/all --force >/dev/null
bash "$SCRIPT" workspace delete feat/bare --force >/dev/null

echo "ALL OK"
