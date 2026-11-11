{ config, lib, ... }:
{
  home.file = let
    instructions = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix-contexts/agent-instructions/AGENTS.md";
  in {
    ".codex/AGENTS.md".source = lib.mkForce instructions;
    "${config.programs.claude-code.configDir}/CLAUDE.md".source = lib.mkForce instructions;
  };
  programs.mcp = {
    enable = true;
    servers = {
      Figma_0 = {
        type = "http";
        url = "https://mcp.figma.com/mcp";
      };
      Figma_1 = {
        type = "http";
        url = "https://mcp.figma.com/mcp?profile=1";
      };
    };
  };
}
