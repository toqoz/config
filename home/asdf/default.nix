{ config, lib, pkgs, ... }:
let
  asdfConfigDir = "${config.xdg.configHome}/asdf";
  asdfDataDir = "${config.xdg.dataHome}/asdf";
in
{
  home.packages = [ pkgs.asdf-vm ];

  home.sessionVariables = {
    ASDF_CONFIG_FILE = "${asdfConfigDir}/.asdfrc";
    ASDF_DATA_DIR = "${asdfDataDir}";
  };

  xdg.configFile."asdf/.asdfrc".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/asdf/.asdfrc";
  home.file.".tool-versions".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/asdf/.tool-versions";

  home.activation.installAsdfPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          asdf-vm
          git
          #curl
          #gnugrep
          #coreutils
          #gnutar
          #gzip
          #unzip
          #gawk
          #findutils
        ]
      )
    }:$PATH"
    export ASDF_DATA_DIR="${asdfDataDir}"
    export ASDF_CONFIG_FILE="${asdfConfigDir}/.asdfrc"
    mkdir -p "$ASDF_DATA_DIR" "${asdfConfigDir}"
    if ! asdf plugin list | grep -qx nodejs; then
      asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
    fi
    if ! asdf plugin list | grep -qx pnpm; then
      asdf plugin add pnpm https://github.com/jonathanmorley/asdf-pnpm.git
    fi
    if ! asdf plugin list | grep -qx deno; then
      asdf plugin add deno https://github.com/asdf-community/asdf-deno.git
    fi
    if ! asdf plugin list | grep -qx erlang; then
      asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
    fi
    if ! asdf plugin list | grep -qx elixir; then
      asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
    fi
  '';
}
