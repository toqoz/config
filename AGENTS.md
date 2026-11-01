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

You may be running inside a git worktree (or a fresh clone) created
outside this session — typically by the user via `git-wt`. Multiple
worktrees of this repo can exist on the host at the same time, each
with its own in-flight change.

Implications:

- The host machine is shared across worktrees. `nix run .#switch-<host>`
  changes the live system, so it must not run from a worktree —
  activation belongs on `main`, after merge, sequentially.
- Build artifacts and flake evaluation are worktree-local and safe to
  run in parallel. Use them as the pre-commit gate (next section).
- Treat the worktree as your sandbox: edit, build, test, commit. Leave
  `switch` to the user.

If you are about to start work and you are *not* in a worktree (i.e.
the primary checkout — `git rev-parse --git-dir` equals
`git rev-parse --git-common-dir`), pause and confirm with the user
before proceeding. Other worktrees may be in flight, and the user
typically intends to work from a `git-wt` worktree.

## Pre-commit Gate

Before committing from this workspace, verify the change:

- `nix run .#build-<host>` — builds the target nix-darwin configuration without activating (`remilis` or `forge01`).
- `nix flake check` — evaluates the flake.
- `node --test t/*.test.mts` — runs repo-level tests (plus any skill-local
  `*.test.ts` relevant to the change).

A green build + flake check is the bar for committing. Activation-only
failures that surface during `switch` are an accepted gap, caught
post-merge on `main`.

## Tests for Testable Code

For shell scripts under `scripts/` and skill `scripts/`, and any other
behavior that can be exercised in isolation, prefer adding tests over
relying on manual verification alone. Place repo-wide tests in `t/`
(`node --test t/*.test.mts`); co-locate skill-internal tests next to the
code they cover.
