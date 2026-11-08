{ ... }:
{
  imports = [
    ./base.nix
    ./agents/claude-code
    ./agents/mcp.nix
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

  # Both hosts run the server the same way; this one also runs the desktop
  # app, which attaches to the local server instead of starting its own.
  my.t3code.enable = true;
  my.t3code.desktop.enable = true;
  my.t3code.server.servePort = 3373;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "toqoz";
  home.homeDirectory = "/Users/toqoz";
}
