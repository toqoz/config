{
  pkgs,
  llm-agents,
  ...
}:
{
  home.packages = [
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
  ];

  home.file.".pi/agent/keybindings.json".text = builtins.toJSON {
    "tui.editor.deleteCharBackward" = [
      "backspace"
      "ctrl+h"
    ];
  };
}
