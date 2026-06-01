{
  lib,
  pkgs,
  llm-agents,
  ...
}:
let
  piPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  piPackages = [
    {
      name = "pi-mcp-adapter";
      version = "2.8.0";
    }
    {
      name = "pi-subagents";
      version = "0.27.0";
    }
    {
      name = "pi-intercom";
      version = "0.6.0";
    }
  ];
in
{
  home.packages = [
    piPackage
  ];

  home.activation.installPiPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${lib.makeBinPath [
      piPackage
      pkgs.jq
      pkgs.nodejs
    ]}:$PATH"
    export PI_SKIP_VERSION_CHECK=1
    export PI_TELEMETRY=0

    settings="$HOME/.pi/agent/settings.json"

    ${lib.concatMapStringsSep "\n" (pkg: ''
      source="npm:${pkg.name}@${pkg.version}"
      package_json="$HOME/.pi/agent/npm/node_modules/${pkg.name}/package.json"

      if [ -f "$package_json" ] \
        && jq -e --arg version "${pkg.version}" '.version == $version' "$package_json" >/dev/null \
        && [ -f "$settings" ] \
        && jq -e --arg source "$source" '(.packages // []) | any(. == $source or (.source? == $source))' "$settings" >/dev/null; then
        echo "${pkg.name} ${pkg.version} is already installed"
      else
        pi install "$source"
      fi
    '') piPackages}
  '';

  home.file.".pi/agent/AGENTS.md".source = ../agents/AGENTS.md;

  home.file.".pi/agent/keybindings.json".text = builtins.toJSON {
    "app.model.cycleForward" = [ "alt+n" ];
    "app.model.cycleBackward" = [ "alt+p" ];
    "app.session.togglePath" = [ "ctrl+shift+p" ];
    "app.session.toggleNamedFilter" = [ "ctrl+shift+n" ];
    "app.thinking.cycle" = [
      "shift+tab"
      "alt+shift+n"
    ];

    "tui.editor.cursorUp" = [
      "up"
      "ctrl+p"
    ];
    "tui.editor.cursorDown" = [
      "down"
      "ctrl+n"
    ];
    "tui.editor.cursorLeft" = [
      "left"
      "ctrl+b"
    ];
    "tui.editor.cursorRight" = [
      "right"
      "ctrl+f"
    ];
    "tui.editor.cursorWordLeft" = [
      "alt+left"
      "alt+b"
    ];
    "tui.editor.cursorWordRight" = [
      "alt+right"
      "alt+f"
    ];
    "tui.editor.deleteCharForward" = [
      "delete"
      "ctrl+d"
    ];
    "tui.editor.deleteCharBackward" = [
      "backspace"
      "ctrl+h"
    ];
    "tui.input.newLine" = [
      "alt+j"
    ];
    "tui.select.up" = [
      "up"
      "ctrl+p"
    ];
    "tui.select.down" = [
      "down"
      "ctrl+n"
    ];
  };
}
