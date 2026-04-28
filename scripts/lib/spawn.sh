#!/usr/bin/env bash
# spawn.sh - terminal spawn + AI tool detection for super-worktree
# Sources util.sh for log/warn/detach_run.

KNOWN_AI_TOOLS="opencode claude codex cline cursor windsurf aider"
SHELL_NAMES="bash zsh fish sh csh tcsh dash ksh mksh nu xonsh elvish pwsh powershell"

# detect_ai_tool [cli_override]
# Precedence: CLI flag > $SUPER_WORKTREE_TOOL > parent process walk > opencode fallback.
detect_ai_tool() {
  local cli_override="${1:-}"

  if [[ -n "$cli_override" ]]; then
    printf '%s' "$cli_override"; return 0
  fi
  if [[ -n "${SUPER_WORKTREE_TOOL:-}" ]]; then
    printf '%s' "$SUPER_WORKTREE_TOOL"; return 0
  fi

  local pid=$$
  local depth=0 max_depth=12
  while [[ $depth -lt $max_depth && $pid -gt 1 ]]; do
    local ppid="" comm=""
    if [[ -r /proc/$pid/status ]]; then
      ppid=$(awk '/^PPid:/{print $2}' /proc/$pid/status 2>/dev/null)
      [[ -n "$ppid" && "$ppid" -gt 1 ]] && comm=$(cat /proc/$ppid/comm 2>/dev/null)
    else
      local ps_output
      ps_output=$(ps -o ppid=,comm= -p "$pid" 2>/dev/null) || true
      if [[ -n "$ps_output" ]]; then
        ppid=$(awk '{print $1}' <<<"$ps_output")
        comm=$(awk '{print $2}' <<<"$ps_output")
      fi
    fi

    [[ -z "$ppid" || "$ppid" == "0" || "$ppid" == "1" ]] && break

    local norm="${comm#-}"
    local is_shell=false
    for s in $SHELL_NAMES; do
      [[ "$norm" == "$s" ]] && { is_shell=true; break; }
    done

    if [[ "$is_shell" == "false" && -n "$comm" ]]; then
      for tool in $KNOWN_AI_TOOLS; do
        if [[ "$norm" == "$tool" ]]; then
          printf '%s' "$tool"; return 0
        fi
      done
    fi

    pid=$ppid
    ((depth++))
  done

  warn "Could not detect AI tool, falling back to opencode"
  printf 'opencode'
}

# spawn_terminal <worktree_path> <branch_name> [ai_tool]
spawn_terminal() {
  local worktree_path="$1"
  local branch_name="$2"
  local cli_tool="${3:-}"

  if [[ "${NO_SPAWN:-0}" == "1" ]]; then
    log "(--no-spawn) skipping terminal launch"
    return 0
  fi

  local ai_tool launch_cmd
  ai_tool=$(detect_ai_tool "$cli_tool")
  launch_cmd="cd $(printf '%q' "$worktree_path") && exec ${ai_tool}"

  # 1. cmux workspace
  if [[ -n "${CMUX_WORKSPACE_ID:-}" ]] && command -v cmux &>/dev/null; then
    if cmux new-workspace "$branch_name" 2>/dev/null \
       && cmux send-surface "$launch_cmd" 2>/dev/null; then
      log "Spawned cmux workspace: $branch_name"; return 0
    fi
  fi

  # 2. tmux
  if command -v tmux &>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
      if tmux new-window -c "$worktree_path" -n "$branch_name" "$ai_tool" 2>/dev/null; then
        log "Spawned tmux window: $branch_name"; return 0
      fi
    else
      local sess="wt-$branch_name"
      if tmux new-session -d -s "$sess" -c "$worktree_path" "$ai_tool" 2>/dev/null; then
        log "Spawned tmux session: $sess"
        log "  Attach: tmux attach -t $sess"
        return 0
      fi
    fi
  fi

  # 3. zellij
  if command -v zellij &>/dev/null && [[ -n "${ZELLIJ:-}" ]]; then
    if zellij action new-tab --cwd "$worktree_path" --name "$branch_name" 2>/dev/null \
       && zellij action write-chars "$ai_tool" 2>/dev/null \
       && zellij action write 13 2>/dev/null; then
      log "Spawned zellij tab: $branch_name"; return 0
    fi
  fi

  # 4. WezTerm
  if command -v wezterm &>/dev/null; then
    if wezterm cli spawn --cwd "$worktree_path" -- bash -c "$launch_cmd" &>/dev/null; then
      log "Spawned wezterm tab"; return 0
    fi
    detach_run wezterm start --cwd "$worktree_path" -- bash -c "$launch_cmd"
    log "Spawned wezterm window"; return 0
  fi

  # 5. Kitty
  if command -v kitty &>/dev/null; then
    if kitty @ launch --type=tab --cwd="$worktree_path" bash -c "$launch_cmd" &>/dev/null; then
      log "Spawned kitty tab"; return 0
    fi
    detach_run kitty --directory "$worktree_path" bash -c "$launch_cmd"
    log "Spawned kitty window"; return 0
  fi

  # 6. Ghostty
  if command -v ghostty &>/dev/null; then
    detach_run ghostty -e bash -c "$launch_cmd"
    log "Spawned ghostty window"; return 0
  fi

  # 7. Alacritty
  if command -v alacritty &>/dev/null; then
    detach_run alacritty --working-directory "$worktree_path" -e bash -c "$launch_cmd"
    log "Spawned alacritty window"; return 0
  fi

  # 8. GNOME Terminal
  if command -v gnome-terminal &>/dev/null; then
    detach_run gnome-terminal --working-directory="$worktree_path" -- bash -c "$launch_cmd; exec bash"
    log "Spawned gnome-terminal"; return 0
  fi

  # 9. Konsole
  if command -v konsole &>/dev/null; then
    detach_run konsole --workdir "$worktree_path" -e bash -c "$launch_cmd"
    log "Spawned konsole"; return 0
  fi

  # 10. Windows Terminal (WSL)
  if command -v wt.exe &>/dev/null; then
    detach_run wt.exe new-tab -d "$worktree_path" bash -c "$launch_cmd"
    log "Spawned Windows Terminal tab"; return 0
  fi

  # 11. macOS — iTerm2 / Terminal.app
  if [[ "$(uname)" == "Darwin" ]] && command -v osascript &>/dev/null; then
    if osascript <<EOF &>/dev/null
tell application "iTerm"
  set newWindow to (create window with default profile)
  tell current session of newWindow
    write text "$launch_cmd"
  end tell
end tell
EOF
    then log "Spawned iTerm2 window"; return 0; fi

    if osascript -e "tell application \"Terminal\" to do script \"$launch_cmd\"" &>/dev/null; then
      log "Spawned Terminal.app window"; return 0
    fi
  fi

  log ""
  log "========================================"
  log "No supported terminal detected. Run manually:"
  log "  cd $worktree_path"
  log "  $ai_tool"
  log "========================================"
  return 0
}

# spawn_ide <worktree_path> <ide>
# ide ∈ {code, cursor, windsurf, idea, webstorm, pycharm, zed, subl, nvim, vim}
spawn_ide() {
  local worktree_path="$1"
  local ide="$2"

  if [[ "${NO_SPAWN:-0}" == "1" ]]; then
    log "(--no-spawn) skipping IDE launch"
    return 0
  fi

  if ! command -v "$ide" &>/dev/null; then
    warn "IDE '$ide' not in PATH"
    log "  cd $worktree_path && $ide ."
    return 0
  fi

  detach_run "$ide" "$worktree_path"
  log "Spawned IDE: $ide $worktree_path"
}
