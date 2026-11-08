# config

macOS configuration managed with Nix, nix-darwin, and Home Manager.
Both hosts share `home/base.nix`; host entry points select their additional tools and apps.

| Host | Account | Profile |
| ---- | ------- | ------- |
| remilis | toqoz | Development and desktop |
| forge01 | agent | Development subset |

## Set up

On the target Apple Silicon Mac, install any missing prerequisites:

1. Install Xcode Command Line Tools and wait for installation to finish.

   ```sh
	xcode-select --install
   ```

2. Install [Homebrew](https://brew.sh/) into `/opt/homebrew`.

   ```sh
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

3. Install Nix with the [NixOS community installer](https://github.com/NixOS/nix-installer).

   ```sh
	curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install --enable-flakes
   ```

   Open a new terminal before continuing.

Keep the installer's `!include nix.custom.conf` directive in `/etc/nix/nix.conf`.

Clone only if this checkout does not already exist. Keep it at this path because some tool configurations link into it.

```sh
	mkdir -p "$HOME/src/github.com/ToQoz"
	git clone https://github.com/toqoz/config.git "$HOME/src/github.com/ToQoz/config"
	cd "$HOME/src/github.com/ToQoz/config"
```

Back up existing Git, shell, Codex, and skill configuration before the first activation.
Activation synchronizes skill directories and replaces Codex settings while preserving its `projects` table.
**Homebrew activation uninstalls formulae and casks not selected by this host.**

Run the command for this Mac from the integrated `main` checkout, not a worktree:

| Host | Build without activation | Build and apply |
| ---- | ------------------------ | --------------- |
| remilis | `nix run .#build-remilis` | `nix run .#switch-remilis` |
| forge01 | `nix run .#build-forge01` | `nix run .#switch-forge01` |

After the first activation, run `asdf install` to install the configured runtimes.
Log into services separately on each Mac. Do not copy tokens, SSH private keys, or Keychain data.

## Update

From the checkout on the target Mac, run `git pull --ff-only`, then the same `switch-<host>` command.
Push integrated changes before updating another Mac. Its checkout must be on `main` with no local changes.

For forge01 over SSH:

```sh
	ssh -t agent@forge01 'cd ~/src/github.com/ToQoz/config && git pull --ff-only && nix run .#switch-forge01'
```

The command runs on forge01. `-t` allows the remote sudo password prompt.
Use an IP address or SSH alias if `forge01` does not resolve.

## Package updates

### Update workflow

| Upstream type | Where to update | Action |
| ------------- | --------------- | ------ |
| Nix packages and modules | `flake.lock` | Run `nix flake update`, or `nix flake update <input>` for one upstream. |
| External skills | `flake.lock` | Update the skill inputs selected in [flake.nix](flake.nix). Switch deploys the selected revisions. |
| Locally packaged releases | Definitions below | Update versions or revisions and fetch hashes together. |
| Pi extensions | [home/pi/default.nix](home/pi/default.nix) | Bump the npm pins. Switch installs the selected versions. |
| asdf runtimes | [home/asdf/.tool-versions](home/asdf/.tool-versions) | Change the pins here, then run `asdf install` on each host. |
| Homebrew formulae and casks | Homebrew metadata | Switch upgrades Brew-managed packages. App-managed updates are listed below. |

### Upstream sources

The input names below work with `nix flake update <input>`.
Updating `flake.lock` does not update local package pins.

| Nix input | Upstream |
| --------- | -------- |
| `nixpkgs` | [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs), `nixpkgs-unstable` |
| `home-manager` | [nix-community/home-manager](https://github.com/nix-community/home-manager) |
| `nix-darwin` | [nix-darwin/nix-darwin](https://github.com/nix-darwin/nix-darwin) |
| `llm-agents` | [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix) |
| `agent-skills` | [Kyure-A/agent-skills-nix](https://github.com/Kyure-A/agent-skills-nix), skill deployment module |
| `gws` | [googleworkspace/cli](https://github.com/googleworkspace/cli) |
| `herdr` | [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr) |
| `hunk` | [modem-dev/hunk](https://github.com/modem-dev/hunk) |
| `android-nixpkgs` | [tadfisher/android-nixpkgs](https://github.com/tadfisher/android-nixpkgs), `stable` |

| Skill source | Upstream | Pin location |
| ------------ | -------- | ------------ |
| Local | [home/agents/skills](home/agents/skills) | This checkout |
| T3 pstack | [toqoz/t3-pstack](https://github.com/toqoz/t3-pstack) | `flake.lock`: `t3-pstack` |
| Anthropic | [anthropics/skills](https://github.com/anthropics/skills) | `flake.lock`: `anthropic-skills` |
| agent-browser | [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser) | `flake.lock`: `vercel-agent-browser` |
| Notion | [makenotion/skills](https://github.com/makenotion/skills) | `flake.lock`: `makenotion-skills` |
| ketch | [1broseidon/ketch](https://github.com/1broseidon/ketch) | [packages/ketch.nix](packages/ketch.nix) |
| modern-web-guidance | [GoogleChrome/modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance), distributed through npm | [packages/modern-web-guidance.nix](packages/modern-web-guidance.nix) |

Skill selection and local adaptations live in
[home/agents/agent-skills](home/agents/agent-skills).

For changes in this repository, build each affected host, run `nix flake check`
and `node --test t/*.test.mts`, then commit. Apply committed changes from `main`
with `switch-<host>` on each Mac.

Some updates require work outside this repository:

- Personal upstreams: update and publish `toqoz/t3-pstack` or merge changes into the `toqoz/deepseek-harness` fork first, then advance the corresponding lock or revision here.
- Self-updating apps and App Store apps: update on each Mac through the app or store. A Nix lock update does not select their versions.
- macOS and Xcode Command Line Tools: update through Apple's system tools on each Mac.
- Project dependencies and project-specific runtimes: update their owning repositories and lockfiles.

### Local Nix packages

Update pins in the linked definitions, then build, check, and switch.
Unless noted below, these packages have no configured app self-update path.

| Package | Definition |
| ------- | ---------- |
| Kanary | [Package](packages/kanary.nix) |
| ketch | [Package](packages/ketch.nix) |
| modern-web-guidance | [Package](packages/modern-web-guidance.nix) |
| ntn | [Package](packages/ntn.nix) |
| jrf, oj | [Package](packages/jrf.nix) |
| vite-plus | [Package](packages/vite-plus.nix) |
| deepseek-harness, dedicated Node and pnpm | [Module](home/deepseek-harness/default.nix) |
| tailscale-serve | [Wrapper](packages/tailscale-serve.nix) |

- Kanary: automatic checks and installation are disabled in [app settings](darwin/apps/kanary.nix). Restart the app after switching.
- vite-plus: `VP_NO_UPDATE_CHECK=1` disables update checks and notices. The wrapper installs the pinned backend on first use and restores it if the active version changes. Manual `vp upgrade` can still change the version until the next wrapper invocation.

### Homebrew

[Switch](darwin/homebrew.nix) refreshes Brew metadata and upgrades packages.
Casks with `auto_updates true` use their app updater and are skipped by Brew.

| Update path | Packages |
| ----------- | -------- |
| Brew on switch | `portless` (formula), `capcut`, `macskk` |
| App self-update | `1password`, `aqua-voice`, `chatgpt`, `claude`, `figma`, `google-chrome`, `grok-bot`, `karabiner-elements`, `lark`, `linear`, `notion-calendar`, `orbstack`, `paper-design`, `stablyai/orca/orca`, `tailscale-app`, `zed` |
| App Store; also Brew on switch | `1Password for Safari` |

Cask policies checked on 2026-11-08. Definitions live in `darwin/apps/`.
To force an update when an app updater falls behind:

```sh
	brew upgrade --cask --greedy <name>
```
