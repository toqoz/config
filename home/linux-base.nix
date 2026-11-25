# Home Manager profile shared by every Linux host. It stays deliberately small:
# these hosts are small boards that evaluate this configuration on-device, so
# the darwin profile in ./base.nix (agents, GUI tools, heavy language runtimes)
# is not a baseline here.
{ pkgs, ... }:
{
  imports = [
    ./gh.nix
    ./git-identities.nix
    ./git.nix
  ];

  home.stateVersion = "26.05";

  # ghq has no Home Manager module; its root comes from ./git.nix.
  home.packages = [ pkgs.ghq ];
}
