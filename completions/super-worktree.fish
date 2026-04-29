# super-worktree fish completion
# Install:  cp completions/super-worktree.fish ~/.config/fish/completions/

set -l prog worktree-manager.sh super-worktree

complete -c $prog -f

complete -c $prog -n __fish_use_subcommand -a create    -d 'create a new worktree'
complete -c $prog -n __fish_use_subcommand -a delete    -d 'remove a worktree'
complete -c $prog -n __fish_use_subcommand -a merge     -d 'merge branch and remove worktree'
complete -c $prog -n __fish_use_subcommand -a sync      -d 're-copy env and re-symlink'
complete -c $prog -n __fish_use_subcommand -a list      -d 'list worktrees'
complete -c $prog -n __fish_use_subcommand -a status    -d 'clean/dirty per worktree'
complete -c $prog -n __fish_use_subcommand -a prune     -d 'remove orphan metadata'
complete -c $prog -n __fish_use_subcommand -a workspace -d 'multi-repo workspace commands'
complete -c $prog -n __fish_use_subcommand -a version   -d 'print version'
complete -c $prog -n __fish_use_subcommand -a help      -d 'show usage'

# workspace subcommands
function __sw_ws_no_sub
  set -l toks (commandline -opc)
  test (count $toks) -eq 2; and test "$toks[2]" = workspace
end
complete -c $prog -n __sw_ws_no_sub -a init    -d 'generate workspace config'
complete -c $prog -n __sw_ws_no_sub -a list    -d 'list projects + features'
complete -c $prog -n __sw_ws_no_sub -a create  -d 'create coordinated worktrees'
complete -c $prog -n __sw_ws_no_sub -a status  -d 'per-project clean/dirty'
complete -c $prog -n __sw_ws_no_sub -a sync    -d 're-pull env across projects'
complete -c $prog -n __sw_ws_no_sub -a delete  -d 'remove feature across projects'
complete -c $prog -n __sw_ws_no_sub -a merge   -d 'merge each project branch'
complete -c $prog -n __sw_ws_no_sub -a prune   -d 'remove orphan workspace metadata'

function __sw_ws_create
  set -l toks (commandline -opc)
  test (count $toks) -ge 3; and test "$toks[2]" = workspace; and test "$toks[3]" = create
end
complete -c $prog -n __sw_ws_create -l projects          -d 'csv project aliases'
complete -c $prog -n __sw_ws_create -l all               -d 'all declared projects'
complete -c $prog -n __sw_ws_create -l base              -r -d 'base ref'
complete -c $prog -n __sw_ws_create -l per-project-base  -d 'alias=ref,...'
complete -c $prog -n __sw_ws_create -l branch            -r -d 'explicit branch'
complete -c $prog -n __sw_ws_create -l branch-override   -d 'alias=branch,...'
complete -c $prog -n __sw_ws_create -l ticket            -d 'ticket id'
complete -c $prog -n __sw_ws_create -l slug              -d 'slug text'
complete -c $prog -n __sw_ws_create -l tool              -xa 'claude opencode codex cursor cline windsurf aider'
complete -c $prog -n __sw_ws_create -l config            -r -d 'config JSON'
complete -c $prog -n __sw_ws_create -l no-symlink-layer  -d 'skip symlink hub'
complete -c $prog -n __sw_ws_create -l print-cd          -d 'print cd line'
complete -c $prog -n __sw_ws_create -l dry-run           -d 'no changes'

function __sw_ws_delete
  set -l toks (commandline -opc)
  test (count $toks) -ge 3; and test "$toks[2]" = workspace; and test "$toks[3]" = delete
end
complete -c $prog -n __sw_ws_delete -l force      -d 'delete despite dirty'
complete -c $prog -n __sw_ws_delete -l force-all  -d 'delete despite all dirty'

function __sw_ws_init
  set -l toks (commandline -opc)
  test (count $toks) -ge 3; and test "$toks[2]" = workspace; and test "$toks[3]" = init
end
complete -c $prog -n __sw_ws_init -l auto-discover -d 'scan for git repos'
complete -c $prog -n __sw_ws_init -l name          -r -d 'workspace name'
complete -c $prog -n __sw_ws_init -l target        -r -d 'target dir'
complete -c $prog -n __sw_ws_init -l force         -d 'overwrite existing'

function __sw_ws_list_status
  set -l toks (commandline -opc)
  test (count $toks) -ge 3; and test "$toks[2]" = workspace
  and contains -- "$toks[3]" list status
end
complete -c $prog -n __sw_ws_list_status -l json -d 'JSON output'

function __sw_branches
  git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null
end

complete -c $prog -n '__fish_seen_subcommand_from delete merge sync' -a '(__sw_branches)'

complete -c $prog -n '__fish_seen_subcommand_from create' -l config   -r -d 'custom config JSON'
complete -c $prog -n '__fish_seen_subcommand_from create' -l tool     -xa 'claude opencode codex cursor cline windsurf aider'
complete -c $prog -n '__fish_seen_subcommand_from create' -l ticket   -d 'ticket id'
complete -c $prog -n '__fish_seen_subcommand_from create' -l slug     -d 'slug text'
complete -c $prog -n '__fish_seen_subcommand_from create' -l from-pr  -d 'PR number'
complete -c $prog -n '__fish_seen_subcommand_from create' -l print-cd -d 'print cd line'
complete -c $prog -n '__fish_seen_subcommand_from create' -l dry-run  -d 'no changes'

complete -c $prog -n '__fish_seen_subcommand_from list status' -l json -d 'JSON output'
