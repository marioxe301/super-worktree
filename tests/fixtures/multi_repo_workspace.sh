#!/usr/bin/env bash
# Fixture helper: create a synthetic multi-repo workspace under $1 (a tmpdir).
# Args:
#   $1  workspace_root  - existing or to-be-created directory
#   $@  project aliases (default: api ui db)
# Generates:
#   - one git repo per alias with an initial commit + .env
#   - super-worktree.workspace.json declaring all aliases, defaults to first two
set -euo pipefail

ws_root="${1:?workspace root required}"; shift || true
projects=("$@")
[[ ${#projects[@]} -eq 0 ]] && projects=(api ui db)

[[ -d "$ws_root" ]] || mkdir -p "$ws_root"

for alias in "${projects[@]}"; do
  mkdir -p "$ws_root/$alias"
  ( cd "$ws_root/$alias"
    git init -q -b main
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    printf 'X=%s\n' "$alias" > .env
  )
done

projects_json=""
for alias in "${projects[@]}"; do
  projects_json+="    { \"alias\": \"$alias\", \"path\": \"./$alias\", \"defaultBase\": \"main\" },"$'\n'
done
projects_json="${projects_json%,$'\n'}"

if [[ ${#projects[@]} -ge 2 ]]; then
  defaults_json="\"${projects[0]}\", \"${projects[1]}\""
else
  defaults_json="\"${projects[0]}\""
fi

cat > "$ws_root/super-worktree.workspace.json" <<JSON
{
  "version": 1,
  "workspace": {
    "name": "test-workspace",
    "projects": [
$projects_json
    ],
    "defaultProjects": [$defaults_json],
    "spawnMode": "single",
    "symlinkLayer": true,
    "rollback": "strict"
  }
}
JSON
