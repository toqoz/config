{ pkgs, llm-agents, gws, ... }:
{
  imports = [
    ./agents/agent-skills
    ./agents/codex
    ./android.nix
    ./asdf
    ./direnv.nix
    ./fzf.nix
    ./gh.nix
    ./git.nix
    ./pi
    ./repo.nix
    ./scripts.nix
    ./starship
    ./tmux
    ./unfree.nix
    ./xdg-misc.nix
    ./zsh
  ];

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
  programs.zsh = {
    enable = true;
    package = pkgs.emptyDirectory;
  };

  my.unfreePackages = [ "slack" "ntn" ];

  home.file.".npmrc".text = ''
    registry=https://npm.flatt.tech/
  '';

  xdg.configFile."pnpm/config.yaml".text = ''
    registry: https://npm.flatt.tech/
    minimumReleaseAge: 4320
  '';

  home.packages = with pkgs; [
    ghq
    pnpm
    mariadb.client
    slack
    (callPackage ../packages/ntn.nix { })
    (callPackage ../packages/ketch.nix { })
    gws.packages.${pkgs.stdenv.hostPlatform.system}.default
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser
    ripgrep
    fd
    git-wt
    openssh
    wget
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
  ];
}
