#!/usr/bin/env bash
# super-worktree - git worktree manager with env file copying and node_modules
# symlinking. Prints a copy-pasteable cd hint after create.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/util.sh
source "$SCRIPT_DIR/lib/util.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/sync.sh
source "$SCRIPT_DIR/lib/sync.sh"
# shellcheck source=lib/workspace.sh
source "$SCRIPT_DIR/lib/workspace.sh"
# shellcheck source=lib/workspace_meta.sh
source "$SCRIPT_DIR/lib/workspace_meta.sh"

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

# Workspace detection runs first; single-repo globals are populated lazily and
# the single-mode guard fires only when a single-mode command actually needs them.
detect_workspace
GIT_ROOT="$(_resolve_git_root || true)"
WORKTREE_DIR=""
META_DIR=""
if [[ -n "$GIT_ROOT" ]]; then
  WORKTREE_DIR="$GIT_ROOT/.worktrees"
  META_DIR="$WORKTREE_DIR/.metadata"
fi

_require_single_mode() {
  if [[ -z "$GIT_ROOT" ]]; then
    if [[ "$WORKSPACE_MODE" -eq 1 ]]; then
      die "this command requires a single git repo cwd. Workspace detected at $WORKSPACE_ROOT — use 'workspace ...' subcommands."
    fi
    die "not inside a git repository"
  fi
}

DRY_RUN="${DRY_RUN:-0}"
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

Single-repo:
  $(basename "$0") create <branch> [from-branch] [options]
  $(basename "$0") delete <branch>
  $(basename "$0") merge  <branch>
  $(basename "$0") sync   <branch>
  $(basename "$0") list   [--json]
  $(basename "$0") status [--json]
  $(basename "$0") prune

Workspace (parent folder with multiple sibling repos):
  $(basename "$0") workspace init    [--auto-discover] [--name <n>]
  $(basename "$0") workspace list    [--json]
  $(basename "$0") workspace create  <feature> [--projects api,ui|--all] [options]
  $(basename "$0") workspace status  <feature> [--json]
  $(basename "$0") workspace sync    <feature>
  $(basename "$0") workspace delete  <feature> [--force|--force-all]
  $(basename "$0") workspace merge   <feature>
  $(basename "$0") workspace prune

Misc:
  $(basename "$0") version
  $(basename "$0") help

Create options:
  --config <file>     Custom config JSON
  --tool <name>       AI tool name appended to printed cd hint (e.g. 'claude')
  --ticket <id>       Ticket id for branch templating (e.g. WFL-1234)
  --slug <text>       Slug for branch templating (kebab-cased)
  --from-pr <num>     Check out a GitHub PR (requires gh)
  --print-cd          Print 'cd <path>' line to stdout (for shell eval)
  --dry-run           Print intended actions; make no changes

Workspace create options:
  --projects a,b      Comma list of aliases (default: defaultProjects, else all)
  --all               Override defaults; create in every declared project
  --base <ref>        Workspace-wide base; per-project defaultBase wins if set
  --per-project-base api=develop,ui=main
  --branch <name>     Explicit branch name (skips template)
  --branch-override api=feat/x-api,ui=feat/x-ui

Environment:
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
  # Workspace auto-route: at workspace root with no enclosing single git repo,
  # forward verbatim args to the workspace create dispatcher.
  if [[ "$WORKSPACE_MODE" -eq 1 && -z "$GIT_ROOT" ]]; then
    cmd_workspace_create "$@"
    return $?
  fi
  _require_single_mode
  local branch="" from_branch="" custom_config="" cli_tool="" ticket="" slug="" from_pr=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)    custom_config="$2"; shift 2 ;;
      --tool)      cli_tool="$2";      shift 2 ;;
      --ticket)    ticket="$2";        shift 2 ;;
      --slug)      slug="$2";          shift 2 ;;
      --from-pr)   from_pr="$2";       shift 2 ;;
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

  write_metadata "$branch" "$base_ref" "$cli_tool"

  run_hook postCreate "BRANCH=$branch" "BASE=$base_ref" "WORKTREE_PATH=$WORKTREE_DIR/$branch"

  print_cd_hint "$WORKTREE_DIR/$branch" "$cli_tool"

  WORKTREE_CREATED=0
}

cmd_delete() {
  _require_single_mode
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
  _require_single_mode
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
  _require_single_mode
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
  _require_single_mode
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
  _require_single_mode
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
  _require_single_mode
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

_require_workspace_mode() {
  if [[ "$WORKSPACE_MODE" -ne 1 ]]; then
    die "no super-worktree.workspace.json found from cwd or any ancestor. Run 'workspace init' to create one."
  fi
}

cmd_workspace() {
  local sub="${1:-help}"
  shift || true
  case "$sub" in
    init)    cmd_workspace_init    "$@" ;;
    list)    cmd_workspace_list    "$@" ;;
    create)  cmd_workspace_create  "$@" ;;
    status)  cmd_workspace_status  "$@" ;;
    sync)    cmd_workspace_sync    "$@" ;;
    delete)  cmd_workspace_delete  "$@" ;;
    merge)   cmd_workspace_merge   "$@" ;;
    prune)   cmd_workspace_prune   "$@" ;;
    help|--help|-h|"") usage ;;
    *) err "unknown workspace subcommand: $sub"; usage; exit 1 ;;
  esac
}

cmd_workspace_init() {
  local target="$PWD" name="" force=0 auto_discover=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --target) target="$2"; shift 2 ;;
      --force) force=1; shift ;;
      --auto-discover) auto_discover=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  ws_init_config "$target" "$name" "$force"
  log "Edit super-worktree.workspace.json to refine project list, defaultProjects, hooks."
}

cmd_workspace_create() {
  _require_workspace_mode

  local feature="" projects_csv="" workspace_base=""
  local pp_base="" pp_branch="" branch_explicit=""
  local ticket="" slug="" cli_tool="" custom_config=""
  local symlink_layer_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --projects)         projects_csv="$2"; shift 2 ;;
      --all)              projects_csv="all"; shift ;;
      --base)             workspace_base="$2"; shift 2 ;;
      --per-project-base) pp_base="$2"; shift 2 ;;
      --branch)           branch_explicit="$2"; shift 2 ;;
      --branch-override)  pp_branch="$2"; shift 2 ;;
      --ticket)           ticket="$2"; shift 2 ;;
      --slug)             slug="$2"; shift 2 ;;
      --tool)             cli_tool="$2"; shift 2 ;;
      --config)           custom_config="$2"; shift 2 ;;
      --no-symlink-layer) symlink_layer_override=0; shift ;;
      --print-cd)         PRINT_CD=1; shift ;;
      --dry-run)          DRY_RUN=1; shift ;;
      -*)                 die "unknown flag: $1" ;;
      *)
        if [[ -z "$feature" ]]; then feature="$1"; else die "unexpected arg: $1"; fi
        shift ;;
    esac
  done

  # Resolve effective feature name.
  if [[ -n "$branch_explicit" ]]; then
    feature="$branch_explicit"
  elif [[ -n "$ticket" || -n "$slug" ]]; then
    local ticket_lc="${ticket,,}"
    local slug_kebab=""
    [[ -n "$slug" ]] && slug_kebab="$(_slugify "$slug")"
    if [[ -n "$WS_BRANCH_TEMPLATE" ]]; then
      feature="$(ws_branch_template_render "$WS_BRANCH_TEMPLATE" "$ticket_lc" "$slug_kebab" "$feature")"
    else
      feature="${ticket_lc}${slug_kebab:+${ticket_lc:+-}$slug_kebab}"
    fi
  fi
  [[ -z "$feature" ]] && die "feature name required: <feature> or --branch <name> or --ticket/--slug"
  validate_branch_name "$feature"

  # Resolve project selection.
  local aliases_arr=()
  while IFS= read -r a; do [[ -n "$a" ]] && aliases_arr+=("$a"); done \
    < <(resolve_project_selection "$projects_csv")
  [[ ${#aliases_arr[@]} -gt 0 ]] || die "no projects selected"
  local aliases_csv
  aliases_csv="$(IFS=','; echo "${aliases_arr[*]}")"

  parse_per_project_base   "$pp_base"
  parse_per_project_branch "$pp_branch"

  # Honor explicit --no-symlink-layer.
  if [[ -n "$symlink_layer_override" ]]; then
    WS_SYMLINK_LAYER="$symlink_layer_override"
  fi

  log "Workspace: $WORKSPACE_NAME  feature=$feature  projects=$aliases_csv"

  # Pre-flight: validate every selected project.
  ws_pre_flight_validate "$aliases_csv" "$feature" "$workspace_base"

  # Hub directory pre-check.
  local hub
  hub="$(ws_hub_dir "$feature")"
  if [[ -e "$hub" || -L "$hub" ]] && [[ "${DRY_RUN:-0}" -eq 0 ]]; then
    die "hub directory already exists: $hub"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "(dry-run) would create the following:"
    local a
    for a in "${aliases_arr[@]}"; do
      local b base
      b="$(resolve_branch_for_alias "$a" "$feature")"
      base="$(resolve_base_for_alias "$a" "$workspace_base")"
      log "  [$a] branch=$b base=$base path=${WS_PROJECT_PATHS[$a]}/.worktrees/$b"
    done
    log "  hub=$hub  symlinkLayer=$WS_SYMLINK_LAYER  rollback=$WS_ROLLBACK"
    return 0
  fi

  ensure_workspace_local_excludes

  run_ws_hook preCreateAll \
    "FEATURE=$feature" "PROJECTS=$aliases_csv" \
    "WORKSPACE_ROOT=$WORKSPACE_ROOT" "WORKTREE_ROOT_DIR=$hub"

  # Sequential per-project creation with rollback tracking.
  local records=""
  local a b base line ok=1
  for a in "${aliases_arr[@]}"; do
    b="$(resolve_branch_for_alias "$a" "$feature")"
    base="$(resolve_base_for_alias "$a" "$workspace_base")"
    if line="$(ws_create_one_project "$a" "$b" "$base" "$cli_tool" "$custom_config")"; then
      records+="$line"$'\n'
    else
      ok=0
      err "[$a] create failed; aborting workspace create"
      break
    fi
  done

  if [[ "$ok" -ne 1 ]]; then
    if [[ "$WS_ROLLBACK" == "strict" ]]; then
      ws_rollback_projects "$records"
      die "workspace create rolled back ($WS_ROLLBACK)"
    else
      warn "workspace create failed; left partial state in place ($WS_ROLLBACK)"
      ws_meta_write "$feature" "$cli_tool" "$records" || true
      exit 1
    fi
  fi

  ws_build_symlink_hub "$feature" "$records"
  ws_meta_write "$feature" "$cli_tool" "$records"

  run_ws_hook postCreateAll \
    "FEATURE=$feature" "PROJECTS=$aliases_csv" \
    "WORKSPACE_ROOT=$WORKSPACE_ROOT" "WORKTREE_ROOT_DIR=$hub"

  print_workspace_cd_block "$feature" "$hub" "$records" "$cli_tool"
}

# Resolve a per-project worktreePath from metadata (which stores it as ./api/.worktrees/...)
# into an absolute path under WORKSPACE_ROOT.
_ws_abs_wt() {
  local wpath="$1"
  if [[ "$wpath" == .* ]]; then
    printf '%s/%s' "$WORKSPACE_ROOT" "${wpath#./}"
  else
    printf '%s' "$wpath"
  fi
}

cmd_workspace_status() {
  _require_workspace_mode
  local feature="" json_out=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_out=1; shift ;;
      -*) die "unknown flag: $1" ;;
      *) feature="$1"; shift ;;
    esac
  done
  [[ -n "$feature" ]] || die "feature required"
  ws_meta_iter_projects "$feature" >/dev/null \
    || die "no metadata for feature '$feature'"

  if [[ "$json_out" -eq 1 ]]; then
    require_cmd jq "Install jq for --json output"
    local first=1
    printf '['
    while IFS='|' read -r alias branch base wpath; do
      [[ -z "$alias" ]] && continue
      local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
      local dirty
      dirty=$(git -C "$abs_wt" status --porcelain 2>/dev/null | wc -l)
      [[ $first -eq 0 ]] && printf ','
      first=0
      jq -n --arg a "$alias" --arg b "$branch" --arg p "$abs_wt" --argjson d "$dirty" \
         '{alias:$a, branch:$b, path:$p, dirty:$d}'
    done < <(ws_meta_iter_projects "$feature")
    printf ']\n'
    return 0
  fi

  printf 'Feature: %s\n' "$feature"
  while IFS='|' read -r alias branch base wpath; do
    [[ -z "$alias" ]] && continue
    local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
    local dirty
    dirty=$(git -C "$abs_wt" status --porcelain 2>/dev/null | wc -l)
    if [[ "$dirty" -gt 0 ]]; then
      printf '  %-16s [DIRTY: %d file(s)] %s\n' "$alias" "$dirty" "$abs_wt"
    else
      printf '  %-16s [clean]              %s\n' "$alias" "$abs_wt"
    fi
  done < <(ws_meta_iter_projects "$feature")
}

cmd_workspace_sync() {
  _require_workspace_mode
  local feature="" custom_config=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) custom_config="$2"; shift 2 ;;
      -*) die "unknown flag: $1" ;;
      *) feature="$1"; shift ;;
    esac
  done
  [[ -n "$feature" ]] || die "feature required"
  ws_meta_iter_projects "$feature" >/dev/null \
    || die "no metadata for feature '$feature'"

  log "Syncing workspace feature '$feature'..."
  local _saved_root="$GIT_ROOT"
  while IFS='|' read -r alias branch base wpath; do
    [[ -z "$alias" ]] && continue
    local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
    [[ -d "$abs_wt" ]] || { warn "[$alias] worktree missing: $abs_wt; skipping"; continue; }
    log "[$alias] sync $abs_wt"
    GIT_ROOT="${WS_PROJECT_PATHS[$alias]}"
    load_config "$custom_config"
    copy_sensitive_files "$abs_wt"
    symlink_node_modules "$abs_wt"
    trust_dev_tools "${WS_PROJECT_PATHS[$alias]}" "$abs_wt"
  done < <(ws_meta_iter_projects "$feature")
  GIT_ROOT="$_saved_root"
  log "Sync complete."
}

cmd_workspace_delete() {
  _require_workspace_mode
  local feature="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|--force-all) force=1; shift ;;
      -*)                  die "unknown flag: $1" ;;
      *)                   feature="$1"; shift ;;
    esac
  done
  [[ -n "$feature" ]] || die "feature required"
  ws_meta_iter_projects "$feature" >/dev/null \
    || die "no metadata for feature '$feature'"

  if [[ "$force" -eq 0 ]]; then
    local dirty_aliases=()
    while IFS='|' read -r alias branch base wpath; do
      [[ -z "$alias" ]] && continue
      local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
      local dirty
      dirty=$(git -C "$abs_wt" status --porcelain 2>/dev/null | wc -l)
      [[ "$dirty" -gt 0 ]] && dirty_aliases+=("$alias")
    done < <(ws_meta_iter_projects "$feature")
    if [[ ${#dirty_aliases[@]} -gt 0 ]]; then
      die "dirty projects: ${dirty_aliases[*]}. Re-run with --force or --force-all."
    fi
  fi

  run_ws_hook preDeleteAll \
    "FEATURE=$feature" "WORKSPACE_ROOT=$WORKSPACE_ROOT"

  while IFS='|' read -r alias branch base wpath; do
    [[ -z "$alias" ]] && continue
    local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
    local proj_path="${WS_PROJECT_PATHS[$alias]:-}"
    [[ -z "$proj_path" ]] && { warn "[$alias] no longer in workspace config; skipping"; continue; }

    log "[$alias] removing worktree $branch"
    _ws_run_project_phase "$alias" "$branch" "$base" preDelete "" || true
    git -C "$proj_path" worktree remove --force "$abs_wt" 2>/dev/null || true
    git -C "$proj_path" branch -D "$branch" 2>/dev/null || true
    rm -f "$proj_path/.worktrees/.metadata/$(_basename_safe "$branch").json"
    _ws_run_project_phase "$alias" "$branch" "$base" postDelete "" || true
  done < <(ws_meta_iter_projects "$feature")

  ws_teardown_symlink_hub "$feature"
  ws_meta_remove "$feature"

  run_ws_hook postDeleteAll \
    "FEATURE=$feature" "WORKSPACE_ROOT=$WORKSPACE_ROOT"

  log "Workspace feature '$feature' deleted."
}

cmd_workspace_merge() {
  _require_workspace_mode
  local feature="${1:-}"
  [[ -n "$feature" ]] || die "feature required"
  ws_meta_iter_projects "$feature" >/dev/null \
    || die "no metadata for feature '$feature'"

  while IFS='|' read -r alias branch base wpath; do
    [[ -z "$alias" ]] && continue
    local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
    local proj_path="${WS_PROJECT_PATHS[$alias]:-}"
    [[ -z "$proj_path" ]] && continue
    local upstream
    upstream="$(git -C "$proj_path" rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "")"
    if [[ -n "$upstream" ]]; then
      log "[$alias] merging $branch into $upstream"
      git -C "$proj_path" checkout "$upstream"
      git -C "$proj_path" merge --no-ff "$branch"
    else
      warn "[$alias] no upstream for '$branch'; skipping merge"
    fi
    git -C "$proj_path" worktree remove --force "$abs_wt" 2>/dev/null || true
    rm -f "$proj_path/.worktrees/.metadata/$(_basename_safe "$branch").json"
  done < <(ws_meta_iter_projects "$feature")

  ws_teardown_symlink_hub "$feature"
  ws_meta_remove "$feature"
  log "Workspace feature '$feature' merged + cleaned."
}

cmd_workspace_prune() {
  _require_workspace_mode
  log "Pruning workspace metadata + per-project worktrees..."
  local alias proj_path
  for alias in "${WS_PROJECT_ALIASES[@]}"; do
    proj_path="${WS_PROJECT_PATHS[$alias]}"
    git -C "$proj_path" worktree prune -v 2>&1 | sed "s|^|  [$alias] |"
  done

  local feature
  while IFS= read -r feature; do
    [[ -z "$feature" ]] && continue
    local missing=0
    while IFS='|' read -r a b base wpath; do
      [[ -z "$a" ]] && continue
      local abs_wt; abs_wt="$(_ws_abs_wt "$wpath")"
      [[ -d "$abs_wt" ]] || missing=1
    done < <(ws_meta_iter_projects "$feature")
    if [[ "$missing" -eq 1 ]]; then
      log "  removed orphan workspace metadata: $feature"
      ws_meta_remove "$feature"
      ws_teardown_symlink_hub "$feature"
    fi
  done < <(ws_meta_list)
}

# `workspace list` shows the parsed config plus any features (real or not).
cmd_workspace_list() {
  _require_workspace_mode
  local json_out=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_out=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  if [[ "$json_out" -eq 1 ]]; then
    require_cmd jq "Install jq for --json output"
    local features=()
    while IFS= read -r f; do [[ -n "$f" ]] && features+=("$f"); done < <(ws_meta_list)
    local first=1
    printf '{"workspace":'
    jq -n --arg n "$WORKSPACE_NAME" --arg r "$WORKSPACE_ROOT" \
       '{name:$n, root:$r}'
    printf ',"projects":['
    local alias
    for alias in "${WS_PROJECT_ALIASES[@]}"; do
      [[ $first -eq 0 ]] && printf ','
      first=0
      jq -n --arg a "$alias" --arg p "${WS_PROJECT_PATHS[$alias]}" --arg b "${WS_PROJECT_BASES[$alias]:-}" \
         '{alias:$a, path:$p, defaultBase:$b}'
    done
    printf '],"features":['
    first=1
    local feature
    for feature in "${features[@]}"; do
      [[ $first -eq 0 ]] && printf ','
      first=0
      ws_meta_read "$feature"
    done
    printf ']}\n'
    return 0
  fi

  printf 'Workspace: %s (%s)\n\n' "$WORKSPACE_NAME" "$WORKSPACE_ROOT"
  printf 'Projects:\n'
  printf '  %-16s %-10s %s\n' ALIAS BASE PATH
  local alias
  for alias in "${WS_PROJECT_ALIASES[@]}"; do
    printf '  %-16s %-10s %s\n' "$alias" "${WS_PROJECT_BASES[$alias]:-(auto)}" "${WS_PROJECT_PATHS[$alias]}"
  done

  printf '\nFeatures:\n'
  local features=()
  while IFS= read -r f; do [[ -n "$f" ]] && features+=("$f"); done < <(ws_meta_list)
  if [[ ${#features[@]} -eq 0 ]]; then
    printf '  (none)\n'
    return 0
  fi
  printf '  %-32s %s\n' FEATURE PROJECTS
  local feature plist
  for feature in "${features[@]}"; do
    plist=""
    if command -v jq &>/dev/null; then
      plist="$(jq -r '.projects[].alias' "$(ws_meta_path "$feature")" 2>/dev/null | paste -sd, -)"
    fi
    printf '  %-32s %s\n' "$feature" "${plist:-?}"
  done
}

main() {
  local cmd="${1:-help}"
  case "$cmd" in
    create)    shift; cmd_create    "$@" ;;
    delete)    shift; cmd_delete    "$@" ;;
    merge)     shift; cmd_merge     "$@" ;;
    sync)      shift; cmd_sync      "$@" ;;
    list)      shift; cmd_list      "$@" ;;
    status)    shift; cmd_status    "$@" ;;
    prune)     cmd_prune  ;;
    workspace) shift; cmd_workspace "$@" ;;
    version|--version|-v) cmd_version ;;
    help|--help|-h|"")    usage     ;;
    *) err "unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
