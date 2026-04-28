# super-worktree

![super-worktree](./super-worktree.png)

Create isolated git worktrees for parallel feature work with monorepo-aware env file copying and node_modules symlinking.

## Installation

Choose your platform below:

### OpenCode (recommended via OCX)

```bash
# Install via OCX registry (recommended)
ocx add marioxe301/super-worktree --from https://marioxe301.github.io/super-worktree

# Or clone and install manually
git clone https://github.com/marioxe301/super-worktree.git
cp -r super-worktree ~/.config/opencode/skills/
```

### Claude Code

```bash
# Using Claude marketplace (recommended)
/plugin install marioxe301/super-worktree

# Or using npx skills
npx skills add marioxe301/super-worktree -a claude-code
```

### Other AI Agents (Cursor, Codex, etc.)

```bash
# Using npx skills (recommended for all agents)
npx skills add marioxe301/super-worktree

# Install to specific agents
npx skills add marioxe301/super-worktree -a codex -a cursor -a windsurf

# Install globally to all supported agents
npx skills add marioxe301/super-worktree --all
```

### Manual Installation

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