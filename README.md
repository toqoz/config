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

## Cask apps

`homebrew.onActivation.upgrade = true` runs `brew bundle --upgrade`, which
**skips casks that declare `auto_updates true`**. Those apps update themselves,
so the switch commands do not upgrade them.

If a self-updater falls behind, force an upgrade:

```sh
	brew upgrade --cask --greedy <name>
```

| Cask | Updater | Source |
| ---- | ------- | ------ |
| `1password` | self | `darwin/apps/1password.nix` |
| `aqua-voice` | self | `darwin/apps/aqua-voice.nix` |
| `chatgpt` | self | `darwin/apps/chatgpt.nix` |
| `claude` | self | `darwin/apps/claude-desktop.nix` |
| `figma` | self | `darwin/apps/figma.nix` |
| `google-chrome` | self | `darwin/apps/chrome.nix` |
| `karabiner-elements` | self | `darwin/apps/karabiner.nix` |
| `macskk` | brew | `darwin/apps/macskk.nix` |
| `orbstack` | self | `darwin/apps/orbstack.nix` |
| `paper-design` | self | `darwin/apps/paper-design.nix` |
| `tailscale-app` | self | `darwin/apps/tailscale.nix` |
