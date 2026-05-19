{
  pkgs,
  llm-agents,
  ...
}:
{
  home.packages = [
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
  ];

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
