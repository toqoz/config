{ ... }:
{
  imports = [
    ./base.nix
    ./agents/claude-code
    ./agents/codex/app-server.nix
    ./deepseek-harness
    ./t3code.nix
  ];

  my.t3code.enable = true;

  home.username = "agent";
  home.homeDirectory = "/Users/agent";
}
