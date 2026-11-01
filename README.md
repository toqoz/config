# config

macOS configuration managed with Nix, nix-darwin, and Home Manager.
Both hosts share `home/base.nix`; host entry points select their additional tools and apps.

| Host | Account | Profile |
| ---- | ------- | ------- |
| remilis | toqoz | Development and desktop |
| forge01 | agent | Development subset |

## Set up

On the target Apple Silicon Mac, install Xcode command line tools, Homebrew at `/opt/homebrew`, and Nix.
The Nix installer must manage the daemon and `/etc/nix/nix.conf`, with `!include nix.custom.conf` enabled.
No separate nix-darwin installation is needed; the commands below provide the locked version.

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
| `codex-app` | self | `darwin/apps/codex.nix` |
| `figma` | self | `darwin/apps/figma.nix` |
| `google-chrome` | self | `darwin/apps/chrome.nix` |
| `karabiner-elements` | self | `darwin/apps/karabiner.nix` |
| `macskk` | brew | `darwin/apps/macskk.nix` |
| `nani` | self | `darwin/apps/nani.nix` |
| `orbstack` | self | `darwin/apps/orbstack.nix` |
| `paper-design` | self | `darwin/apps/paper-design.nix` |
