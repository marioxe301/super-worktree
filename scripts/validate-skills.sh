#!/usr/bin/env bash
# Validate every SKILL.md frontmatter parses as YAML and contains name + description.
# Mirrors the discovery rules used by `npx skills` (vercel-labs/skills).
set -euo pipefail

cd "$(dirname "$0")/.."

mapfile -t files < <(find . -name SKILL.md -type f \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/.worktrees/*' \
  -not -path '*/__pycache__/*')

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No SKILL.md found" >&2
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "node required" >&2
  exit 1
fi

yaml_dir=""
for cand in /tmp/yamltest/node_modules /tmp/skills-validator/node_modules; do
  [[ -d "$cand/yaml" ]] && yaml_dir="$cand" && break
done
if [[ -z "$yaml_dir" ]]; then
  mkdir -p /tmp/skills-validator
  ( cd /tmp/skills-validator
    [[ -f package.json ]] || npm init -y >/dev/null 2>&1
    [[ -d node_modules/yaml ]] || npm install --silent yaml@^2.8.0 >/dev/null 2>&1
  ) || true
  yaml_dir=/tmp/skills-validator/node_modules
fi

if [[ ! -d "$yaml_dir/yaml" ]]; then
  echo "could not install yaml package" >&2
  exit 1
fi

fail=0
for f in "${files[@]}"; do
  if result=$(node -e "
    const yaml = require('$yaml_dir/yaml');
    const fs = require('fs');
    const raw = fs.readFileSync('$f', 'utf-8');
    const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)\$/);
    if (!m) { console.log('NO_FRONTMATTER'); process.exit(1); }
    try {
      const d = yaml.parse(m[1]) || {};
      if (typeof d.name !== 'string' || !d.name) { console.log('MISSING_NAME'); process.exit(1); }
      if (typeof d.description !== 'string' || !d.description) { console.log('MISSING_DESCRIPTION'); process.exit(1); }
      console.log('OK name=' + d.name + ' desc.len=' + d.description.length);
    } catch (e) {
      console.log('PARSE_ERR ' + e.message);
      process.exit(1);
    }
  " 2>&1); then
    printf '  OK  %s — %s\n' "$f" "$result"
  else
    printf '  FAIL %s — %s\n' "$f" "$result" >&2
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "SKILL.md validation FAILED" >&2
  exit 1
fi
echo "All SKILL.md files valid."
