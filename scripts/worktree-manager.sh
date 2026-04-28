#!/usr/bin/env bash
# super-worktree - git worktree manager with env file copying, node_modules
# symlinking, AI tool detection, and detached terminal spawn.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/util.sh
source "$SCRIPT_DIR/lib/util.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/spawn.sh
source "$SCRIPT_DIR/lib/spawn.sh"
# shellcheck source=lib/sync.sh
source "$SCRIPT_DIR/lib/sync.sh"

_resolve_git_root() {
  local toplevel bare_dir
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$toplevel" ]]; then
    printf '%s' "$toplevel"
    return 0
  fi
  if [[ "$(git rev-parse --is-bare-repository 2>/dev/null || echo false)" == "true" ]]; then
    bare_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
    if [[ -n "$bare_dir" ]]; then
      ( cd "$bare_dir" && pwd )
      return 0
    fi
  fi
  return 1
}

GIT_ROOT="$(_resolve_git_root || true)"
[[ -z "$GIT_ROOT" ]] && die "not inside a git repository"
WORKTREE_DIR="$GIT_ROOT/.worktrees"
META_DIR="$WORKTREE_DIR/.metadata"

DRY_RUN="${DRY_RUN:-0}"
NO_SPAWN="${NO_SPAWN:-0}"
PRINT_CD="${PRINT_CD:-0}"
JSON_OUT="${JSON_OUT:-0}"

WORKTREE_CREATED=0
BRANCH_NAME=""

cleanup_on_err() {
  if [[ "$WORKTREE_CREATED" -eq 1 && -n "$BRANCH_NAME" && "$DRY_RUN" -eq 0 ]]; then
    warn "rolling back partial worktree '$BRANCH_NAME'"
    git worktree remove --force "$WORKTREE_DIR/$BRANCH_NAME" 2>/dev/null || true
    rm -f "$META_DIR/$BRANCH_NAME.json"
  fi
}
trap cleanup_on_err ERR

usage() {
  cat <<EOF
super-worktree v$SUPER_WORKTREE_VERSION

Usage:
  $(basename "$0") create <branch> [from-branch] [options]
  $(basename "$0") delete <branch>
  $(basename "$0") merge  <branch>
  $(basename "$0") sync   <branch>
  $(basename "$0") list   [--json]
  $(basename "$0") status [--json]
  $(basename "$0") prune
  $(basename "$0") version
  $(basename "$0") help

Create options:
  --config <file>     Custom config JSON
  --tool <name>       Force AI tool (claude, opencode, codex, ...)
  --ide <name>        Open IDE instead of AI tool (code, cursor, idea)
  --ticket <id>       Ticket id for branch templating (e.g. WFL-1234)
  --slug <text>       Slug for branch templating (kebab-cased)
  --from-pr <num>     Check out a GitHub PR (requires gh)
  --no-spawn          Skip terminal spawn
  --print-cd          Print 'cd <path>' line to stdout (for shell eval)
  --dry-run           Print intended actions; make no changes

Environment:
  SUPER_WORKTREE_TOOL  Override AI tool detection
  TRUST_DIRENV=1       Auto-run 'direnv allow' on copied .envrc
EOF
}

ensure_local_exclude() {
  local exclude_file="$GIT_ROOT/.git/info/exclude"
  mkdir -p "$(dirname "$exclude_file")"
  touch "$exclude_file"
  if ! grep -qxF '.worktrees/' "$exclude_file" 2>/dev/null; then
    [[ "$DRY_RUN" -eq 0 ]] && printf '%s\n' '.worktrees/' >> "$exclude_file"
    log "ensured .worktrees/ in .git/info/exclude"
  fi
}

write_metadata() {
  local branch="$1" base="$2" tool="$3"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  local out="$META_DIR/$branch.json"
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<EOF
{"baseBranch":"$base","createdAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","aiTool":"$tool"}
EOF
}

_slugify() {
  local s="$1"
  s="${s,,}"
  s="${s// /-}"
  s="${s//_/-}"
  s="$(printf '%s' "$s" | tr -cd 'a-z0-9-')"
  printf '%s' "$s"
}

cmd_create() {
  local branch="" from_branch="" custom_config="" cli_tool="" ide="" ticket="" slug="" from_pr=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)    custom_config="$2"; shift 2 ;;
      --tool)      cli_tool="$2";      shift 2 ;;
      --ide)       ide="$2";           shift 2 ;;
      --ticket)    ticket="$2";        shift 2 ;;
      --slug)      slug="$2";          shift 2 ;;
      --from-pr)   from_pr="$2";       shift 2 ;;
      --no-spawn)  NO_SPAWN=1;         shift   ;;
      --print-cd)  PRINT_CD=1;         shift   ;;
      --dry-run)   DRY_RUN=1;          shift   ;;
      -*)          die "unknown flag: $1" ;;
      *)
        if   [[ -z "$branch"      ]]; then branch="$1"
        elif [[ -z "$from_branch" ]]; then from_branch="$1"
        else die "unexpected arg: $1"
        fi
        shift
        ;;
    esac
  done

  if [[ -n "$ticket" || -n "$slug" ]]; then
    [[ -z "$branch" ]] || die "cannot combine positional <branch> with --ticket/--slug"
    branch="${ticket:+${ticket,,}}"
    [[ -n "$slug" ]] && branch="${branch:+$branch-}$(_slugify "$slug")"
  fi

  if [[ -n "$from_pr" ]]; then
    require_cmd gh "Install GitHub CLI (https://cli.github.com) to use --from-pr"
    [[ -z "$branch" ]] && branch="pr-$from_pr"
    log "Fetching PR #$from_pr ref via gh..."
    gh pr checkout --detach "$from_pr" >/dev/null 2>&1 || die "gh pr checkout failed for #$from_pr"
    from_branch="HEAD"
  fi

  validate_branch_name "$branch"

  local base_ref="${from_branch:-}"
  if [[ -z "$base_ref" ]]; then
    if git rev-parse -q --verify origin/HEAD &>/dev/null; then
      base_ref="origin/HEAD"
    else
      base_ref="main"
    fi
  fi
  git rev-parse -q --verify "$base_ref" &>/dev/null \
    || die "base ref '$base_ref' does not exist"

  if [[ -d "$WORKTREE_DIR/$branch" ]]; then
    die "worktree '$branch' already exists at '$WORKTREE_DIR/$branch'"
  fi
  if git worktree list --porcelain | awk '/^branch /{print $2}' | grep -qx "refs/heads/$branch"; then
    die "branch '$branch' already has a worktree"
  fi

  load_config "$custom_config"

  log "Creating worktree '$branch' from '$base_ref'..."
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "(dry-run) would: git worktree add -b $branch $WORKTREE_DIR/$branch $base_ref"
    log "(dry-run) copyFiles=${COPY_FILES[*]}"
    log "(dry-run) symlinkDirs=${SYMLINK_DIRS[*]}"
    log "(dry-run) hooks=${!HOOKS[*]}"
    return 0
  fi

  ensure_local_exclude

  run_hook preCreate "BRANCH=$branch" "BASE=$base_ref" "WORKTREE_PATH=$WORKTREE_DIR/$branch"

  mkdir -p "$WORKTREE_DIR"
  git worktree add -b "$branch" "$WORKTREE_DIR/$branch" "$base_ref"
  WORKTREE_CREATED=1
  BRANCH_NAME="$branch"

  copy_sensitive_files "$WORKTREE_DIR/$branch"
  symlink_node_modules "$WORKTREE_DIR/$branch"
  trust_dev_tools "$GIT_ROOT" "$WORKTREE_DIR/$branch"

  local resolved_tool
  resolved_tool=$(detect_ai_tool "$cli_tool")
  write_metadata "$branch" "$base_ref" "$resolved_tool"

  run_hook postCreate "BRANCH=$branch" "BASE=$base_ref" "WORKTREE_PATH=$WORKTREE_DIR/$branch"

  log ""
  log "Worktree ready: $WORKTREE_DIR/$branch"
  print_cd_hint "$WORKTREE_DIR/$branch"

  if [[ -n "$ide" ]]; then
    spawn_ide "$WORKTREE_DIR/$branch" "$ide"
  else
    spawn_terminal "$WORKTREE_DIR/$branch" "$branch" "$cli_tool"
  fi

  WORKTREE_CREATED=0
}

cmd_delete() {
  local branch="${1:-}"
  validate_branch_name "$branch"

  local worktree_path="$WORKTREE_DIR/$branch"
  [[ -d "$worktree_path" ]] || die "worktree '$branch' does not exist at '$worktree_path'"

  load_config ""

  local meta="$META_DIR/$branch.json"
  local base_branch="main"
  if [[ -f "$meta" ]] && command -v jq &>/dev/null; then
    base_branch=$(jq -r '.baseBranch // "main"' "$meta" 2>/dev/null || echo "main")
  fi

  run_hook preDelete "BRANCH=$branch" "WORKTREE_PATH=$worktree_path"

  log "Removing worktree for '$branch'..."
  git worktree remove --force "$worktree_path" 2>/dev/null || true
  rm -f "$meta"

  run_hook postDelete "BRANCH=$branch" "BASE=$base_branch"

  log ""
  log "========================================"
  log "Worktree deleted. Base branch: $base_branch"
  log "========================================"
}

cmd_merge() {
  local branch="${1:-}"
  validate_branch_name "$branch"

  local worktree_path="$WORKTREE_DIR/$branch"
  [[ -d "$worktree_path" ]] || die "worktree '$branch' does not exist"

  local upstream
  upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "")

  if [[ -n "$upstream" ]]; then
    log "Merging '$branch' into '$upstream'..."
    git checkout "$upstream"
    git merge --no-ff "$branch"
  else
    warn "no upstream configured for '$branch'; manual merge required"
  fi

  log "Removing worktree for '$branch'..."
  git worktree remove --force "$worktree_path"
  rm -f "$META_DIR/$branch.json"
  log "Done."
}

# Yields lines: "<branch>\t<path>" for worktrees under $WORKTREE_DIR.
_iter_worktrees() {
  git worktree list --porcelain 2>/dev/null | awk -v root="$WORKTREE_DIR" '
    /^worktree /        { path=$2; next }
    /^branch refs\/heads\// {
      sub("refs/heads/", "", $2); branch=$2
      if (index(path, root)==1) printf "%s\t%s\n", branch, path
    }
  '
}

cmd_list() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUT=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  if [[ "$JSON_OUT" -eq 1 ]]; then
    require_cmd jq "Install jq for --json output"
    local first=1
    printf '['
    while IFS=$'\t' read -r branch path; do
      [[ -z "$branch" ]] && continue
      local meta="$META_DIR/$branch.json"
      local base="null" created="null" tool="null"
      if [[ -f "$meta" ]]; then
        base=$(jq '.baseBranch // null'   "$meta")
        created=$(jq '.createdAt // null' "$meta")
        tool=$(jq '.aiTool // null'       "$meta")
      fi
      [[ $first -eq 0 ]] && printf ','
      first=0
      printf '{"branch":%s,"path":%s,"base":%s,"createdAt":%s,"aiTool":%s}' \
        "$(jq -Rn --arg v "$branch" '$v')" "$(jq -Rn --arg v "$path" '$v')" \
        "$base" "$created" "$tool"
    done < <(_iter_worktrees)
    printf ']\n'
    return 0
  fi

  printf '%-40s %-20s %-22s %s\n' BRANCH BASE CREATED TOOL
  while IFS=$'\t' read -r branch path; do
    [[ -z "$branch" ]] && continue
    local meta="$META_DIR/$branch.json"
    local base="?" created="?" tool="?"
    if [[ -f "$meta" ]] && command -v jq &>/dev/null; then
      base=$(jq -r '.baseBranch // "?"' "$meta")
      created=$(jq -r '.createdAt // "?"' "$meta")
      tool=$(jq -r '.aiTool // "?"' "$meta")
    fi
    printf '%-40s %-20s %-22s %s\n' "$branch" "$base" "$created" "$tool"
  done < <(_iter_worktrees)
}

cmd_status() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUT=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  if [[ "$JSON_OUT" -eq 1 ]]; then
    require_cmd jq "Install jq for --json output"
    local first=1
    printf '['
    while IFS=$'\t' read -r branch path; do
      [[ -z "$branch" ]] && continue
      local dirty
      dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l)
      [[ $first -eq 0 ]] && printf ','
      first=0
      printf '{"branch":%s,"path":%s,"dirty":%d}' \
        "$(jq -Rn --arg v "$branch" '$v')" "$(jq -Rn --arg v "$path" '$v')" "$dirty"
    done < <(_iter_worktrees)
    printf ']\n'
    return 0
  fi

  while IFS=$'\t' read -r branch path; do
    [[ -z "$branch" ]] && continue
    local dirty
    dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l)
    if [[ "$dirty" -gt 0 ]]; then
      printf '  %-40s [DIRTY: %d file(s)]\n' "$branch" "$dirty"
    else
      printf '  %-40s [clean]\n' "$branch"
    fi
  done < <(_iter_worktrees)
}

cmd_sync() {
  local branch="${1:-}" custom_config=""
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) custom_config="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  validate_branch_name "$branch"

  local worktree_path="$WORKTREE_DIR/$branch"
  [[ -d "$worktree_path" ]] || die "worktree '$branch' does not exist"

  load_config "$custom_config"

  log "Re-syncing worktree '$branch'..."
  copy_sensitive_files "$worktree_path"
  symlink_node_modules "$worktree_path"
  trust_dev_tools "$GIT_ROOT" "$worktree_path"
  log "Sync complete."
}

cmd_prune() {
  log "Pruning stale worktrees and metadata..."
  git worktree prune -v
  if [[ -d "$META_DIR" ]]; then
    while IFS= read -r -d '' meta; do
      local rel branch
      rel="${meta#"$META_DIR"/}"
      branch="${rel%.json}"
      if [[ ! -d "$WORKTREE_DIR/$branch" ]]; then
        rm -f "$meta"
        log "  removed orphan metadata: $branch"
      fi
    done < <(find "$META_DIR" -type f -name '*.json' -print0 2>/dev/null)
    find "$META_DIR" -type d -empty -delete 2>/dev/null || true
  fi
}

cmd_version() {
  log "super-worktree $SUPER_WORKTREE_VERSION"
}

main() {
  local cmd="${1:-help}"
  case "$cmd" in
    create)  shift; cmd_create  "$@" ;;
    delete)  shift; cmd_delete  "$@" ;;
    merge)   shift; cmd_merge   "$@" ;;
    sync)    shift; cmd_sync    "$@" ;;
    list)    shift; cmd_list    "$@" ;;
    status)  shift; cmd_status  "$@" ;;
    prune)   cmd_prune  ;;
    version|--version|-v) cmd_version ;;
    help|--help|-h|"")    usage     ;;
    *) err "unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
