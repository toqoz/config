{ ... }:
{
  imports = [
    ./base.nix
    ./agents/codex/app-server.nix
    ./deepseek-harness
  ];

  home.username = "agent";
  home.homeDirectory = "/Users/agent";
}
