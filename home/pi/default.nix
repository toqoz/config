{
  lib,
  pkgs,
  llm-agents,
  ...
}:
let
  piPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  piMcpAdapterVersion = "2.8.0";
  piMcpAdapterSource = "npm:pi-mcp-adapter@${piMcpAdapterVersion}";
in
{
  home.packages = [
    piPackage
  ];

  home.activation.installPiMcpAdapter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${lib.makeBinPath [
      piPackage
      pkgs.jq
      pkgs.nodejs
    ]}:$PATH"
    export PI_SKIP_VERSION_CHECK=1
    export PI_TELEMETRY=0

    settings="$HOME/.pi/agent/settings.json"
    package_json="$HOME/.pi/agent/npm/pi-mcp-adapter/package.json"

    if [ -f "$package_json" ] \
      && jq -e --arg version "${piMcpAdapterVersion}" '.version == $version' "$package_json" >/dev/null \
      && [ -f "$settings" ] \
      && jq -e --arg source "${piMcpAdapterSource}" '(.packages // []) | any(. == $source or (.source? == $source))' "$settings" >/dev/null; then
      echo "pi-mcp-adapter ${piMcpAdapterVersion} is already installed"
    else
      pi install "${piMcpAdapterSource}"
    fi
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
      "alt+m"
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
