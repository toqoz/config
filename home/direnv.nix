{ ... }:
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    # Nix devShells export dozens of internal variables; the diff is noise, not signal.
    # Variable changes are tied to flake.nix edits, so hiding the diff loses nothing useful.
    config.global.hide_env_diff = true;
  };
}
