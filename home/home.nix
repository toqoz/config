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
    ./vscode-family
    ./wezterm
    ./zed
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "toqoz";
  home.homeDirectory = "/Users/toqoz";
}
