# super-worktree

![super-worktree](./super-worktree.png)

Create isolated git worktrees for parallel feature work. Auto-copies env files, symlinks `node_modules`, detects your AI tool, and spawns a detached terminal session that survives the calling shell.

Single repo or **multi-repo workspace** — one feature branch can span `api/`, `ui/`, `db/`, etc. simultaneously, with one AI session at a unified workspace root. See [docs/workspace.md](./docs/workspace.md).

## Contents

- [Installation](#installation)
- [Requirements](#requirements)
- [Features](#features)
  - [Sensitive file copying](#sensitive-file-copying)
  - [node_modules symlinking](#node_modules-symlinking)
  - [Detached terminal spawn](#detached-terminal-spawn)
  - [AI tool detection](#ai-tool-detection)
  - [IDE handoff](#ide-handoff)
  - [Lifecycle hooks](#lifecycle-hooks)
  - [Branch templating](#branch-templating)
  - [GitHub PR checkout](#github-pr-checkout)
  - [Glob negation + env interpolation](#glob-negation--env-interpolation)
  - [Local-only ignore](#local-only-ignore)
  - [Metadata tracking](#metadata-tracking)
- [Commands](#commands)
- [Create options](#create-options)
- [Environment overrides](#environment-overrides)
- [Examples](#examples)
- [Natural language usage](#natural-language-usage)
- [Shell completions](#shell-completions)
- [Configuration priority](#configuration-priority)
- [Workspace mode](./docs/workspace.md)
- [Tests](#tests)
- [License](#license)

## Installation

```bash
npx skills add marioxe301/super-worktree
```

Works with Claude Code, OpenCode, Codex, Cursor, Windsurf, Cline, Aider, and 40+ AI agents.

## Requirements

- Git 2.5+ (worktree support)
- Bash 4.0+
- `jq` (required for JSON config parsing)
- `gh` (optional, only for `--from-pr`)

## Features

### Sensitive file copying

Defaults: `.env`, `.env.*`, `.envrc`, `.local.*`, `*.secret`, `*.key`, `.secrets.*`, `credentials.{json,yml,env}`, `auth.{json,yml,env}`, `.dev.vars`, `.prod.vars`, `.staging.vars`. Recurses up to `copyDepth` (default 2) for monorepo workspaces. Negate via `!pattern`.

### node_modules symlinking

Saves disk space. Discovers nested workspace `node_modules` automatically.

### Detached terminal spawn

Opens a new terminal tab/session and auto-runs the detected AI tool. Spawned with `setsid nohup … & disown` so it survives the calling AI session exiting.

| Terminal | Platform | Priority |
|----------|----------|----------|
| cmux | all | 1 (when `$CMUX_WORKSPACE_ID` set) |
| tmux | all | 2 (new window inside session, detached session outside) |
| zellij | all | 3 (when `$ZELLIJ` set) |
| WezTerm | all | 4 |
| Kitty | Linux/macOS | 5 |
| Ghostty | macOS/Linux | 6 |
| Alacritty | all | 7 |
| GNOME Terminal | Linux | 8 |
| Konsole | Linux | 9 |
| Windows Terminal (WSL) | Windows | 10 |
| iTerm2 / Terminal.app | macOS | 11 |

Fallback: prints `cd … && <ai_tool>` instructions.

### AI tool detection

Precedence: `--tool` flag → `$SUPER_WORKTREE_TOOL` → parent process walk (skips shells, matches `claude`/`opencode`/`codex`/`cursor`/`cline`/`windsurf`/`aider`) → `opencode` fallback.

### IDE handoff

`--ide code|cursor|idea|webstorm|pycharm|zed|subl|nvim|vim` opens the IDE instead of an AI tool.

### Lifecycle hooks

Run shell commands at create/delete phases:

```json
{
  "version": 1,
  "hooks": {
    "preCreate":  "echo creating $BRANCH",
    "postCreate": "pnpm install --frozen-lockfile",
    "preDelete":  "echo cleaning $BRANCH",
    "postDelete": "echo done"
  }
}
```

Hooks receive `BRANCH`, `BASE`, `WORKTREE_PATH` env vars.

### Branch templating

```bash
bash scripts/worktree-manager.sh create --ticket TEST-1 --slug "test feature"
# → branch: test-1-test-feature
```

### GitHub PR checkout

```bash
bash scripts/worktree-manager.sh create --from-pr 123
```

### Glob negation + env interpolation

```json
{
  "sync": {
    "copyFiles": [".env", ".env.*", "!.env.example", "${HOME}/.aws/credentials"]
  }
}
```

Defaults already negate `.env.example`, `.env.sample`, `.env.template`.

### Local-only ignore

Adds `.worktrees/` to `.git/info/exclude` (not tracked `.gitignore`).

### Metadata tracking

Stored at `.worktrees/.metadata/<branch>.json`:

```json
{"baseBranch":"main","createdAt":"2026-04-28T20:59:18Z","aiTool":"claude"}
```

## Commands

| Command | Description |
|---------|-------------|
| `create <branch> [from-branch] [opts]` | Create new worktree |
| `delete <branch>` | Remove worktree |
| `merge <branch>` | Merge into upstream and remove |
| `sync <branch>` | Re-copy env + re-symlink for existing worktree |
| `list [--json]` | List worktrees with base/created/tool |
| `status [--json]` | Show clean/dirty per worktree |
| `prune` | Remove orphan metadata + `git worktree prune` |
| `workspace init` | Generate `super-worktree.workspace.json` from auto-discovery |
| `workspace list [--json]` | Show workspace projects + features |
| `workspace create <feature> [--projects a,b\|--all]` | Create coordinated worktrees across N projects |
| `workspace status <feature> [--json]` | Per-project clean/dirty |
| `workspace sync <feature>` | Re-pull env/symlinks across all projects |
| `workspace delete <feature> [--force\|--force-all]` | Remove worktrees + symlink hub + metadata |
| `workspace merge <feature>` | Merge each project's branch into upstream and clean up |
| `workspace prune` | Remove orphan workspace metadata |
| `version` | Print version |
| `help` | Show usage |

## Create options

| Flag | Effect |
|------|--------|
| `--config <file>` | Custom config JSON |
| `--tool <name>` | Force AI tool |
| `--ide <name>` | Open IDE instead of AI tool |
| `--ticket <id>` | Ticket id for branch templating |
| `--slug <text>` | Slug for branch templating |
| `--from-pr <num>` | Check out a GitHub PR (requires `gh`) |
| `--no-spawn` | Skip terminal spawn |
| `--print-cd` | Print `cd <path>` to stdout |
| `--dry-run` | Print intended actions; no changes |

## Environment overrides

| Var | Effect |
|-----|--------|
| `SUPER_WORKTREE_TOOL` | Override AI tool detection |
| `TRUST_DIRENV=1` | Auto-run `direnv allow` on copied `.envrc` |
| `NO_SPAWN=1` / `DRY_RUN=1` / `PRINT_CD=1` / `JSON_OUT=1` | Equivalent to flags |

## Examples

```bash
# Create from origin/HEAD
bash scripts/worktree-manager.sh create feature/login

# Create from develop with custom config
bash scripts/worktree-manager.sh create feature/payments develop --config .super-worktree.json

# Templated branch + force claude tool
bash scripts/worktree-manager.sh create --ticket TEST-1 --slug "test feature" --tool claude

# CI-friendly creation
bash scripts/worktree-manager.sh create hotfix --no-spawn

# Open in VS Code instead of AI tool
bash scripts/worktree-manager.sh create feature/ui --ide code

# Eval cd into new worktree
cd "$(bash scripts/worktree-manager.sh create feat --print-cd --no-spawn | tail -1 | sed 's|^cd ||')"

# Re-pull env after rotation
bash scripts/worktree-manager.sh sync feature/login

# Machine-readable list
bash scripts/worktree-manager.sh list --json | jq '.[].branch'
```

## Natural language usage

Invoke via natural language prompts to your AI agent:

**Create:**
- "Create a worktree for feature/login"
- "Set up a hotfix worktree from production"
- "Start work on TEST-1 with slug 'test feature'"

**Delete / sync:**
- "Delete the payments worktree"
- "Re-sync env files into the login worktree"

**With specific tools:**
- "Create a worktree and open it in cursor"
- "Open feature/ui in VS Code instead"

**Workspace (multi-repo):**
- "Initialize a workspace at this folder so I can work across api, ui, and db"
- "Spin up coordinated worktrees for feat/payments across api and ui"
- "Start TEST-42 with slug 'rate limiter' across all projects"
- "Create feat/checkout in api from main and ui from develop"
- "Show me which workspace projects are dirty for feat/payments"
- "Sync env files across every project in feat/payments after I rotated secrets"
- "Tear down feat/payments — force it even if any project is dirty"
- "Merge feat/payments into upstream in each project and clean up"
- "Open feat/payments in tabs mode so I get one terminal per repo"
- "Create feat/db-only just in db, skip the rest"

## Shell completions

```bash
# bash
echo 'source /path/to/super-worktree/completions/super-worktree.bash' >> ~/.bashrc

# zsh
cp completions/_super-worktree /usr/local/share/zsh/site-functions/

# fish
cp completions/super-worktree.fish ~/.config/fish/completions/
```

## Configuration priority

1. Built-in defaults
2. Global: `~/.config/super-worktree/config.json`
3. Project: `.super-worktree.json` or `super-worktree.json`
4. CLI `--config` (highest)

## Tests

```bash
bash tests/e2e_smoke.sh       # single-repo: create/list/status/delete/prune
bash tests/e2e_features.sh    # templating, negation, sync, --json
bash tests/e2e_workspace.sh   # multi-repo workspace: 17 cases incl. rollback, hub, sync
```

CI: `.github/workflows/ci.yml` runs shellcheck + all three e2e suites on push/PR.

## License

MIT
