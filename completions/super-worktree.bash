#!/usr/bin/env bash
# super-worktree bash completion
# Source from ~/.bashrc:  source /path/to/completions/super-worktree.bash

_super_worktree() {
  local cur prev cmds ws_subs
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmds="create delete merge sync list status prune workspace version help"
  ws_subs="init list create status sync delete merge prune"

  if [[ $COMP_CWORD -eq 1 ]]; then
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return 0
  fi

  if [[ "${COMP_WORDS[1]}" == "workspace" ]]; then
    if [[ $COMP_CWORD -eq 2 ]]; then
      # shellcheck disable=SC2207
      COMPREPLY=( $(compgen -W "$ws_subs" -- "$cur") )
      return 0
    fi
    case "${COMP_WORDS[2]}" in
      create)
        case "$prev" in
          --tool)        COMPREPLY=( $(compgen -W "claude opencode codex cursor cline windsurf aider" -- "$cur") ) ;;
          --config)      COMPREPLY=( $(compgen -f -- "$cur") ) ;;
          *)
            # shellcheck disable=SC2207
            COMPREPLY=( $(compgen -W "--projects --all --base --per-project-base --branch --branch-override --ticket --slug --tool --config --no-symlink-layer --print-cd --dry-run" -- "$cur") )
            ;;
        esac
        ;;
      list|status)
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "--json" -- "$cur") )
        ;;
      delete)
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "--force --force-all" -- "$cur") )
        ;;
      init)
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "--auto-discover --name --target --force" -- "$cur") )
        ;;
    esac
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    delete|merge|sync)
      local branches
      branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
      # shellcheck disable=SC2207
      COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
      ;;
    create)
      case "$prev" in
        --tool)    COMPREPLY=( $(compgen -W "claude opencode codex cursor cline windsurf aider" -- "$cur") ) ;;
        --config)  COMPREPLY=( $(compgen -f -- "$cur") ) ;;
        *)
          # shellcheck disable=SC2207
          COMPREPLY=( $(compgen -W "--config --tool --ticket --slug --from-pr --print-cd --dry-run --projects --all --base --branch --branch-override --per-project-base --no-symlink-layer" -- "$cur") )
          ;;
      esac
      ;;
    list|status)
      # shellcheck disable=SC2207
      COMPREPLY=( $(compgen -W "--json" -- "$cur") )
      ;;
  esac
}

complete -F _super_worktree worktree-manager.sh
complete -F _super_worktree super-worktree
