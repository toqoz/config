{ ... }:
{
  imports = [
    ./agents/agent-skills
    ./agents/claude-code
    ./agents/codex
    ./agents/mcp.nix
    ./android.nix
    ./asdf
    ./borders
    ./direnv.nix
    ./fzf.nix
    ./gh.nix
    ./git.nix
    ./karabiner
    ./neovim
    ./nix.nix
    ./obsidian.nix
    ./packages.nix
    ./repo.nix
    ./scripts.nix
    ./sketchybar
    ./starship
    ./tmux
    ./unfree.nix
    ./vscode-family
    ./wezterm
    ./xdg-misc.nix
    ./zsh
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "toqoz";
  home.homeDirectory = "/Users/toqoz";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.11"; # Please read the comment before changing.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
