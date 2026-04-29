#!/usr/bin/env bash
# workspace.sh - multi-repo workspace detection and config loader.
# Sources util.sh for log/warn/die.
# Populates globals when in workspace mode:
#   WORKSPACE_MODE         - 1 if a workspace was detected, 0 otherwise
#   WORKSPACE_ROOT         - absolute path to dir containing super-worktree.workspace.json
#   WORKSPACE_CONFIG       - absolute path to the workspace config file
#   WORKSPACE_NAME         - display name (config or basename)
#   WS_PROJECT_ALIASES     - indexed array of declared aliases (preserves config order)
#   WS_PROJECT_PATHS       - alias -> absolute project path
#   WS_PROJECT_BASES       - alias -> defaultBase ref (may be empty)
#   WS_DEFAULT_PROJECTS    - indexed array; empty means "all"
#   WS_BRANCH_TEMPLATE     - template string (may be empty)
#   WS_SYMLINK_LAYER       - 1/0
#   WS_ROLLBACK            - "strict" or "leave"
#   WS_HOOKS               - associative; keys: preCreateAll postCreateAll preDeleteAll postDeleteAll

declare -g  WORKSPACE_MODE=0
declare -g  WORKSPACE_ROOT=""
declare -g  WORKSPACE_CONFIG=""
declare -g  WORKSPACE_NAME=""
declare -ga WS_PROJECT_ALIASES=()
declare -gA WS_PROJECT_PATHS=()
declare -gA WS_PROJECT_BASES=()
declare -ga WS_DEFAULT_PROJECTS=()
declare -g  WS_BRANCH_TEMPLATE=""
declare -g  WS_SYMLINK_LAYER=1
declare -g  WS_ROLLBACK="strict"
declare -gA WS_HOOKS=()

WORKSPACE_CONFIG_FILE="super-worktree.workspace.json"

# Walk from $1 upward looking for super-worktree.workspace.json.
# Prints the directory containing it; returns 1 if not found.
_find_workspace_root() {
  local dir="${1:-$PWD}"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -f "$dir/$WORKSPACE_CONFIG_FILE" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  if [[ -f "/$WORKSPACE_CONFIG_FILE" ]]; then
    printf '/'
    return 0
  fi
  return 1
}

# Best-effort: list immediate subdirectories of $1 that look like git repos.
# Used by `workspace init --auto-discover`.
discover_git_repos() {
  local parent="$1"
  [[ -d "$parent" ]] || return 0
  local entry
  while IFS= read -r -d '' entry; do
    [[ -d "$entry/.git" || -f "$entry/.git" ]] || continue
    printf '%s\0' "$entry"
  done < <(find "$parent" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
}

_ws_jq_check() {
  if ! command -v jq &>/dev/null; then
    die "jq is required for workspace mode (install: brew/apt install jq)"
  fi
}

# Reset workspace globals (for re-load).
_ws_reset() {
  WORKSPACE_MODE=0
  WORKSPACE_ROOT=""
  WORKSPACE_CONFIG=""
  WORKSPACE_NAME=""
  WS_PROJECT_ALIASES=()
  WS_PROJECT_PATHS=()
  WS_PROJECT_BASES=()
  WS_DEFAULT_PROJECTS=()
  WS_BRANCH_TEMPLATE=""
  WS_SYMLINK_LAYER=1
  WS_ROLLBACK="strict"
  WS_HOOKS=()
}

# Parse workspace config from $WORKSPACE_CONFIG into globals.
# Validates: jq-parseable, version, projects[] non-empty, alias uniqueness, paths exist & are git.
_ws_parse_config() {
  local file="$WORKSPACE_CONFIG"
  _ws_jq_check
  if ! jq empty "$file" &>/dev/null; then
    die "invalid JSON in $file"
  fi

  local version
  version="$(jq -r '.version // empty' "$file")"
  if [[ -n "$version" && "$version" != "1" ]]; then
    warn "workspace config $file declares version $version; build expects 1"
  fi

  local count
  count="$(jq -r '.workspace.projects | length // 0' "$file")"
  [[ "$count" -gt 0 ]] || die "workspace config $file has no projects[]"

  WORKSPACE_NAME="$(jq -r '.workspace.name // empty' "$file")"
  [[ -z "$WORKSPACE_NAME" ]] && WORKSPACE_NAME="$(basename "$WORKSPACE_ROOT")"

  WS_BRANCH_TEMPLATE="$(jq -r '.workspace.branchTemplate // empty' "$file")"

  local sl
  sl="$(jq -r '.workspace.symlinkLayer // true' "$file")"
  case "$sl" in true) WS_SYMLINK_LAYER=1 ;; false) WS_SYMLINK_LAYER=0 ;; *) WS_SYMLINK_LAYER=1 ;; esac

  local rb
  rb="$(jq -r '.workspace.rollback // "strict"' "$file")"
  case "$rb" in strict|leave) WS_ROLLBACK="$rb" ;; *) die "invalid rollback '$rb' in $file" ;; esac

  local phase val
  for phase in preCreateAll postCreateAll preDeleteAll postDeleteAll; do
    val="$(jq -r ".workspace.hooks.$phase // empty" "$file")"
    [[ -n "$val" ]] && WS_HOOKS["$phase"]="$val"
  done

  local i alias path base
  for ((i=0; i<count; i++)); do
    alias="$(jq -r ".workspace.projects[$i].alias // empty" "$file")"
    path="$(jq -r ".workspace.projects[$i].path  // empty" "$file")"
    base="$(jq -r ".workspace.projects[$i].defaultBase // empty" "$file")"

    [[ -z "$alias" ]] && die "workspace config: projects[$i].alias is required"
    [[ -z "$path"  ]] && die "workspace config: projects[$i].path is required"

    [[ "$alias" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
      || die "workspace config: alias '$alias' must match ^[a-z0-9][a-z0-9-]*$"

    if [[ -n "${WS_PROJECT_PATHS[$alias]:-}" ]]; then
      die "workspace config: duplicate alias '$alias'"
    fi

    if [[ "$path" != /* ]]; then
      path="$WORKSPACE_ROOT/$path"
    fi
    path="$(cd "$path" 2>/dev/null && pwd || printf '%s' "$path")"

    [[ -d "$path" ]] || die "project '$alias' path missing: $path"
    if ! git -C "$path" rev-parse --show-toplevel &>/dev/null; then
      die "project '$alias' is not a git repo: $path"
    fi

    WS_PROJECT_ALIASES+=("$alias")
    WS_PROJECT_PATHS["$alias"]="$path"
    WS_PROJECT_BASES["$alias"]="$base"
  done

  local defaults
  defaults="$(jq -r '.workspace.defaultProjects // [] | .[]?' "$file")"
  if [[ -n "$defaults" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ -n "${WS_PROJECT_PATHS[$line]:-}" ]] \
        || die "workspace defaultProjects: alias '$line' not declared in projects[]"
      WS_DEFAULT_PROJECTS+=("$line")
    done <<< "$defaults"
  fi
}

# Detect workspace mode from $PWD upward. Sets WORKSPACE_MODE=1 if found.
detect_workspace() {
  _ws_reset
  local root
  if root="$(_find_workspace_root "$PWD")"; then
    WORKSPACE_ROOT="$root"
    WORKSPACE_CONFIG="$root/$WORKSPACE_CONFIG_FILE"
    WORKSPACE_MODE=1
    _ws_parse_config
  fi
  return 0
}

# Resolve --projects spec into a list of aliases. Empty spec -> defaults -> all.
# Args: $1 = csv string. "all" forces every alias even if defaults are set.
# Prints aliases newline-separated.
resolve_project_selection() {
  local spec="${1:-}"
  if [[ -z "$spec" || "$spec" == "all" ]]; then
    if [[ "$spec" != "all" && ${#WS_DEFAULT_PROJECTS[@]} -gt 0 ]]; then
      printf '%s\n' "${WS_DEFAULT_PROJECTS[@]}"
    else
      printf '%s\n' "${WS_PROJECT_ALIASES[@]}"
    fi
    return 0
  fi
  local IFS=','
  local part
  for part in $spec; do
    part="${part## }"
    part="${part%% }"
    [[ -z "$part" ]] && continue
    [[ -n "${WS_PROJECT_PATHS[$part]:-}" ]] \
      || die "unknown project alias '$part' (declared: ${WS_PROJECT_ALIASES[*]})"
    printf '%s\n' "$part"
  done
}

# Per-project per-flag base override parser: "api=develop,ui=main" -> sets WS_BASE_OVERRIDE assoc.
declare -gA WS_BASE_OVERRIDE=()
parse_per_project_base() {
  local spec="${1:-}"
  WS_BASE_OVERRIDE=()
  [[ -z "$spec" ]] && return 0
  local IFS=','
  local pair k v
  for pair in $spec; do
    [[ -z "$pair" ]] && continue
    k="${pair%%=*}"
    v="${pair#*=}"
    [[ -z "$k" || -z "$v" || "$k" == "$pair" ]] && die "invalid --per-project-base entry: '$pair'"
    [[ -n "${WS_PROJECT_PATHS[$k]:-}" ]] || die "--per-project-base: unknown alias '$k'"
    WS_BASE_OVERRIDE["$k"]="$v"
  done
}

# Per-project branch override parser: "api=feat/x-api,ui=feat/x-ui".
declare -gA WS_BRANCH_OVERRIDE=()
parse_per_project_branch() {
  local spec="${1:-}"
  WS_BRANCH_OVERRIDE=()
  [[ -z "$spec" ]] && return 0
  local IFS=','
  local pair k v
  for pair in $spec; do
    [[ -z "$pair" ]] && continue
    k="${pair%%=*}"
    v="${pair#*=}"
    [[ -z "$k" || -z "$v" || "$k" == "$pair" ]] && die "invalid --branch-override entry: '$pair'"
    [[ -n "${WS_PROJECT_PATHS[$k]:-}" ]] || die "--branch-override: unknown alias '$k'"
    WS_BRANCH_OVERRIDE["$k"]="$v"
  done
}

# Resolve effective base ref for an alias.
# Priority: per-project --per-project-base > workspace --base > project.defaultBase > origin/HEAD > main
resolve_base_for_alias() {
  local alias="$1" workspace_base="${2:-}"
  local proj_path="${WS_PROJECT_PATHS[$alias]}"
  local pinned="${WS_PROJECT_BASES[$alias]:-}"
  local override="${WS_BASE_OVERRIDE[$alias]:-}"

  local ref="$override"
  [[ -z "$ref" && -n "$workspace_base" ]] && ref="$workspace_base"
  [[ -z "$ref" && -n "$pinned" ]] && ref="$pinned"
  if [[ -z "$ref" ]]; then
    if git -C "$proj_path" rev-parse -q --verify origin/HEAD &>/dev/null; then
      ref="origin/HEAD"
    else
      ref="main"
    fi
  fi
  printf '%s' "$ref"
}

# Resolve effective branch name for an alias from a base feature name.
# Priority: per-project --branch-override > base feature name (same across projects).
resolve_branch_for_alias() {
  local alias="$1" feature="$2"
  local override="${WS_BRANCH_OVERRIDE[$alias]:-}"
  if [[ -n "$override" ]]; then
    printf '%s' "$override"
  else
    printf '%s' "$feature"
  fi
}

# Run a workspace-level hook. cwd = WORKSPACE_ROOT.
run_ws_hook() {
  local phase="$1"; shift
  local cmd="${WS_HOOKS[$phase]:-}"
  [[ -z "$cmd" ]] && return 0
  log "Running workspace hook ($phase)..."
  ( cd "$WORKSPACE_ROOT" && env "$@" bash -c "$cmd" ) || warn "workspace hook $phase exited non-zero"
}

# Render branch template ({ticket}, {slug}, {feature}). Returns rendered string.
ws_branch_template_render() {
  local tmpl="$1" ticket="${2:-}" slug="${3:-}" feature="${4:-}"
  local out="$tmpl"
  out="${out//\{ticket\}/$ticket}"
  out="${out//\{slug\}/$slug}"
  out="${out//\{feature\}/$feature}"
  printf '%s' "$out"
}

# Pre-flight: validate every selected project before any mutation.
# Args: $1 csv-of-aliases, $2 effective-feature, $3 workspace-base (may be empty).
# Returns 0 on success, non-zero with diagnostic on first failure.
ws_pre_flight_validate() {
  local aliases_csv="$1" feature="$2" workspace_base="$3"
  local IFS=','
  local alias
  for alias in $aliases_csv; do
    [[ -z "$alias" ]] && continue
    local proj_path="${WS_PROJECT_PATHS[$alias]}"
    local branch base
    branch="$(resolve_branch_for_alias "$alias" "$feature")"
    base="$(resolve_base_for_alias "$alias" "$workspace_base")"
    validate_branch_name "$branch"

    git -C "$proj_path" rev-parse -q --verify "$base" &>/dev/null \
      || die "project '$alias': base ref '$base' does not exist"

    if [[ -d "$proj_path/.worktrees/$branch" ]]; then
      die "project '$alias': worktree already exists at $proj_path/.worktrees/$branch"
    fi
    if git -C "$proj_path" worktree list --porcelain | awk '/^branch /{print $2}' | grep -qx "refs/heads/$branch"; then
      die "project '$alias': branch '$branch' already has a worktree"
    fi
  done
  return 0
}

# Create a worktree for one project. Internal helper for cmd_workspace_create.
# Args: $1 alias, $2 branch, $3 base, $4 ai_tool, $5 custom_config
# On success: prints "alias|branch|base|worktree_path" to stdout (records line).
# On failure: returns non-zero.
ws_create_one_project() {
  local alias="$1" branch="$2" base="$3" ai_tool="$4" custom_config="${5:-}"
  local proj_path="${WS_PROJECT_PATHS[$alias]}"
  local wt="$proj_path/.worktrees/$branch"

  # Redirect all log/git/sync chatter to stderr; keep stdout exclusive for the record line.
  {
    log "[$alias] worktree add $branch from $base"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      log "  (dry-run) would: git -C $proj_path worktree add -b $branch $wt $base"
    else
      _ws_run_project_phase "$alias" "$branch" "$base" preCreate "$custom_config" || true

      if ! git -C "$proj_path" worktree add -b "$branch" "$wt" "$base"; then
        err "[$alias] git worktree add failed"
        return 1
      fi

      local exclude_file="$proj_path/.git/info/exclude"
      if [[ -d "$(dirname "$exclude_file")" ]]; then
        touch "$exclude_file" 2>/dev/null || true
        grep -qxF '.worktrees/' "$exclude_file" 2>/dev/null \
          || printf '%s\n' '.worktrees/' >> "$exclude_file"
      fi

      local _saved_root="$GIT_ROOT"
      GIT_ROOT="$proj_path"
      load_config "$custom_config"
      copy_sensitive_files "$wt"
      symlink_node_modules "$wt"
      trust_dev_tools "$proj_path" "$wt"
      GIT_ROOT="$_saved_root"

      local meta_dir="$proj_path/.worktrees/.metadata"
      mkdir -p "$meta_dir"
      cat > "$meta_dir/$(_basename_safe "$branch").json" <<JSON
{"baseBranch":"$base","createdAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","aiTool":"$ai_tool"}
JSON

      _ws_run_project_phase "$alias" "$branch" "$base" postCreate "$custom_config" || true
    fi
  } >&2

  printf '%s|%s|%s|%s\n' "$alias" "$branch" "$base" "$wt"
}

# Internal: load per-project config and run a single hook phase.
_ws_run_project_phase() {
  local alias="$1" branch="$2" base="$3" phase="$4" custom_config="${5:-}"
  local _saved_root="$GIT_ROOT"
  GIT_ROOT="${WS_PROJECT_PATHS[$alias]}"
  load_config "$custom_config"
  run_hook "$phase" \
    "BRANCH=$branch" "BASE=$base" \
    "WORKTREE_PATH=$GIT_ROOT/.worktrees/$branch" \
    "PROJECT_ALIAS=$alias" "WORKSPACE_ROOT=$WORKSPACE_ROOT"
  GIT_ROOT="$_saved_root"
}

# Slashes in branch names are common; per-project metadata files use last segment + sha to avoid clashes.
# Match historical single-mode behavior: the metadata file is keyed by literal branch name with '/' allowed.
_basename_safe() {
  local s="$1"
  s="${s//\//__}"
  printf '%s' "$s"
}

# Roll back a list of created projects: remove worktrees and per-project metadata.
# Args: newline-separated records "alias|branch|base|worktreePath"
ws_rollback_projects() {
  local records="$1"
  [[ -z "$records" ]] && return 0
  local alias branch base wpath
  while IFS='|' read -r alias branch base wpath; do
    [[ -z "$alias" ]] && continue
    local proj_path="${WS_PROJECT_PATHS[$alias]}"
    warn "[$alias] rolling back $branch"
    git -C "$proj_path" worktree remove --force "$wpath" 2>/dev/null || true
    git -C "$proj_path" branch -D "$branch" 2>/dev/null || true
    rm -f "$proj_path/.worktrees/.metadata/$(_basename_safe "$branch").json"
  done <<< "$records"
}

# Build the symlink hub: <workspace>/.worktrees/<feature>/<alias> -> per-project worktree.
# Args: $1 feature, $2 records (newline-separated alias|branch|base|wpath)
ws_build_symlink_hub() {
  local feature="$1" records="$2"
  local hub
  hub="$(ws_hub_dir "$feature")"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "(dry-run) would build symlink hub at $hub"
    return 0
  fi
  if [[ -e "$hub" || -L "$hub" ]]; then
    rm -rf "$hub" 2>/dev/null || true
  fi
  mkdir -p "$hub"

  local alias branch base wpath
  while IFS='|' read -r alias branch base wpath; do
    [[ -z "$alias" ]] && continue
    local target="$hub/$alias"
    if [[ "$WS_SYMLINK_LAYER" -eq 1 ]]; then
      local rp
      rp="$(relpath "$hub" "$wpath")"
      if ! ln -s "$rp" "$target" 2>/dev/null; then
        warn "symlink failed for $alias; falling back to README pointer"
        printf '%s\n' "$wpath" > "$target.path"
      fi
    else
      printf '%s\n' "$wpath" > "$target.path"
    fi
  done <<< "$records"
}

# Tear down symlink hub for a feature.
ws_teardown_symlink_hub() {
  local feature="$1"
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  local hub
  hub="$(ws_hub_dir "$feature")"
  [[ -e "$hub" || -L "$hub" ]] && rm -rf "$hub"
  # Also clean up empty parent dirs (e.g. .worktrees/feat/) if no other features sit there.
  local p
  p="$(dirname "$hub")"
  while [[ -d "$p" && "$p" != "$WORKSPACE_ROOT/.worktrees" && "$p" != "/" ]]; do
    rmdir "$p" 2>/dev/null || break
    p="$(dirname "$p")"
  done
}

# Generate a workspace config from auto-discovery.
# Args: $1 target dir (defaults to $PWD), $2 name (defaults to basename), $3 force (1/0)
ws_init_config() {
  local target="${1:-$PWD}" name="${2:-}" force="${3:-0}"
  target="$(cd "$target" 2>/dev/null && pwd)" || die "target dir does not exist: $1"
  [[ -z "$name" ]] && name="$(basename "$target")"
  local out="$target/$WORKSPACE_CONFIG_FILE"
  if [[ -f "$out" && "$force" -ne 1 ]]; then
    die "$out already exists (use --force to overwrite)"
  fi

  local repos=()
  while IFS= read -r -d '' p; do
    repos+=("$p")
  done < <(discover_git_repos "$target")

  [[ ${#repos[@]} -ge 1 ]] || die "no git repos found at depth 1 under $target"

  require_cmd jq "Install jq for workspace init"

  local projects_json
  projects_json="$(
    for r in "${repos[@]}"; do
      local alias rel default_base
      alias="$(basename "$r")"
      alias="$(printf '%s' "$alias" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
      [[ -z "$alias" ]] && continue
      rel="./$(basename "$r")"
      default_base=""
      if git -C "$r" rev-parse -q --verify origin/HEAD &>/dev/null; then
        default_base="origin/HEAD"
      elif git -C "$r" rev-parse -q --verify main &>/dev/null; then
        default_base="main"
      elif git -C "$r" rev-parse -q --verify master &>/dev/null; then
        default_base="master"
      fi
      jq -n --arg a "$alias" --arg p "$rel" --arg b "$default_base" \
         'if $b == "" then {alias:$a, path:$p} else {alias:$a, path:$p, defaultBase:$b} end'
    done | jq -s '.'
  )"

  jq -n \
    --arg name "$name" \
    --argjson projects "$projects_json" \
    '{version:1, workspace:{name:$name, projects:$projects, symlinkLayer:true, rollback:"strict"}}' \
    > "$out"

  log "Wrote $out (${#repos[@]} project(s))"
}
