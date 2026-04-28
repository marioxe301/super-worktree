#!/usr/bin/env bash
# util.sh - shared helpers for super-worktree
# shellcheck disable=SC2034

SUPER_WORKTREE_VERSION="0.2.0"

log()  { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
err()  { printf 'Error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    err "required command not found: $cmd"
    [[ -n "$hint" ]] && err "$hint"
    exit 1
  fi
}

# Detached background launch — survives parent process exit.
# Falls back to nohup-disown on systems without setsid.
detach_run() {
  if command -v setsid &>/dev/null; then
    setsid nohup "$@" >/dev/null 2>&1 < /dev/null &
  else
    nohup "$@" >/dev/null 2>&1 < /dev/null &
  fi
  disown 2>/dev/null || true
}

validate_branch_name() {
  local name="$1"
  [[ -z "$name" ]] && die "branch name required"
  if ! git check-ref-format --branch "$name" &>/dev/null; then
    die "invalid branch name: $name"
  fi
  case "$name" in
    -*|*..*|*~*|*^*|*:*|*\?*|*\**|*\[*) die "invalid branch name: $name" ;;
  esac
}

# Portable replacement for `realpath --relative-to`.
relpath() {
  local from="$1" to="$2"
  python3 - "$from" "$to" <<'PY' 2>/dev/null || printf '%s' "$to"
import os, sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
}

run_hook() {
  local phase="$1"; shift
  local hook_cmd="${HOOKS[$phase]:-}"
  [[ -z "$hook_cmd" ]] && return 0
  log "Running hook ($phase)..."
  ( cd "$GIT_ROOT" && env "$@" bash -c "$hook_cmd" ) || warn "hook $phase exited non-zero"
}

print_cd_hint() {
  local path="$1"
  if [[ "${PRINT_CD:-0}" == "1" ]]; then
    printf 'cd %q\n' "$path"
    return
  fi
  log ""
  log "========================================"
  log "Worktree ready at: $path"
  log "  cd $path"
  log "========================================"
}
