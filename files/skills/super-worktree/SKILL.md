---
name: super-worktree
description: Create isolated git worktrees for parallel feature work with monorepo-aware env file copying and node_modules symlinking.
---

# super-worktree

A skill for managing isolated git worktrees for parallel feature development with monorepo-aware env file copying and node_modules symlinking.

## Worktree Creation Overview

Git worktrees let you work on multiple branches simultaneously in a single repository. This skill enhances worktrees with:

- **Sensitive file copying**: Automatically copies `.env`, credentials, and other sensitive files to new worktrees
- **node_modules symlinking**: Saves disk space by symlinking `node_modules` directories
- **Configurable patterns**: Define custom sync patterns per-project or globally
- **Dev tool trust**: Automatically trusts Mise/direnv baseline when symlinking

## Creating a worktree

```bash
bash scripts/worktree-manager.sh create <branch> [from-branch] [--config <file>]
```

**Parameters:**
- `<branch>` - Name of the new branch/worktree (required)
- `[from-branch]` - Base branch to create from (defaults to `origin/HEAD` or `main`)
- `--config <file>` - Path to custom config file (optional)

**Example:**
```bash
# Create feature branch from main
bash scripts/worktree-manager.sh create feature/new-login

# Create from develop branch with custom config
bash scripts/worktree-manager.sh create feature/payments --config .super-worktree.json

# Create from a specific commit
bash scripts/worktree-manager.sh create hotfix/urgent fix/abc123
```

## Deleting a worktree

```bash
bash scripts/worktree-manager.sh delete <branch>
```

Removes the worktree and optionally deletes the branch (use with caution).

**Example:**
```bash
bash scripts/worktree-manager.sh delete feature/new-login
```

## Cleaning up (merge)

```bash
bash scripts/worktree-manager.sh merge <branch>
```

Merges the branch into its upstream and then deletes the worktree. Use when feature is complete.

**Example:**
```bash
bash scripts/worktree-manager.sh merge feature/new-login
```

## Configuration

Create a `super-worktree.json` in your project root for custom patterns:

```json
{
  "sync": {
    "copyFiles": [
      ".env",
      ".env.*",
      ".envrc",
      ".local.*",
      "*.secret",
      "*.key",
      ".secrets.*",
      "credentials.json",
      "credentials.yml",
      "credentials.env",
      "auth.json",
      "auth.yml",
      "auth.env",
      ".dev.vars",
      ".prod.vars",
      ".staging.vars"
    ],
    "symlinkDirs": [
      "node_modules"
    ],
    "exclude": [
      "node_modules",
      ".git",
      "dist",
      "build",
      ".next",
      "out",
      "coverage",
      ".turbo",
      ".vercel",
      ".worktrees"
    ]
  }
}
```

### Config Priority

Configuration is loaded in this order (later overrides earlier):

1. **Built-in defaults** - Always available
2. **Global config** - `~/.config/super-worktree/config.json`
3. **Project config** - `.super-worktree.json` in repo root
4. **CLI flag** - `--config <file>` argument (highest priority)

### JSON Schema

A [JSON Schema](schemas/super-worktree.schema.json) is provided for config validation:

```json
{
  "$schema": "./schemas/super-worktree.schema.json",
  "sync": {
    "copyFiles": [".env", ".env.local"],
    "symlinkDirs": ["node_modules", ".pnpm-store"],
    "exclude": ["dist", "build"]
  }
}
```

## Default Patterns

The skill includes sensible defaults that cover most projects:

### copyFiles (copied to worktree)
- `.env`, `.env.*` - Environment files
- `.envrc` - direnv config
- `.local.*` - Local overrides
- `*.secret`, `*.key`, `.secrets.*` - Secret files
- `credentials.json`, `credentials.yml`, `credentials.env` - Credentials
- `auth.json`, `auth.yml`, `auth.env` - Auth config
- `.dev.vars`, `.prod.vars`, `.staging.vars` - Environment-specific vars

### symlinkDirs (symlinked to save space)
- `node_modules` - Node dependencies

### exclude (not copied or symlinked)
- `node_modules`, `.git`, `dist`, `build`, `.next`, `out`, `coverage`, `.turbo`, `.vercel`, `.worktrees`

## Auto-navigation

Automatically spawns terminals with OpenCode running in the new worktree after worktree creation.

### How it works

- **After create**: Opens new terminal in the worktree with OpenCode running
- **After delete**: Opens new terminal in the base branch (stored during creation)
- Base branch is stored in `.worktrees/.metadata/` for persistence across sessions

### Supported Terminals

Terminals are tried in priority order. The first available terminal is used:

| Terminal    | Platform   | Priority |
| ----------- | ---------- | -------- |
| cmux        | All        | 1 (if CMUX_WORKSPACE_ID set) |
| tmux        | All       | 2        |
| Warp        | macOS     | 3        |
| Kitty       | Linux/macOS | 4      |
| Ghostty     | macOS/Linux | 5      |
| Alacritty   | All       | 6        |
| WezTerm     | All       | 7        |
| GNOME Terminal | Linux  | 8        |
| iTerm2      | macOS     | 9 (fallback) |

### Fallback

If no supported terminal is found, the script prints instructions to manually run:

```bash
cd <worktree> && opencode
```

## Natural Language Usage

You can invoke this skill using natural language prompts:

### Creating worktrees

**"Create a new worktree for feature/login from main"**
→ Creates worktree for `feature/login` branch based on `main`

**"Set up parallel development for the authentication branch"**
→ Creates worktree for `feature/authentication` from default base

**"I need to work on two features at once"**
→ Creates a new worktree so you can switch between branches

**"Start a hotfix worktree from production"**
→ Creates worktree for `hotfix/urgent` from production branch

**"Create a worktree using Claude"**
→ Creates worktree and spawns terminal with `claude` (auto-detected)

### Deleting worktrees

**"Delete the feature/login worktree"**
→ Removes worktree and returns to base branch

**"Clean up the payments worktree"**
→ Deletes worktree and navigates back to main

**"I'm done with the authentication branch, remove it"**
→ Deletes worktree and opens terminal in base branch

### Common workflows

**"Switch to a new feature branch without losing my current changes"**
→ Creates worktree so your current branch stays untouched

**"Work on the bugfix while keeping the main branch open"**
→ Creates isolated worktree for parallel development

**"Set up a worktree with my custom config"**
→ Creates worktree using `--config .super-worktree.json`

## Troubleshooting

### "worktree already exists"

The branch already has a worktree. Delete it first:

```bash
bash scripts/worktree-manager.sh delete <branch>
```

### "jq not found"

The script uses `jq` for JSON parsing. Install with:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# CentOS/RHEL
sudo yum install jq
```

### "python3 not found"

Fallback JSON parser requires Python 3. Ensure it's installed:

```bash
# Verify
python3 --version

# Install (macOS)
brew install python3

# Install (Ubuntu)
sudo apt install python3
```

### "cannot stat: No such file or directory"

The base branch or reference doesn't exist. Verify:

```bash
git branch -a
git log --oneline -5
```

### Permission denied

Make the script executable:

```bash
chmod +x scripts/worktree-manager.sh
```

### symlink fails with "File exists"

Remove existing `node_modules` in worktree first:

```bash
rm -rf .worktrees/<branch>/node_modules
bash scripts/worktree-manager.sh create <branch>
```

## Installation

### Using npx (recommended)

```bash
npx skills add owner/super-worktree
```

Note: This requires the skill to be published to npm or available in your skills directory.

### Manual installation

Copy the skill files to your skills directory:

```bash
# Find your skills directory
ls -la ~/.config/opencode/skills/

# Copy files
cp -r super-worktree ~/.config/opencode/skills/
```

### Verify installation

```bash
bash scripts/worktree-manager.sh help
```

## Requirements

- Git 2.5+ (worktree support)
- Bash 4.0+
- `jq` (optional, for JSON config; Python 3 fallback available)
- `python3` (optional, for JSON config fallback)