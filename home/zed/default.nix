{ config, ... }:
{
  # Zed itself is installed via homebrew cask (darwin/apps/zed.nix).
  # The nixpkgs build is ad-hoc re-signed, which causes the macOS keychain
  # to prompt for the login password on every launch.

  xdg.configFile."zed/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/zed/settings.json";

  xdg.configFile."zed/keymap.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/zed/keymap.json";
}
