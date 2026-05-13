# config

- `darwin/`: `nix-darwin` modules
- `home/`: `home-manager` modules
- `packages/`: custom packages

## Nix Apps

- `nix run .#switch` - build and apply
- `nix run .#build` - build (dry-run)

## Cask Apps

`homebrew.onActivation.upgrade = true` runs `brew bundle --upgrade`, which
**skips casks that declare `auto_updates true`** — those apps update themselves
in the background, so `nix run .#switch` won't bump them. This is intentional.

If a `self`-updater cask falls behind (e.g. its built-in updater is broken or
gated), force an upgrade out-of-band:

```sh
brew upgrade --cask --greedy <name>
```

| Cask                  | Updater | Source                           |
| --------------------- | ------- | -------------------------------- |
| `1password`           | self    | `darwin/apps/1password.nix`      |
| `aqua-voice`          | self    | `darwin/apps/aqua-voice.nix`     |
| `chatgpt`             | self    | `darwin/apps/chatgpt.nix`        |
| `claude`              | self    | `darwin/apps/claude-desktop.nix` |
| `codex-app`           | self    | `darwin/apps/codex.nix`          |
| `figma`               | self    | `darwin/apps/figma.nix`          |
| `google-chrome`       | self    | `darwin/apps/chrome.nix`         |
| `karabiner-elements`  | self    | `darwin/apps/karabiner.nix`      |
| `macskk`              | brew    | `darwin/apps/macskk.nix`         |
| `nani`                | self    | `darwin/apps/nani.nix`           |
| `orbstack`            | self    | `darwin/apps/orbstack.nix`       |
| `paper-design`        | self    | `darwin/apps/paper-design.nix`   |
