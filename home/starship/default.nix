{ config, ... }:
{
  programs.starship = {
    enable = true;
    # Sourced manually in home/zsh/default.nix so we can gate it on
    # FENCE_SANDBOX (sandbox shells skip the prompt).
    enableZshIntegration = false;
  };
  # ref. https://github.com/starship/starship/issues/896
  xdg.configFile."starship.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/starship/config.toml";
}
