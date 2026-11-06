---
name: computer-configuration
description: Guidelines for editing environment configuration files managed by the ToQoz/config nix repository. Use this skill whenever modifying shell (zsh), editor (neovim), terminal, Claude Code, Codex, or any other dotfile configuration — especially when the task involves ~/.config, ~/.claude, or similar home directory paths.
user-invocable: false
---

# Nix Dotfiles

All environment configuration is managed via Nix/Home Manager in `~/src/github.com/toqoz/config`. Refer to that repository's `AGENTS.md` (`CLAUDE.md` links to it) for the full structure and file mapping.

## Rules

- **Never edit files directly** under `~/.config/nvim`, `~/.claude`, or other symlinked home directories. Those paths are Nix store outputs or symlinks — direct edits will be lost on the next build.
- **Only edit files in `~/src/github.com/toqoz/config`.**
- **For agent skills**, read and edit the canonical source under `home/agents/skills/` — treat installed skill directories as generated projections.
- **If the target config is not tracked in this repository**, ask the user what to do rather than editing in-place.

## Workspace, Verification, and Activation

Work in the existing checkout by default; config changes do not require a
worktree or a confirmation step for the primary checkout. Inspect the working
tree before editing and preserve unrelated changes.

Run verification directly through the agent's command tool. No tmux pane,
terminal split, or user-started build is required:

- `nix run .#build-<host>` builds the target configuration without activating it.
- `nix flake check` checks the flake.
- Follow the repository's `AGENTS.md` for required tests and pre-commit checks.

Use the affected host (`remilis` or `forge01`); verify both when a change affects
shared configuration. Read command output and resolve failures before reporting
successful verification.

Activation is separate from verification. Leave `nix run .#switch-<host>` to the
user and include the appropriate command when activation is needed. It changes
the live machine and should run from `main` after committing or merging changes.

## Untracked New Files and Flake Builds

Nix flake reads only files tracked by git. A new file (e.g. under `packages/`, `home/`, `scripts/`) that is still untracked causes the build to fail with:

```
error: Path '<file>' in the repository "..." is not tracked by Git
```

Before retrying the build, register the file with `git add -N` (intent-to-add) — **not** bare `git add`:

```bash
git -C <repo> add -N <new-file>
```

This makes the file visible to flake without staging its content. `git diff --staged` stays clean, so concurrent `commit-work` / `commit` flows continue to ignore the file and won't accidentally bundle it into an unrelated commit. When the file is ready, commit it explicitly via the appropriate skill; if you abandon it, run `git restore --staged <new-file>` to drop the intent-to-add entry.
