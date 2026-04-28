#!/usr/bin/env bash
# sync.sh - copy sensitive files, symlink dirs, trust dev tools
# Sources util.sh + uses globals from config.sh: COPY_FILES, SYMLINK_DIRS, EXCLUDE, COPY_DEPTH

_is_excluded() {
  local path="$1"
  local rel="${path#"$GIT_ROOT"/}"
  for ex in "${EXCLUDE[@]}"; do
    case "/$rel/" in
      */"$ex"/*) return 0 ;;
    esac
  done
  return 1
}

_is_negated() {
  local rel="$1"
  local base
  base="$(basename "$rel")"
  for neg in "${COPY_NEGATE[@]}"; do
    [[ -z "$neg" ]] && continue
    # shellcheck disable=SC2053
    [[ "$base" == $neg || "$rel" == $neg ]] && return 0
  done
  return 1
}

copy_sensitive_files() {
  local worktree_path="$1"

  log "Copying sensitive files (depth=$COPY_DEPTH)..."

  local copied=0 secrets_seen=0
  for pattern in "${COPY_FILES[@]}"; do
    if [[ "$pattern" == /* ]]; then
      # Absolute path — copy directly into worktree at same name (basename in root).
      [[ -f "$pattern" ]] || continue
      local rel
      rel="$(basename "$pattern")"
      _is_negated "$rel" && continue
      local dest="$worktree_path/$rel"
      [[ -f "$dest" && ! -L "$dest" ]] && cp "$dest" "$dest.bak"
      cp "$pattern" "$dest"
      log "  copied (absolute): $pattern -> $rel"
      copied=$((copied+1))
      continue
    fi

    while IFS= read -r -d '' file; do
      [[ -z "$file" ]] && continue
      _is_excluded "$file" && continue

      local relpath="${file#"$GIT_ROOT"/}"
      _is_negated "$relpath" && continue

      local dest="$worktree_path/$relpath"

      mkdir -p "$(dirname "$dest")"

      if [[ -f "$dest" && ! -L "$dest" ]]; then
        cp "$dest" "$dest.bak"
      fi

      cp "$file" "$dest"
      log "  copied: $relpath"
      copied=$((copied+1))

      case "$relpath" in
        *.env*|*.envrc|*credentials*|*auth*|*secret*|*.key|*.pem)
          secrets_seen=$((secrets_seen+1)) ;;
      esac
    done < <(find "$GIT_ROOT" -maxdepth "$COPY_DEPTH" -name "$pattern" -type f -not -path '*/.git/*' -print0 2>/dev/null)
  done

  log "  $copied file(s) copied"
  if [[ "$secrets_seen" -gt 0 ]]; then
    warn "$secrets_seen secret-bearing file(s) propagated. Worktree contains plaintext credentials."
  fi
}

symlink_node_modules() {
  local worktree_path="$1"

  log "Setting up symlinked directories..."

  for dirname in "${SYMLINK_DIRS[@]}"; do
    while IFS= read -r -d '' source; do
      [[ -z "$source" ]] && continue
      _is_excluded "$(dirname "$source")" 2>/dev/null && continue

      local rel="${source#"$GIT_ROOT"/}"
      local target="$worktree_path/$rel"
      [[ -e "$target" || -L "$target" ]] && rm -rf "$target"
      mkdir -p "$(dirname "$target")"

      local rp
      rp=$(relpath "$(dirname "$target")" "$source")
      ln -s "$rp" "$target"
      log "  symlinked: $rel"
    done < <(find "$GIT_ROOT" -maxdepth "$COPY_DEPTH" -type d -name "$dirname" -not -path '*/.git/*' -not -path '*/.worktrees/*' -print0 2>/dev/null)
  done
}

trust_dev_tools() {
  local source_root="$1"
  local worktree_path="$2"

  for f in .mise.toml .editorconfig .nvmrc .tool-versions .python-version; do
    if [[ -f "$source_root/$f" ]]; then
      cp "$source_root/$f" "$worktree_path/$f" 2>/dev/null || true
    fi
  done

  if [[ -f "$source_root/.envrc" && -f "$worktree_path/.envrc" ]]; then
    if [[ "${TRUST_DIRENV:-0}" == "1" ]] && command -v direnv &>/dev/null; then
      direnv allow "$worktree_path" 2>/dev/null || true
    else
      log "  (.envrc copied — run 'direnv allow $worktree_path' to trust)"
    fi
  fi
}
