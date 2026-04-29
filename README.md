# super-worktree

![super-worktree](./super-worktree.png)

Create isolated git worktrees for parallel feature work. Auto-copies env files, symlinks `node_modules`, then prints a copy-pasteable `cd` line. No terminal/IDE spawn — clean and reliable on every OS.

Single repo or **multi-repo workspace** — one feature branch can span `api/`, `ui/`, `db/`, etc. simultaneously. See [docs/workspace.md](./docs/workspace.md).

## Contents

- [Installation](#installation)
- [Requirements](#requirements)
- [Features](#features)
  - [Sensitive file copying](#sensitive-file-copying)
  - [node_modules symlinking](#node_modules-symlinking)
  - [Cd hint output](#cd-hint-output)
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
  - [Single-repo](#single-repo)
  - [Workspace (multi-repo)](#workspace-multi-repo)
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

### Cd hint output

After `create`, prints a bordered block with a copy-pasteable `cd` command. Pass `--tool <name>` to append ` && <name>` to the line so you can launch your AI tool in one paste.

```
========================================
Worktree ready: /repo/.worktrees/feat-x
  cd /repo/.worktrees/feat-x && claude
========================================
```

`--print-cd` switches to a single machine-friendly `cd %q` line on stdout (no border) for `eval`-style integration.

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
| `--tool <name>` | AI tool name appended to printed `cd` hint (e.g. `claude`) |
| `--ticket <id>` | Ticket id for branch templating |
| `--slug <text>` | Slug for branch templating |
| `--from-pr <num>` | Check out a GitHub PR (requires `gh`) |
| `--print-cd` | Print `cd <path>` to stdout (machine-friendly, single line) |
| `--dry-run` | Print intended actions; no changes |

## Environment overrides

| Var | Effect |
|-----|--------|
| `TRUST_DIRENV=1` | Auto-run `direnv allow` on copied `.envrc` |
| `DRY_RUN=1` / `PRINT_CD=1` / `JSON_OUT=1` | Equivalent to flags |

## Examples

### Single-repo

```bash
# Create from origin/HEAD
bash scripts/worktree-manager.sh create feature/login

# Create from develop with custom config
bash scripts/worktree-manager.sh create feature/payments develop --config .super-worktree.json

# Templated branch + claude in printed cd hint
bash scripts/worktree-manager.sh create --ticket TEST-1 --slug "test feature" --tool claude

# Eval cd into new worktree
eval "$(bash scripts/worktree-manager.sh create feat --print-cd)"

# Re-pull env after rotation
bash scripts/worktree-manager.sh sync feature/login

# Machine-readable list
bash scripts/worktree-manager.sh list --json | jq '.[].branch'
```

### Workspace (multi-repo)

```bash
# Auto-discover sibling git repos at parent folder, write workspace config
cd ~/work/myapp
bash scripts/worktree-manager.sh workspace init --name myapp

# Coordinated worktrees across api + ui (defaultProjects from config)
bash scripts/worktree-manager.sh workspace create feat/payments

# Force every declared project, even if defaultProjects narrows the set
bash scripts/worktree-manager.sh workspace create feat/release --all

# Pick subset explicitly
bash scripts/worktree-manager.sh workspace create feat/db-only --projects db

# Mixed bases: api from develop, ui from main
bash scripts/worktree-manager.sh workspace create feat/x --projects api,ui \
  --per-project-base api=develop,ui=main

# Different branch name per project (align with existing CI branches)
bash scripts/worktree-manager.sh workspace create feat/checkout \
  --projects api,ui --branch-override api=feat/checkout-api,ui=feat/checkout-ui

# Templated workspace branch
bash scripts/worktree-manager.sh workspace create --ticket TEST-42 --slug "rate limiter" --all

# Bare 'create' at workspace root auto-routes to workspace create
bash scripts/worktree-manager.sh create feat/payments --projects api,ui

# Per-project clean/dirty across the feature
bash scripts/worktree-manager.sh workspace status feat/payments
bash scripts/worktree-manager.sh workspace status feat/payments --json | jq '.[] | select(.dirty>0) | .alias'

# Re-pull env across every project after rotating secrets
bash scripts/worktree-manager.sh workspace sync feat/payments

# Tear down (refuses if any project is dirty unless --force)
bash scripts/worktree-manager.sh workspace delete feat/payments
bash scripts/worktree-manager.sh workspace delete feat/payments --force

# Merge each project's branch into its upstream and clean up
bash scripts/worktree-manager.sh workspace merge feat/payments

# Workspace overview
bash scripts/worktree-manager.sh workspace list
bash scripts/worktree-manager.sh workspace list --json | jq '.features[].feature'

# Drop orphan workspace metadata after manual git surgery
bash scripts/worktree-manager.sh workspace prune
```

## Natural language usage

The skill auto-triggers when your AI agent sees prompts about parallel branches, worktrees, multi-repo features, or env-file syncing. You don't need to remember flag names — describe the intent.

### Trigger phrasing

Any of these patterns will route the agent into super-worktree:

- "create / spin up / set up / start a worktree for X"
- "work on X in parallel without touching my current branch"
- "I need to work on api and ui at the same time for feature X"
- "coordinate a feature branch across multiple repos"
- "delete / merge / sync / list worktrees"
- "show me dirty worktrees / which projects have changes"
- "tear down feature X across all projects"
- "init a workspace here / scan this folder for repos"

### Single-repo

**Create:**
- "Create a worktree for feature/login"
- "Set up a hotfix worktree from production"
- "Start work on TEST-1 with slug 'test feature'"
- "Spin up a worktree for the PR I'm reviewing — gh PR 1234"
- "I want to try a refactor in parallel without leaving this branch"

**Delete / sync / list:**
- "Delete the payments worktree"
- "Re-sync env files into the login worktree"
- "List my worktrees / show me which ones are dirty"
- "Merge feature/login back into main and clean up the worktree"

**With specific AI tool in cd hint:**
- "Create a worktree and append `claude` to the cd hint"
- "Set up feat/x with `--tool codex`"

### Workspace (multi-repo)

**Init / discovery:**
- "Initialize a workspace at this folder so I can work across api, ui, and db"
- "Scan this directory for git repos and set up a workspace"
- "I have api/, ui/, db/ as siblings — make this a workspace"

**Coordinated create:**
- "Spin up coordinated worktrees for feat/payments across api and ui"
- "Start work on feat/checkout in every project"
- "Start TEST-42 with slug 'rate limiter' across all projects"
- "Create feat/checkout in api from main and ui from develop"
- "I need to touch api and ui together for the new auth flow"
- "Create feat/db-only just in db, skip the rest"

**Status / sync / teardown:**
- "Which workspace projects are dirty for feat/payments?"
- "Show me status across all projects in feat/x"
- "Sync env files across every project in feat/payments after I rotated secrets"
- "Tear down feat/payments — force it even if any project is dirty"
- "Merge feat/payments into upstream in each project and clean up"
- "Prune any orphan workspace metadata"

**Routing examples (what the agent picks):**

| You say | Agent runs |
|---------|------------|
| "Start TEST-1 in api and ui" | `workspace create test-1 --projects api,ui` |
| "Same feature, but pick the base branch separately for ui" | `workspace create test-1 --projects api,ui --per-project-base ui=develop` |
| "Append claude to the cd hint" | adds `--tool claude` |
| "Force delete feat/x across everything" | `workspace delete feat/x --force-all` |
| "Dump status as JSON for my dashboard" | `workspace status feat/x --json` |

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
