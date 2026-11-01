{ ... }:
{
  imports = [
    ./app-registry.nix
    ./apps/1password.nix
    ./apps/chrome.nix
    ./apps/codex.nix
    ./apps/orbstack.nix
    ./apps/slack.nix
    ./apps/tailscale.nix
    ./homebrew.nix
    ./nix.nix
    ./unfree.nix
  ];

  networking = {
    hostName = "forge01";
    localHostName = "forge01";
    computerName = "forge01";
  };

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
  system.primaryUser = "agent";
}
