#!/bin/bash
set -euo pipefail

GIT_ROOT=$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -n 1)
WORKTREE_DIR="$GIT_ROOT/.worktrees"
WORKTREE_CREATED=0
BRANCH_NAME=""

cleanup() {
  if [[ "$WORKTREE_CREATED" -eq 1 && -n "$BRANCH_NAME" ]]; then
    git worktree remove --force "$WORKTREE_DIR/$BRANCH_NAME" 2>/dev/null || true
  fi
}
trap cleanup ERR EXIT

usage() {
  cat <<EOF
super-worktree - Git worktree manager with env file copying and node_modules symlinking

Usage:
  $(basename "$0") create <branch> [from-branch] [--config <file>]
  $(basename "$0") delete <branch>
  $(basename "$0") merge <branch>
  $(basename "$0") help

Commands:
  create <branch> [from-branch] [--config <file>]
    Create a new worktree for <branch> from [from-branch] (defaults to origin/HEAD or main)
    --config <file>  Use custom config file

  delete <branch>
    Remove worktree for <branch>

  merge <branch>
    Merge branch and remove worktree (cleanup)

  help
    Show this help message

Examples:
  $(basename "$0") create feature/new-login
  $(basename "$0") create feature/payments --config .super-worktree.json
  $(basename "$0") delete feature/new-login
  $(basename "$0") merge feature/new-login

EOF
}

load_config() {
  local custom_config="${1:-}"
  local config_file=""
  local copyFiles=()
  local symlinkDirs=()
  local exclude=()

  # Default patterns
  copyFiles=(".env" ".env.*" ".envrc" ".local.*" "*.secret" "*.key" ".secrets.*" "credentials.json" "credentials.yml" "credentials.env" "auth.json" "auth.yml" "auth.env" ".dev.vars" ".prod.vars" ".staging.vars")
  symlinkDirs=("node_modules")
  exclude=("node_modules" ".git" "dist" "build" ".next" "out" "coverage" ".turbo" ".vercel" ".worktrees")

  # Try to load jq first, fallback to python3
  have_jq=false
  if command -v jq &> /dev/null; then
    have_jq=true
  fi

  # Load global config
  global_config="$HOME/.config/super-worktree/config.json"
  if [[ -f "$global_config" ]]; then
    if $have_jq; then
      local global_copy
      global_copy=$(jq -r '.sync.copyFiles // [] | join(" ")' "$global_config" 2>/dev/null || echo "")
      if [[ -n "$global_copy" ]]; then
        read -ra copyFiles <<< "$global_copy"
      fi
    else
      # python3 fallback for global
      python3 -c "
import json
import sys
try:
    with open('$global_config') as f:
        cfg = json.load(f)
        if 'sync' in cfg and 'copyFiles' in cfg['sync']:
            print(' '.join(cfg['sync']['copyFiles']))
except Exception:
    pass
" 2>/dev/null || true
    fi
  fi

  # Load project config
  project_config="$GIT_ROOT/.super-worktree.json"
  if [[ -f "$project_config" ]]; then
    if $have_jq; then
      local project_copy project_symlink project_exclude
      project_copy=$(jq -r '.sync.copyFiles // [] | join(" ")' "$project_config" 2>/dev/null || echo "")
      project_symlink=$(jq -r '.sync.symlinkDirs // [] | join(" ")' "$project_config" 2>/dev/null || echo "")
      project_exclude=$(jq -r '.sync.exclude // [] | join(" ")' "$project_config" 2>/dev/null || echo "")
      [[ -n "$project_copy" ]] && read -ra copyFiles <<< "$project_copy"
      [[ -n "$project_symlink" ]] && read -ra symlinkDirs <<< "$project_symlink"
      [[ -n "$project_exclude" ]] && read -ra exclude <<< "$project_exclude"
    else
      python3 -c "
import json
try:
    with open('$project_config') as f:
        cfg = json.load(f)
        if 'sync' in cfg:
            if 'copyFiles' in cfg['sync']:
                print(' '.join(cfg['sync']['copyFiles']))
            if 'symlinkDirs' in cfg['sync']:
                print(' '.join(cfg['sync']['symlinkDirs']))
            if 'exclude' in cfg['sync']:
                print(' '.join(cfg['sync']['exclude']))
except Exception:
    pass
" 2>/dev/null || true
    fi
  fi

  # Load custom config (highest priority)
  if [[ -n "$custom_config" && -f "$custom_config" ]]; then
    if $have_jq; then
      local custom_copy custom_symlink custom_exclude
      custom_copy=$(jq -r '.sync.copyFiles // [] | join(" ")' "$custom_config" 2>/dev/null || echo "")
      custom_symlink=$(jq -r '.sync.symlinkDirs // [] | join(" ")' "$custom_config" 2>/dev/null || echo "")
      custom_exclude=$(jq -r '.sync.exclude // [] | join(" ")' "$custom_config" 2>/dev/null || echo "")
      [[ -n "$custom_copy" ]] && read -ra copyFiles <<< "$custom_copy"
      [[ -n "$custom_symlink" ]] && read -ra symlinkDirs <<< "$custom_symlink"
      [[ -n "$custom_exclude" ]] && read -ra exclude <<< "$custom_exclude"
    else
      python3 -c "
import json
try:
    with open('$custom_config') as f:
        cfg = json.load(f)
        if 'sync' in cfg:
            if 'copyFiles' in cfg['sync']:
                print(' '.join(cfg['sync']['copyFiles']))
            if 'symlinkDirs' in cfg['sync']:
                print(' '.join(cfg['sync']['symlinkDirs']))
            if 'exclude' in cfg['sync']:
                print(' '.join(cfg['sync']['exclude']))
except Exception:
    pass
" 2>/dev/null || true
    fi
  fi

  echo "${copyFiles[*]}"
  echo "${symlinkDirs[*]}"
  echo "${exclude[*]}"
}

cmd_create() {
  local branch="${1:-}"
  local from_branch=""
  local custom_config=""

  # Parse arguments
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        custom_config="$2"
        shift 2
        ;;
      *)
        if [[ -z "$from_branch" ]]; then
          from_branch="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    echo "Error: branch name required" >&2
    exit 1
  fi

  # Determine base branch
  local base_ref="${from_branch:-}"
  if [[ -z "$base_ref" ]]; then
    if git rev-parse -q --verify origin/HEAD &>/dev/null; then
      base_ref="origin/HEAD"
    else
      base_ref="main"
    fi
  fi

  # Verify base ref exists
  if ! git rev-parse -q --verify "$base_ref" &>/dev/null; then
    echo "Error: base branch '$base_ref' does not exist" >&2
    exit 1
  fi

  # Check if worktree already exists
  if [[ -d "$WORKTREE_DIR/$branch" ]]; then
    echo "Error: worktree '$branch' already exists at '$WORKTREE_DIR/$branch'" >&2
    exit 1
  fi

  # Abort if branch already has a worktree elsewhere
  if git worktree list --porcelain | grep -q "worktree $branch$"; then
    echo "Error: branch '$branch' already has a worktree" >&2
    exit 1
  fi

  echo "Creating worktree for branch '$branch' from '$base_ref'..."

  # Create worktrees directory
  mkdir -p "$WORKTREE_DIR"

  # Ensure .gitignore has worktrees entry
  ensure_gitignore

  # Create the worktree
  git worktree add -b "$branch" "$WORKTREE_DIR/$branch" "$base_ref"
  WORKTREE_CREATED=1
  BRANCH_NAME="$branch"

  echo "Worktree created at '$WORKTREE_DIR/$branch'"

  # Load config
  local config_result
  config_result=$(load_config "$custom_config")
  local copyFiles symlinkDirs exclude
  copyFiles=$(echo "$config_result" | sed -n '1p')
  symlinkDirs=$(echo "$config_result" | sed -n '2p')
  exclude=$(echo "$config_result" | sed -n '3p')

  # Copy sensitive files
  copy_sensitive_files "$WORKTREE_DIR/$branch" "$copyFiles" "$exclude"

  # Symlink node_modules
  symlink_node_modules "$WORKTREE_DIR/$branch" "$symlinkDirs" "$exclude"

  # Trust dev tools
  trust_dev_tools "$GIT_ROOT" "$WORKTREE_DIR/$branch"

  echo "Done! Worktree ready at '$WORKTREE_DIR/$branch'"
}

ensure_gitignore() {
  local gitignore="$GIT_ROOT/.gitignore"
  local needs_add=false

  # Check if .gitignore exists
  if [[ ! -f "$gitignore" ]]; then
    touch "$gitignore"
    needs_add=true
  fi

  # Check if .worktrees is gitignored
  if ! git check-ignore -q "$WORKTREE_DIR" 2>/dev/null; then
    echo ".worktrees/" >> "$gitignore"
    needs_add=true
  fi

  if [[ "$needs_add" == "true" ]] && git rev-parse -q --git-dir &>/dev/null; then
    # Stage .gitignore if tracked
    if git ls-files --error-unmatch "$gitignore" &>/dev/null 2>&1; then
      git add "$gitignore" 2>/dev/null || true
    fi
  fi
}

copy_sensitive_files() {
  local worktree_path="$1"
  local copyFiles="$2"
  local exclude="$3"

  echo "Copying sensitive files..."

  # Convert exclude to array for checking
  local exclude_arr
  read -ra exclude_arr <<< "$exclude"

  # Copy files matching patterns
  for pattern in $copyFiles; do
    # Handle glob patterns
    if [[ "$pattern" == *\** ]]; then
      while IFS= read -r -d '' file; do
        [[ -z "$file" ]] && continue

        # Check if in excluded directory
        local should_exclude=false
        for ex in "${exclude_arr[@]}"; do
          if [[ "$file" == *"/$ex"* ]] || [[ "$file" == "$ex" ]]; then
            should_exclude=true
            break
          fi
        done

        if [[ "$should_exclude" == "false" ]]; then
          local relpath="${file#$GIT_ROOT/}"
          local dest="$worktree_path/$relpath"

          # Create parent directory
          mkdir -p "$(dirname "$dest")"

          # Backup existing file
          if [[ -f "$dest" ]]; then
            cp "$dest" "$dest.bak"
          fi

          # Copy the file
          cp "$file" "$dest"
          echo "  Copied: $relpath"
        fi
      done < <(find "$GIT_ROOT" -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    else
      # Literal filename
      local file="$GIT_ROOT/$pattern"
      if [[ -f "$file" ]]; then
        local relpath="${file#$GIT_ROOT/}"
        local dest="$worktree_path/$relpath"

        mkdir -p "$(dirname "$dest")"

        if [[ -f "$dest" ]]; then
          cp "$dest" "$dest.bak"
        fi

        cp "$file" "$dest"
        echo "  Copied: $relpath"
      fi
    fi
  done
}

symlink_node_modules() {
  local worktree_path="$1"
  local symlinkDirs="$2"
  local exclude="$3"

  echo "Setting up symlinked directories..."

  local exclude_arr
  read -ra exclude_arr <<< "$exclude"

  for dirname in $symlinkDirs; do
    local source="$GIT_ROOT/$dirname"
    local target="$worktree_path/$dirname"

    # Check if source exists
    if [[ ! -d "$source" ]]; then
      echo "  Skipping $dirname (not in source)"
      continue
    fi

    # Remove existing directory if present
    if [[ -e "$target" ]]; then
      rm -rf "$target"
    fi

    # Create relative symlink
    local relpath
    relpath=$(realpath --relative-to="$(dirname "$target")" "$source")
    ln -s "$relpath" "$target"
    echo "  Symlinked: $dirname"
  done
}

trust_dev_tools() {
  local source_root="$1"
  local worktree_path="$2"

  # Trust Mise
  if [[ -f "$source_root/.mise.toml" ]]; then
    cp "$source_root/.mise.toml" "$worktree_path/.mise.toml" 2>/dev/null || true
  fi

  # Trust direnv
  if [[ -f "$source_root/.envrc" ]]; then
    cp "$source_root/.envrc" "$worktree_path/.envrc" 2>/dev/null || true

    # Add to trust list if direnv is available
    if command -v direnv &>/dev/null; then
      direnv allow "$worktree_path" 2>/dev/null || true
    fi
  fi

  # Trust .editorconfig
  if [[ -f "$source_root/.editorconfig" ]]; then
    cp "$source_root/.editorconfig" "$worktree_path/.editorconfig" 2>/dev/null || true
  fi
}

cmd_delete() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    echo "Error: branch name required" >&2
    exit 1
  fi

  local worktree_path="$WORKTREE_DIR/$branch"

  if [[ ! -d "$worktree_path" ]]; then
    echo "Error: worktree '$branch' does not exist at '$worktree_path'" >&2
    exit 1
  fi

  echo "Removing worktree for '$branch'..."
  git worktree remove --force "$worktree_path"
  echo "Done!"
}

cmd_merge() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    echo "Error: branch name required" >&2
    exit 1
  fi

  local worktree_path="$WORKTREE_DIR/$branch"

  if [[ ! -d "$worktree_path" ]]; then
    echo "Error: worktree '$branch' does not exist" >&2
    exit 1
  fi

  # Determine upstream branch
  local upstream
  upstream=$(git rev-parse --abbrev-ref "$branch@{upstream}" 2>/dev/null || echo "")

  if [[ -n "$upstream" ]]; then
    echo "Merging '$branch' into '$upstream'..."
    git checkout "$upstream"
    git merge "$branch"
  else
    echo "Warning: no upstream branch configured for '$branch'"
    echo "Manual merge required"
  fi

  # Remove worktree
  echo "Removing worktree for '$branch'..."
  git worktree remove --force "$worktree_path"
  echo "Done!"
}

# Main command routing
main() {
  local command="${1:-}"

  case "$command" in
    create)
      shift
      cmd_create "$@"
      ;;
    delete)
      shift
      cmd_delete "$@"
      ;;
    merge)
      shift
      cmd_merge "$@"
      ;;
    help|--help|-h)
      usage
      ;;
    "")
      usage
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"