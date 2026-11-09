{
  username = "agent";

  darwinModule = { ... }:
  {
    imports = import ../../darwin/base.nix;

    nixpkgs.hostPlatform = "aarch64-darwin";
    system.stateVersion = 6;

    networking = {
      hostName = "forge01";
      localHostName = "forge01";
      computerName = "forge01";
    };
  };

  homeModule = { ... }:
  {
    imports = [
      ../../home/base.nix
      ../../home/agents/claude-code
      ../../home/agents/codex/app-server.nix
      ../../home/deepseek-harness
      ../../home/t3code.nix
    ];

    my.t3code.enable = true;
  };
}
