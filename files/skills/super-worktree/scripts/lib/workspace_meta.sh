#!/usr/bin/env bash
# workspace_meta.sh - aggregate workspace-level metadata read/write.
# Sources util.sh; relies on $WORKSPACE_ROOT being set by workspace.sh.
# File layout:
#   <WORKSPACE_ROOT>/.worktrees/.metadata/<feature-encoded>.json
# Feature names containing '/' are encoded by replacing '/' with '__'.

ws_meta_dir() {
  printf '%s' "$WORKSPACE_ROOT/.worktrees/.metadata"
}

ws_root_dir() {
  printf '%s' "$WORKSPACE_ROOT/.worktrees"
}

# Encode feature name for use as a filename ('/' -> '__').
ws_meta_encode() {
  local f="$1"
  printf '%s' "${f//\//__}"
}

ws_meta_decode() {
  local f="$1"
  printf '%s' "${f//__/\/}"
}

ws_meta_path() {
  local feature="$1"
  printf '%s/%s.json' "$(ws_meta_dir)" "$(ws_meta_encode "$feature")"
}

# Path to the symlink hub for a given feature.
ws_hub_dir() {
  local feature="$1"
  printf '%s/%s' "$(ws_root_dir)" "$feature"
}

# Quote a string for safe JSON embedding.
_jq_str() {
  if command -v jq &>/dev/null; then
    jq -Rn --arg v "$1" '$v'
  else
    printf '"%s"' "${1//\"/\\\"}"
  fi
}

# Convert "alias|branch|base|worktree_path" newline-separated records into a JSON array.
_ws_records_to_json() {
  local records="$1"
  if ! command -v jq &>/dev/null; then
    printf '[]'
    return 0
  fi
  local arr
  arr="$(
    while IFS='|' read -r alias branch base wpath; do
      [[ -z "$alias" ]] && continue
      local proj_path="${WS_PROJECT_PATHS[$alias]:-}"
      local rel_proj="${proj_path#"$WORKSPACE_ROOT"/}"
      local rel_wt="${wpath#"$WORKSPACE_ROOT"/}"
      jq -n \
        --arg alias "$alias" \
        --arg path  "./$rel_proj" \
        --arg branch "$branch" \
        --arg base "$base" \
        --arg worktreePath "./$rel_wt" \
        '{alias:$alias, path:$path, branch:$branch, base:$base, worktreePath:$worktreePath}'
    done <<< "$records"
  )"
  if [[ -z "$arr" ]]; then
    printf '[]'
  else
    printf '%s' "$arr" | jq -s '.'
  fi
}

# Write workspace metadata for a feature.
# Args:
#   $1 feature
#   $2 ai_tool
#   $3 records  - newline-separated "alias|branch|base|worktree_path"
ws_meta_write() {
  local feature="$1" ai_tool="$2" records="$3"
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0

  local meta
  meta="$(ws_meta_path "$feature")"
  mkdir -p "$(dirname "$meta")"

  local hub
  hub="$(ws_hub_dir "$feature")"
  local hub_rel="${hub#"$WORKSPACE_ROOT"/}"
  local created
  created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local projects_json
  projects_json="$(_ws_records_to_json "$records")"

  cat > "$meta" <<JSON
{
  "feature": $(_jq_str "$feature"),
  "createdAt": $(_jq_str "$created"),
  "aiTool": $(_jq_str "$ai_tool"),
  "workspaceRoot": $(_jq_str "$WORKSPACE_ROOT"),
  "rootSymlinkDir": $(_jq_str "$hub_rel"),
  "projects": $projects_json
}
JSON
}

# Read raw metadata JSON; returns 1 if missing.
ws_meta_read() {
  local feature="$1"
  local meta
  meta="$(ws_meta_path "$feature")"
  [[ -f "$meta" ]] || return 1
  cat "$meta"
}

# List all workspace features (one per line). Empty if none.
ws_meta_list() {
  local dir
  dir="$(ws_meta_dir)"
  [[ -d "$dir" ]] || return 0
  local f base
  while IFS= read -r -d '' f; do
    base="$(basename "$f" .json)"
    printf '%s\n' "$(ws_meta_decode "$base")"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
}

# Remove workspace metadata for a feature.
ws_meta_remove() {
  local feature="$1"
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  rm -f "$(ws_meta_path "$feature")"
}

# Iterate workspace metadata projects: prints "alias|branch|base|worktreePath" per project.
# Used by delete/sync/status when feature was created previously.
ws_meta_iter_projects() {
  local feature="$1"
  local meta
  meta="$(ws_meta_path "$feature")"
  [[ -f "$meta" ]] || return 1
  command -v jq &>/dev/null || { warn "jq not installed; cannot iterate workspace metadata"; return 1; }
  jq -r '.projects[] | [.alias, .branch, .base, .worktreePath] | join("|")' "$meta"
}

# Ensure local-only ignore for the workspace .worktrees hub.
# Append to each declared project's .git/info/exclude so editors don't show stray paths.
ensure_workspace_local_excludes() {
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  local hub_root
  hub_root="$(ws_root_dir)"
  mkdir -p "$hub_root"
  local alias path exclude_file
  for alias in "${WS_PROJECT_ALIASES[@]}"; do
    path="${WS_PROJECT_PATHS[$alias]}"
    exclude_file="$path/.git/info/exclude"
    [[ -d "$(dirname "$exclude_file")" ]] || continue
    touch "$exclude_file" 2>/dev/null || continue
    if ! grep -qxF '.worktrees/' "$exclude_file" 2>/dev/null; then
      printf '%s\n' '.worktrees/' >> "$exclude_file"
    fi
  done
}
