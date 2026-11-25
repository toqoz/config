# Home Manager profile shared by every Linux host. It stays deliberately small:
# these hosts are small boards that evaluate this configuration on-device, so
# the darwin profile in ./base.nix (agents, GUI tools, heavy language runtimes)
# is not a baseline here.
{ pkgs, ... }:
{
  imports = [ ./git.nix ];

  home.stateVersion = "26.05";

  # `gh` without ./gh.nix: that module assumes the sops-managed identity
  # contexts and deletes ~/.config/gh/hosts.yml on every activation, which would
  # erase a `gh auth login` performed on a host that has no identity contexts.
  programs.gh.enable = true;

  # ghq has no Home Manager module; its root comes from ./git.nix.
  home.packages = [ pkgs.ghq ];
}
