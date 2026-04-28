#!/usr/bin/env bash
# config.sh - configuration loader for super-worktree
# Sources util.sh for log/warn/die.
# Populates globals: COPY_FILES, SYMLINK_DIRS, EXCLUDE, HOOKS, COPY_DEPTH

declare -ga COPY_FILES=()
declare -ga COPY_NEGATE=()
declare -ga SYMLINK_DIRS=()
declare -ga EXCLUDE=()
declare -gA HOOKS=()
declare -g  COPY_DEPTH=2
declare -g  CONFIG_VERSION=1

_default_config() {
  COPY_FILES=(
    ".env" ".env.*" ".envrc" ".local.*"
    "*.secret" "*.key" ".secrets.*"
    "credentials.json" "credentials.yml" "credentials.env"
    "auth.json" "auth.yml" "auth.env"
    ".dev.vars" ".prod.vars" ".staging.vars"
  )
  COPY_NEGATE=(".env.example" ".env.sample" ".env.template")
  SYMLINK_DIRS=("node_modules")
  EXCLUDE=(
    "node_modules" ".git" "dist" "build" ".next"
    "out" "coverage" ".turbo" ".vercel" ".worktrees"
  )
  HOOKS=()
  COPY_DEPTH=2
}

# Expand $VAR / ${VAR} in a string. Whitelisted for safety.
_expand_env() {
  local raw="$1"
  local out="$raw"
  out="${out//\$\{HOME\}/$HOME}"
  out="${out//\$HOME/$HOME}"
  out="${out//\$\{USER\}/${USER:-}}"
  out="${out//\$USER/${USER:-}}"
  out="${out//\$\{XDG_CONFIG_HOME\}/${XDG_CONFIG_HOME:-$HOME/.config}}"
  printf '%s' "$out"
}

_merge_jq_array() {
  local file="$1" path="$2" target="$3"
  local raw
  raw=$(jq -r "$path // empty | .[]?" "$file" 2>/dev/null) || return 0
  [[ -z "$raw" ]] && return 0
  declare -n arr_ref="$target"
  arr_ref=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && arr_ref+=("$(_expand_env "$line")")
  done <<< "$raw"
  return 0
}

# Split copyFiles into positive + negate (!) lists in-place.
_partition_negation() {
  local positives=() negatives=()
  for entry in "${COPY_FILES[@]}"; do
    if [[ "$entry" == \!* ]]; then
      negatives+=("${entry#!}")
    else
      positives+=("$entry")
    fi
  done
  COPY_FILES=("${positives[@]}")
  if [[ "${#negatives[@]}" -gt 0 ]]; then
    COPY_NEGATE=("${negatives[@]}")
  fi
}

_merge_jq_hooks() {
  local file="$1"
  local phase val
  for phase in preCreate postCreate preDelete postDelete; do
    val=$(jq -r ".hooks.$phase // empty" "$file" 2>/dev/null || echo "")
    [[ -n "$val" ]] && HOOKS["$phase"]="$val"
  done
  return 0
}

_merge_jq_scalar() {
  local file="$1" path="$2" var="$3"
  local val
  val=$(jq -r "$path // empty" "$file" 2>/dev/null || echo "")
  if [[ -n "$val" ]]; then
    declare -n ref="$var"
    ref="$val"
  fi
  return 0
}

_load_one() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  if ! command -v jq &>/dev/null; then
    warn "jq not installed; skipping $file. Install jq for full config support."
    return 0
  fi
  if ! jq empty "$file" &>/dev/null; then
    warn "invalid JSON in $file; skipping"
    return 0
  fi
  local version
  version=$(jq -r '.version // empty' "$file" 2>/dev/null || echo "")
  if [[ -n "$version" && "$version" != "$CONFIG_VERSION" ]]; then
    warn "config $file declares version $version; this build expects $CONFIG_VERSION"
  fi

  _merge_jq_array  "$file" '.sync.copyFiles'   COPY_FILES
  _merge_jq_array  "$file" '.sync.symlinkDirs' SYMLINK_DIRS
  _merge_jq_array  "$file" '.sync.exclude'     EXCLUDE
  _merge_jq_scalar "$file" '.sync.copyDepth'   COPY_DEPTH
  _merge_jq_hooks  "$file"
}

# Loads in order: defaults → global → project → custom (later wins).
load_config() {
  local custom="${1:-}"
  _default_config
  _load_one "$HOME/.config/super-worktree/config.json"
  _load_one "$GIT_ROOT/.super-worktree.json"
  _load_one "$GIT_ROOT/super-worktree.json"
  [[ -n "$custom" ]] && _load_one "$custom"
  _partition_negation
  return 0
}
