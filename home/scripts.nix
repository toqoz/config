{ config, ... }:
{
  # Expose this repo's `scripts/` directory on PATH via a stable
  # `~/.local/share/home-scripts/bin` link managed by Home Manager.
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/share/home-scripts/bin"
  ];
  home.file.".local/share/home-scripts/bin".source = ./scripts;
}
