{ ... }:
{
  imports = [
    ./base.nix
    ./agents/claude-code
    ./agents/codex/app-server.nix
    ./deepseek-harness
  ];

  home.username = "agent";
  home.homeDirectory = "/Users/agent";
}
