{ config, ... }:
{
  programs.zed-editor = {
    enable = true;
  };

  xdg.configFile."zed/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/zed/settings.json";

  xdg.configFile."zed/keymap.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/zed/keymap.json";
}
