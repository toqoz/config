# ToQoz/config

This repo manages the machine environment with Nix, nix-darwin, and Home Manager.

## Editing Guide

Each tool's module owns its packages and settings. Host entry points select modules:

- `home/base.nix` — shared development profile for both hosts
- `home/home.nix` — remilis account and additional tools/desktop modules
- `home/forge01.nix` — forge01 account using the shared profile
- `darwin/configuration.nix` — remilis system and app selection
- `darwin/forge01.nix` — forge01 system and app selection
- `darwin/apps/<app>.nix` — GUI app installation, settings, and app registration
- `packages/` — custom Nix packages

Add shared tools through `home/base.nix`; keep host-specific additions in the host's import list or package module. Reuse tool modules rather than copying their settings between hosts.

| Change | Edit |
|---|---|
| zsh init, aliases, env vars, history | `home/zsh/default.nix` |
| git global config | `home/git.nix` |
| Neovim packages, LSPs, extra tools | `home/neovim/default.nix` |
| Shared CLI tools / remilis-only CLI tools | `home/base.nix` / `home/packages.nix` |
| Claude Code settings and permissions | `home/agents/claude-code/` |
| Shared MCP server definitions | `home/agents/mcp.nix`, imported only by remilis |
| Codex settings, instructions, rules | `home/agents/codex/` |
| Shared agent instructions | `home/agents/AGENTS.md` |
| Agent skills | `home/agents/skills/<skill-name>/SKILL.md` |

## Workspace Context

Work in the existing checkout by default. This repository does not
require a worktree or confirmation before working in the primary checkout.
Inspect the working tree first and preserve unrelated changes.

Run builds and checks directly through the agent's command tool; no tmux
session is required. `nix run .#build-<host>` builds without activating.
Leave `nix run .#switch-<host>` to the user: it changes the live machine
and should be run from `main` after changes are committed or merged.

## Pre-commit Gate

Before committing from this workspace, verify the change:

- `nix run .#build-<host>` — builds the target nix-darwin configuration without activating (`remilis` or `forge01`).
- `nix flake check` — evaluates the flake.
- `node --test t/*.test.mts` — runs repo-level tests (plus any skill-local
  `*.test.ts` relevant to the change).

A green build + flake check is the bar for committing. Activation-only
failures that surface during `switch` are an accepted gap, caught
after committing or merging on `main`.

## Tests for Testable Code

For shell scripts under `scripts/` and skill `scripts/`, and any other
behavior that can be exercised in isolation, prefer adding tests over
relying on manual verification alone. Place repo-wide tests in `t/`
(`node --test t/*.test.mts`); co-locate skill-internal tests next to the
code they cover.
