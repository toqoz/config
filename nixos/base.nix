# System settings shared by every Linux host.
{ pkgs, ... }:
{
  # Deployment uses `nixos-rebuild --flake`, and interactive work needs the
  # modern CLI. NixOS leaves these experimental features off by default.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Root's flake evaluation shells out to git. The interactive git, with the
  # direnv wrapper, belongs to the Home Manager profile instead, so root never
  # runs a repository's `.envrc` through `git -C`.
  environment.systemPackages = [ pkgs.git ];

  # Shell-level direnv stays with the system because the Home Manager module
  # would need to own bash's rc file, which NixOS already generates.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
