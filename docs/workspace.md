# Workspace Mode

Workspace mode lets one feature span multiple sibling git repos (e.g. `api/`, `ui/`, `db/`, `workers/`) under a parent folder. Useful when an AI agent runs at the parent — touching `api` and `ui` together for one feature without having to leave the session.

Single-repo mode is unaffected. Workspace mode activates only when `super-worktree.workspace.json` is found at the cwd or any ancestor.

## Layout

```
~/work/myapp/                           # workspace root
├── super-worktree.workspace.json       # workspace declaration
├── .worktrees/
│   ├── .metadata/
│   │   └── feat__payments.json         # workspace-aggregate metadata
│   └── feat/payments/                  # symlink hub for one feature
│       ├── api -> ../../../api/.worktrees/feat/payments
│       └── ui  -> ../../../ui/.worktrees/feat/payments
├── api/                                # child git repo
│   └── .worktrees/feat/payments/       # real worktree lives here
├── ui/
│   └── .worktrees/feat/payments/
└── db/                                 # not selected; untouched
```

Real worktrees stay inside each project (so `git worktree add` works naturally). The hub at `<workspace>/.worktrees/<feature>/<alias>/` symlinks to each per-project worktree, giving the AI session one root with all selected projects as direct subdirectories.

## Quick start

```bash
# Auto-discover sibling git repos and write a workspace config
cd ~/work/myapp
bash scripts/worktree-manager.sh workspace init --name myapp

# Edit super-worktree.workspace.json: defaultProjects, hooks, etc.

# Create coordinated worktrees across api + ui
bash scripts/worktree-manager.sh workspace create feat/payments --projects api,ui

# Status across all selected projects
bash scripts/worktree-manager.sh workspace status feat/payments

# Re-pull env after rotation
bash scripts/worktree-manager.sh workspace sync feat/payments

# Tear down (refuses if dirty unless --force)
bash scripts/worktree-manager.sh workspace delete feat/payments
```

`bash scripts/worktree-manager.sh create feat/payments --projects api,ui` works the same way — bare `create` at workspace root auto-routes to `workspace create`.

## Configuration

`super-worktree.workspace.json` at the workspace root:

```json
{
  "$schema": "./schemas/super-worktree.workspace.schema.json",
  "version": 1,
  "workspace": {
    "name": "myapp",
    "projects": [
      { "alias": "api", "path": "./api", "defaultBase": "main" },
      { "alias": "ui",  "path": "./ui",  "defaultBase": "develop" },
      { "alias": "db",  "path": "./db",  "defaultBase": "main",
        "copyFiles": [".env", ".pgpass"] },
      { "alias": "workers", "path": "./workers" }
    ],
    "defaultProjects": ["api", "ui"],
    "branchTemplate": "feat/{ticket}-{slug}",
    "spawnMode": "single",
    "symlinkLayer": true,
    "rollback": "strict",
    "hooks": {
      "preCreateAll":  "echo starting $FEATURE",
      "postCreateAll": "echo all projects ready",
      "preDeleteAll":  "echo tearing down $FEATURE"
    }
  },
  "sync": {
    "copyFiles": [".env", ".env.*", "!.env.example"],
    "copyDepth": 2
  }
}
```

| Field | Effect |
|-------|--------|
| `workspace.projects[].alias` | Short id used in `--projects` and the symlink hub. Must match `^[a-z0-9][a-z0-9-]*$`. |
| `workspace.projects[].path` | Relative or absolute path to the project's git repo. |
| `workspace.projects[].defaultBase` | Base ref for worktree creation when not overridden. Defaults to `origin/HEAD` then `main`. |
| `workspace.projects[].{copyFiles,symlinkDirs,exclude,copyDepth,hooks}` | Per-project overrides; overlays workspace `sync` defaults. |
| `workspace.defaultProjects` | Aliases used when `--projects` is omitted. Empty/absent = all. |
| `workspace.branchTemplate` | Template for branch name. Supports `{ticket}`, `{slug}`, `{feature}`. |
| `workspace.spawnMode` | `single` (default) = one tab at hub; `tabs` = N tabs (one per project). |
| `workspace.symlinkLayer` | Default `true`. Set `false` for Windows without dev mode. |
| `workspace.rollback` | `strict` (default) = remove created siblings on failure; `leave` = keep partial state. |
| `workspace.hooks.preCreateAll` | Runs once before any worktree creation (cwd = workspace root). |
| `workspace.hooks.postCreateAll` | Runs once after all worktrees + hub + metadata. |
| `workspace.hooks.preDeleteAll` | Runs once before delete. |
| `workspace.hooks.postDeleteAll` | Runs once after delete. |

## CLI

| Command | Effect |
|---------|--------|
| `workspace init [--auto-discover] [--name <n>] [--target <dir>] [--force]` | Generate workspace config from depth-1 git repo scan. |
| `workspace list [--json]` | Print parsed projects and existing features. |
| `workspace create <feature> [opts]` | Create coordinated worktrees + symlink hub + metadata. |
| `workspace status <feature> [--json]` | Per-project clean/dirty. |
| `workspace sync <feature> [--config <file>]` | Re-pull env/symlinks across all projects in metadata. |
| `workspace delete <feature> [--force]` | Refuses dirty unless `--force`/`--force-all`. |
| `workspace merge <feature>` | For each project: merge into upstream, drop worktree. |
| `workspace prune` | Remove workspace metadata for features whose per-project worktrees are gone. |

### `workspace create` options

| Flag | Effect |
|------|--------|
| `--projects api,ui` | Aliases (csv). Default = `defaultProjects` from config, else all. |
| `--all` | Override defaults; create in every declared project. |
| `--base <ref>` | Workspace-wide base; per-project `defaultBase` wins where set. |
| `--per-project-base api=develop,ui=main` | Pin base per project (overrides `--base` and `defaultBase`). |
| `--branch <name>` | Explicit branch name (skips template). |
| `--branch-override api=feat/x-api,ui=feat/x-ui` | Per-project branch override (e.g. align with existing CI branch). |
| `--ticket <id>` / `--slug <text>` | Template-based branch naming. |
| `--tool <name>` | Force AI tool. Single detection at workspace level. |
| `--ide <name>` | Open IDE instead of AI tool. |
| `--config <file>` | Custom per-project sync overrides; overlays workspace base. |
| `--spawn-mode single\|tabs` | Override config; default `single`. |
| `--no-symlink-layer` | Skip the symlink hub (useful on Windows without dev mode). |
| `--no-spawn` / `--print-cd` / `--dry-run` | Same as single-mode. |

## Hooks

| Phase | Scope | cwd | Env |
|-------|-------|-----|-----|
| `workspace.hooks.preCreateAll` | Workspace | `WORKSPACE_ROOT` | `FEATURE`, `PROJECTS`, `WORKSPACE_ROOT`, `WORKTREE_ROOT_DIR` |
| `workspace.hooks.postCreateAll` | Workspace | `WORKSPACE_ROOT` | same |
| Per-project `hooks.preCreate` / `postCreate` | Project | per-project repo | `BRANCH`, `BASE`, `WORKTREE_PATH`, `PROJECT_ALIAS`, `WORKSPACE_ROOT` |
| `workspace.hooks.preDeleteAll` / `postDeleteAll` | Workspace | `WORKSPACE_ROOT` | `FEATURE`, `WORKSPACE_ROOT` |
| Per-project `hooks.preDelete` / `postDelete` | Project | per-project repo | `BRANCH`, `BASE`, `WORKTREE_PATH`, `PROJECT_ALIAS`, `WORKSPACE_ROOT` |

Order on create: `preCreateAll` → for each project (`preCreate` → `git worktree add` → sync → `postCreate`) → build hub → write metadata → `postCreateAll`.

A failing `preCreateAll` aborts before any worktree is created. A per-project failure mid-sequence triggers atomic rollback when `rollback: "strict"` (default).

## Spawn modes

- **single** (default) — one terminal tab at the hub `<workspace>/.worktrees/<feature>/`. AI tools see all selected projects as sibling subdirectories.
- **tabs** — one terminal tab per project, each cwd inside that project's real worktree. Pick this for tmux/zellij users who prefer one window per repo.

## Atomic rollback

When `rollback: "strict"` and a per-project step fails, super-worktree:
1. Removes the worktree for any project already created in this run.
2. Deletes the per-project branch.
3. Drops per-project metadata files.
4. Aborts before writing workspace metadata or building the hub.

`rollback: "leave"` keeps the partial state in place and writes workspace metadata anyway, so you can inspect/recover manually. Useful in CI debugging.

## Backward compatibility

- Single-repo commands (`create/delete/merge/sync/list/status/prune`) work unchanged when invoked inside a single git repo.
- Existing `super-worktree.json` files keep loading with the same schema.
- Per-project metadata at `<project>/.worktrees/.metadata/<branch>.json` keeps the same format (`baseBranch`, `createdAt`, `aiTool`).
- A single-repo command run at workspace root with no enclosing git repo errors with a hint to use `workspace ...`.
- The bare `create <feature> --projects ...` form auto-routes to `workspace create` only when the cwd is the workspace root.

## Edge cases

| Case | Handling |
|------|----------|
| Nested git / submodules | Auto-discovery treats only depth-1 entries with `.git/` as projects. Submodules within a project are left to git. |
| Bare repos as projects | Allowed; existing `_resolve_git_root` bare-repo logic applies per project. |
| Different default branches | Per-project `defaultBase`; falls back to `origin/HEAD` then `main`. |
| Project path missing | Error before any worktree creation. |
| Project not a git repo | Error with hint to `git init` or remove from `projects[]`. |
| Partial create failure | `strict` rollback removes siblings; `leave` keeps them. |
| Delete with one dirty project | Default refuses. `--force` / `--force-all` overrides. |
| Branch already exists in some projects | Pre-flight detects and aborts; use `--branch-override` to attach to existing names per project. |
| Workspace config edited mid-flight | Metadata captured at create time; delete/sync use the captured list. |
| Symlinks fail (Windows without dev mode) | Falls back to a `.path` text file pointer; AI tool needs to be opened per-project (`--spawn-mode tabs` recommended). |

## Files written by workspace mode

| Path | Owner | Purpose |
|------|-------|---------|
| `<workspace>/super-worktree.workspace.json` | user (init) | Workspace declaration. |
| `<workspace>/.worktrees/<feature>/<alias>` | super-worktree | Symlink to per-project worktree. |
| `<workspace>/.worktrees/.metadata/<feature>.json` | super-worktree | Aggregate workspace metadata (slashes encoded as `__`). |
| `<project>/.worktrees/<feature>/` | git | Real per-project worktree. |
| `<project>/.worktrees/.metadata/<branch>.json` | super-worktree | Per-project metadata (matches single-mode format). |
| `<project>/.git/info/exclude` | super-worktree | Appends `.worktrees/` once. |

## Migration

Existing single-repo users adopting workspace mode for the first time:

1. Move `api/`, `ui/`, etc. to siblings under one parent (or use them in place if already arranged that way).
2. `cd <parent>; bash scripts/worktree-manager.sh workspace init --name <n>`.
3. Edit the generated `super-worktree.workspace.json` to set `defaultProjects`, hooks, and `spawnMode`.
4. Existing per-project worktrees keep working — workspace mode is purely additive.
