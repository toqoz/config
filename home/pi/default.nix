{
  lib,
  pkgs,
  llm-agents,
  ...
}:
let
  piPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  # pstack 0.9.102; pin the Git source like the npm packages below.
  pstackRevision = "356c6e0f978df729eb16f227d795f34d221c5aad";
  piPackages = [
    {
      name = "pi-mcp-adapter";
      version = "6.0.0";
    }
    {
      name = "pi-subagents";
      version = "0.76.1";
    }
    {
      name = "pi-intercom";
      version = "0.16.1";
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
      pkgs.git
      pkgs.jq
      pkgs.nodejs
    ]}:$PATH"
    export PI_SKIP_VERSION_CHECK=1
    export PI_TELEMETRY=0

    settings="$HOME/.pi/agent/settings.json"

    mkdir -p "$(dirname "$settings")"
    tmp_settings="$(mktemp)"
    if [ -f "$settings" ]; then
      jq '. as $settings | $settings + {
        defaultProvider: "openai-codex",
        defaultModel: "gpt-6.1-sol",
        defaultThinkingLevel: "medium",
        extensions: (($settings.extensions // []) | if index("-builtin:mcp") then . else . + ["-builtin:mcp"] end)
      }' "$settings" > "$tmp_settings"
    else
      jq -n '{
        defaultProvider: "openai-codex",
        defaultModel: "gpt-6.1-sol",
        defaultThinkingLevel: "medium",
        extensions: ["-builtin:mcp"]
      }' > "$tmp_settings"
    fi
    install -m 0600 "$tmp_settings" "$settings"
    rm -f "$tmp_settings"

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

    source="git:github.com/michael-denyer/pstack-claude@${pstackRevision}"
    checkout="$HOME/.pi/agent/git/github.com/michael-denyer/pstack-claude"
    if [ "$(git -C "$checkout" rev-parse HEAD 2>/dev/null)" = "${pstackRevision}" ] \
      && jq -e --arg source "$source" '(.packages // []) | any(. == $source or (.source? == $source))' "$settings" >/dev/null; then
      echo "pstack 0.9.102 is already installed"
    else
      pi install "$source"
    fi
  '';

  home.file.".pi/agent/AGENTS.md".source = ../agents/AGENTS.md;
  home.file.".pi/agent/pstack-models.md".source = ./pstack-models.md;

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
    # Keep Alt-J for WezTerm, which remaps Shift-Enter to Alt-J.
    # Orca/xterm can report Shift-Enter directly, so bind that too instead of
    # synthesizing an OS-level Alt-J that AeroSpace may intercept.
    "tui.input.newLine" = [
      "alt+j"
      "shift+enter"
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
