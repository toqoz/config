{ config, pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withRuby = false;
    withPython3 = false;
    sideloadInitLua = true;

    extraWrapperArgs = [
      "--set"
      "TELESCOPE_FZY_NATIVE"
      "${pkgs.vimPlugins.telescope-fzy-native-nvim}"
    ];

    extraPackages = with pkgs; [
      skkDictionaries.l
      stylua # Lua formatter
      nixfmt
      vimPlugins.telescope-fzy-native-nvim # To avoid build steps
    ];
  };

  # `config/` holds the live nvim configuration (init.lua, lua/, and the
  # lazy.nvim lockfile). Kept in a subdir so that default.nix above it
  # does not land inside ~/.config/nvim.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/neovim/config";
}
