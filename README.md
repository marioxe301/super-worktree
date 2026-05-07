# super-worktree

![super-worktree](./super-worktree.png)

Create isolated git worktrees for parallel feature work. Auto-copies env files, symlinks `node_modules`, then prints a copy-pasteable `cd` line. No terminal/IDE spawn — clean and reliable on every OS.

## Contents

- [Installation](#installation)
- [Requirements](#requirements)
- [Features](#features)
- [Commands](#commands)
- [Create options](#create-options)
- [Examples](#examples)
- [Natural language usage](#natural-language-usage)
- [Configuration](#configuration)
- [Shell completions](#shell-completions)
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
- `gh` (optional, for `--from-pr`)
- `glab` (optional, for `--from-mr`)

## Features

### Sensitive file copying

Defaults: `.env`, `.env.*`, `.envrc`, `.local.*`, `*.secret`, `*.key`, `.secrets.*`, `credentials.{json,yml,env}`, `auth.{json,yml,env}`, `.dev.vars`, `.prod.vars`, `.staging.vars`. Recurses up to `copyDepth` (default 2) for monorepo workspaces. Negate via `!pattern`.

### node_modules symlinking

Saves disk space. Discovers nested workspace `node_modules` automatically.

### Cd hint output

After `create`, prints a bordered block with a copy-pasteable `cd` command. Pass `--tool <name>` to append ` && <name>` to the line so you can launch your AI tool in one paste.

```
========================================
Worktree ready: /repo/.worktrees/feat-x
  cd /repo/.worktrees/feat-x && claude
========================================
```

`--print-cd` switches to a single machine-friendly `cd <path>` line on stdout (no border) for `eval`-style integration.

### Lifecycle hooks

Run shell commands at create/delete phases:

```json
{
  "version": 1,
  "hooks": {
    "preCreate":  "echo creating $BRANCH",
    "postCreate": "pnpm install --frozen-lockfile",
    "preDelete":  "echo cleaning $BRANCH"
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

### GitLab MR checkout

```bash
bash scripts/worktree-manager.sh create --from-mr 42
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
| `version` | Print version |

## Create options

| Flag | Effect |
|------|--------|
| `--config <file>` | Custom config JSON |
| `--tool <name>` | AI tool name appended to printed `cd` hint (e.g. `claude`) |
| `--ticket <id>` | Ticket id for branch templating |
| `--slug <text>` | Slug for branch templating |
| `--from-pr <num>` | Check out a GitHub PR (requires `gh`) |
| `--from-mr <num>` | Check out a GitLab MR (requires `glab`) |
| `--print-cd` | Print `cd <path>` to stdout (machine-friendly, single line) |
| `--dry-run` | Print intended actions; no changes |

## Environment overrides

| Var | Effect |
|-----|--------|
| `TRUST_DIRENV=1` | Auto-run `direnv allow` on copied `.envrc` |
| `DRY_RUN=1` / `PRINT_CD=1` / `JSON_OUT=1` | Equivalent to flags |

## Examples

```bash
# Create from origin/HEAD
bash scripts/worktree-manager.sh create feature/login

# Create from develop with custom config
bash scripts/worktree-manager.sh create feature/payments develop --config .super-worktree.json

# Templated branch + claude in printed cd hint
bash scripts/worktree-manager.sh create --ticket TEST-1 --slug "test feature" --tool claude

# Eval cd into new worktree
eval "$(bash scripts/worktree-manager.sh create feat/x --print-cd)"

# Check out a GitHub PR
bash scripts/worktree-manager.sh create --from-pr 123

# Check out a GitLab MR
bash scripts/worktree-manager.sh create --from-mr 42

# Re-pull env after rotation
bash scripts/worktree-manager.sh sync feature/login

# Machine-readable list
bash scripts/worktree-manager.sh list --json | jq '.[].branch'

# Delete
bash scripts/worktree-manager.sh delete feature/login

# Merge into upstream and remove
bash scripts/worktree-manager.sh merge feature/login

# Prune orphans
bash scripts/worktree-manager.sh prune
```

## Natural language usage

The skill auto-triggers when your AI agent sees prompts about parallel branches, worktrees, or env-file syncing.

### Trigger phrases

- "create / spin up / set up / start a worktree for X"
- "work on X in parallel without touching my current branch"
- "delete / merge / sync / list worktrees"
- "show me dirty worktrees / which projects have changes"
- "I want to try a refactor in parallel without leaving this branch"

### Examples

| You say | Agent runs |
|---------|------------|
| "Create a worktree for feature/login" | `create feature/login` |
| "Set up a hotfix worktree from production" | `create hotfix production` |
| "Start work on TEST-1 with slug 'test feature'" | `create --ticket TEST-1 --slug "test feature"` |
| "Spin up a worktree for PR 1234" | `create --from-pr 1234` |
| "Spin up a worktree for MR 42" | `create --from-mr 42` |
| "Delete the payments worktree" | `delete payments` |
| "List my worktrees / show me which ones are dirty" | `list` or `status` |
| "Merge feature/login back into main" | `merge feature/login` |
| "Re-sync env files into the login worktree" | `sync login` |

## Configuration

Create a `super-worktree.json` in your project root:

```json
{
  "$schema": "./schemas/super-worktree.schema.json",
  "version": 1,
  "sync": {
    "copyFiles": [".env", ".env.*", ".envrc", "credentials.json"],
    "symlinkDirs": ["node_modules"],
    "copyDepth": 2
  },
  "hooks": {
    "postCreate": "pnpm install --frozen-lockfile"
  }
}
```

### Config priority

1. Built-in defaults
2. Global: `~/.config/super-worktree/config.json`
3. Project: `.super-worktree.json` in repo root
4. CLI `--config <file>` (highest)

## Shell completions

```bash
# bash
echo 'source /path/to/super-worktree/completions/super-worktree.bash' >> ~/.bashrc

# zsh
cp completions/_super-worktree /usr/local/share/zsh/site-functions/

# fish
cp completions/super-worktree.fish ~/.config/fish/completions/
```

## Tests

```bash
bash tests/e2e_smoke.sh       # single-repo: create/list/status/delete/prune
bash tests/e2e_features.sh    # templating, negation, sync, --json
```

CI: `.github/workflows/ci.yml` runs shellcheck + both e2e suites on push/PR.

## License

MIT
