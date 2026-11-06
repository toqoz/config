{ ... }:
{
  imports = [
    ./base.nix
    ./agents/claude-code
    ./agents/mcp.nix
    ./hunk.nix
    ./karabiner
    ./less.nix
    ./neovim
    ./nix.nix
    ./obsidian.nix
    ./packages.nix
    ./ssh.nix
    ./t3code.nix
    ./vscode-family
    ./wezterm
    ./zed
  ];

  # The desktop app and the CLI come from the same pinned llm-agents revision
  # as the forge01 server, so both hosts run one version. The server itself
  # stays on forge01.
  my.t3code.enable = true;
  my.t3code.desktop.enable = true;
  my.t3code.server.enable = false;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "toqoz";
  home.homeDirectory = "/Users/toqoz";
}
