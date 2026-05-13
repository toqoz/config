{ ... }:
{
  imports = [
    ./aerospace.nix
    ./apps/1password.nix
    ./apps/aqua-voice.nix
    ./apps/chatgpt.nix
    ./apps/chrome.nix
    ./apps/claude-desktop.nix
    ./apps/codex.nix
    ./apps/figma.nix
    ./apps/karabiner.nix
    ./apps/macskk.nix
    ./apps/music.nix
    ./apps/nani.nix
    ./apps/orbstack.nix
    ./apps/paper-design.nix
    ./apps/safari.nix
    ./apps/slack.nix
    ./apps/system-preferences.nix
    ./apps/wezterm.nix
    ./fonts.nix
    ./homebrew.nix
    ./nix.nix
    ./system.nix
    ./unfree.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;

  # For homebrew
  system.primaryUser = "toqoz";

  system.startup.chime = false;
}
