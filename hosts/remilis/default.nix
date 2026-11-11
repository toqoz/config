{
  username = "toqoz";

  darwinModule = { ... }:
  {
    # Preserve Homebrew declaration order when combining shared and host apps.
    imports = builtins.sort (a: b: toString a < toString b) ((import ../../darwin/base.nix) ++ [
      ../../darwin/apps/aqua-voice.nix
      ../../darwin/apps/capcut.nix
      ../../darwin/apps/claude-desktop.nix
      ../../darwin/apps/figma.nix
      ../../darwin/apps/grok-bot.nix
      ../../darwin/apps/kanary.nix
      ../../darwin/apps/karabiner.nix
      ../../darwin/apps/keepresso.nix
      ../../darwin/apps/lark.nix
      ../../darwin/apps/linear.nix
      ../../darwin/apps/macskk.nix
      ../../darwin/apps/music.nix
      ../../darwin/apps/notion-calendar.nix
      ../../darwin/apps/orca.nix
      ../../darwin/apps/paper-design.nix
      ../../darwin/apps/safari.nix
      ../../darwin/apps/system-preferences.nix
      ../../darwin/apps/t3code.nix
      ../../darwin/apps/zed.nix
      ../../darwin/agent-instructions.nix
      ../../darwin/fonts.nix
      ../../darwin/system.nix
    ]);

    nixpkgs.hostPlatform = "aarch64-darwin";
    system.stateVersion = 6;

    system.startup.chime = false;
  };

  homeModule = { config, lib, ... }:
  {
    imports = [
      ../../home/base.nix
      ../../home/agents/claude-code
      ../../home/agents/mcp.nix
      ../../home/karabiner
      ../../home/less.nix
      ../../home/neovim
      ../../home/nix.nix
      ../../home/obsidian.nix
      ../../home/packages.nix
      ../../home/t3code.nix
      ../../home/t3-sleep-watcher
      ../../home/vscode-family
      ../../home/zed
    ];

    home.file = let
      instructions = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/nix-contexts/agent-instructions/AGENTS.md";
    in {
      ".codex/AGENTS.md".source = lib.mkForce instructions;
      "${config.programs.claude-code.configDir}/CLAUDE.md".source = lib.mkForce instructions;
    };

    # Both hosts run the server the same way; this one also runs the desktop
    # app, which attaches to the local server instead of starting its own.
    my.t3code.enable = true;
    my.t3code.desktop.enable = true;
    my.t3code.server.servePort = 3373;
    my.t3code.sleepWatcher.enable = true;
  };
}
