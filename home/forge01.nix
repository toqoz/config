{ ... }:
{
  imports = [
    ./base.nix
    ./deepseek-harness
  ];

  home.username = "agent";
  home.homeDirectory = "/Users/agent";
}
