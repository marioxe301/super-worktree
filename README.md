# super-worktree

Create isolated git worktrees for parallel feature work with monorepo-aware env file copying and node_modules symlinking.

## Quickstart

```bash
# Clone or navigate to your repo
cd my-project

# Create a feature branch worktree
bash scripts/worktree-manager.sh create feature/my-feature

# Work on your feature...
# Edit code, run tests, etc.

# When done, merge and cleanup
bash scripts/worktree-manager.sh merge feature/my-feature
```

## Installation

### Using npx skills add

```bash
npx skills add owner/super-worktree
```

> **Note**: This command is available when the skill is published to npm or installed in your skills directory.

### Manual installation

```bash
# Find your skills directory
ls ~/.config/opencode/skills/

# Or create it if needed
mkdir -p ~/.config/opencode/skills

# Copy this skill
cp -r /path/to/super-worktree ~/.config/opencode/skills/
```

## Requirements

- Git 2.5+ (with worktree support)
- Bash 4.0+
- `jq` - Optional, for JSON config parsing (Python 3 fallback available)
- `python3` - Optional, fallback JSON parser

## Features

### Automatic sensitive file copying

Automatically copies environment files and credentials to new worktrees:

- `.env`, `.env.*` - Environment files
- `.envrc` - direnv config
- `.local.*` - Local overrides
- `credentials.json`, `credentials.yml` - Credentials
- `auth.json`, `auth.yml` - Auth config

### node_modules symlinking

Saves disk space by symlinking dependencies instead of copying:

```bash
# Instead of 500MB per worktree
# Each worktree shares the same node_modules
```

### Configurable patterns

Override defaults with a `super-worktree.json` file:

```json
{
  "sync": {
    "copyFiles": [".env", ".env.local"],
    "symlinkDirs": ["node_modules", ".pnpm-store"],
    "exclude": ["dist", "build"]
  }
}
```

## Commands

| Command | Description |
|---------|-------------|
| `create <branch> [from-branch]` | Create new worktree |
| `create <branch> --config <file>` | Create with custom config |
| `delete <branch>` | Remove worktree |
| `merge <branch>` | Merge and cleanup |

## Examples

```bash
# Create from main
bash scripts/worktree-manager.sh create feature/new-login

# Create from develop
bash scripts/worktree-manager.sh create feature/payments develop

# Create from specific branch with custom config
bash scripts/worktree-manager.sh create hotfix/urgent --config .my-config.json

# Delete worktree
bash scripts/worktree-manager.sh delete feature/new-login

# Merge and cleanup
bash scripts/worktree-manager.sh merge feature/new-login
```

## Configuration Priority

Config is loaded in this order (later overrides earlier):

1. Built-in defaults
2. Global config: `~/.config/super-worktree/config.json`
3. Project config: `.super-worktree.json`
4. CLI `--config` flag (highest)

## License

MIT