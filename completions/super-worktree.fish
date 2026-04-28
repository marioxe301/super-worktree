# super-worktree fish completion
# Install:  cp completions/super-worktree.fish ~/.config/fish/completions/

set -l prog worktree-manager.sh super-worktree

complete -c $prog -f

complete -c $prog -n __fish_use_subcommand -a create  -d 'create a new worktree'
complete -c $prog -n __fish_use_subcommand -a delete  -d 'remove a worktree'
complete -c $prog -n __fish_use_subcommand -a merge   -d 'merge branch and remove worktree'
complete -c $prog -n __fish_use_subcommand -a sync    -d 're-copy env and re-symlink'
complete -c $prog -n __fish_use_subcommand -a list    -d 'list worktrees'
complete -c $prog -n __fish_use_subcommand -a status  -d 'clean/dirty per worktree'
complete -c $prog -n __fish_use_subcommand -a prune   -d 'remove orphan metadata'
complete -c $prog -n __fish_use_subcommand -a version -d 'print version'
complete -c $prog -n __fish_use_subcommand -a help    -d 'show usage'

function __sw_branches
  git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
end

complete -c $prog -n '__fish_seen_subcommand_from delete merge sync' -a '(__sw_branches)'

complete -c $prog -n '__fish_seen_subcommand_from create' -l config   -r -d 'custom config JSON'
complete -c $prog -n '__fish_seen_subcommand_from create' -l tool     -xa 'claude opencode codex cursor cline windsurf aider'
complete -c $prog -n '__fish_seen_subcommand_from create' -l ide      -xa 'code cursor windsurf idea webstorm pycharm zed subl nvim vim'
complete -c $prog -n '__fish_seen_subcommand_from create' -l ticket   -d 'ticket id'
complete -c $prog -n '__fish_seen_subcommand_from create' -l slug     -d 'slug text'
complete -c $prog -n '__fish_seen_subcommand_from create' -l from-pr  -d 'PR number'
complete -c $prog -n '__fish_seen_subcommand_from create' -l no-spawn -d 'skip terminal spawn'
complete -c $prog -n '__fish_seen_subcommand_from create' -l print-cd -d 'print cd line'
complete -c $prog -n '__fish_seen_subcommand_from create' -l dry-run  -d 'no changes'

complete -c $prog -n '__fish_seen_subcommand_from list status' -l json -d 'JSON output'
