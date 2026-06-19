{ config, lib, ... }:
let
  inherit (config.my) apps;
in
{
  options.my.apps = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.appId = lib.mkOption {
          type = lib.types.str;
          description = ''
            macOS bundle identifier for the app. Apps set this under their
            own `darwin/apps/<name>.nix` module so that workspace-oriented
            consumers (aerospace window rules today; potentially other
            automation tomorrow) can reference the identifier by semantic
            name instead of duplicating the string.
          '';
        };
      }
    );
    default = { };
    description = ''
      Registry of managed darwin-side apps. Each app module contributes
      its own entry (today: bundle identifier). Intentionally free of
      app-specific layout decisions — those live with aerospace.
    '';
  };

  config = {
  services.aerospace = {
    enable = true;
    settings = {
      config-version = 2;

      exec = {
        inherit-env-vars = true;
        env-vars = {
          PATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/Users/toqoz/.nix-profile/bin:/etc/profiles/per-user/toqoz/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };

      after-startup-command = [
        "exec-and-forget sketchybar"
        "exec-and-forget borders"
      ];

      # JankyBorders misses focus changes inside an accordion (macOS doesn't
      # fire an AX focus event when only the stack z-order changes). Re-running
      # bordersrc here re-applies options to the live instance, which forces
      # it to re-query the focused window.
      on-focus-changed = [
        "exec-and-forget ~/.config/borders/bordersrc"
      ];

      # (managed by home-manager)
      start-at-login = false;

      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;

      accordion-padding = 30;
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";

      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

      exec-on-workspace-change = [
        "/bin/bash"
        "-c"
        "sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$(/run/current-system/sw/bin/aerospace list-workspaces --focused)"
      ];

      automatically-unhide-macos-hidden-apps = false;

      persistent-workspaces = [
        "1"
        "2"
        "3"
        "4"
        "5"
        "Q"
        "W"
        "E"
        "R"
        "T"
      ];

      on-mode-changed = [ ];

      key-mapping.preset = "qwerty";

      gaps = {
        inner = {
          horizontal = 8;
          vertical = 8;
        };
        outer = {
          left = 8;
          bottom = 8;
          top = [
            { monitor."Studio Display" = 40; }
            4
          ];
          right = 8;
        };
      };

      mode.main.binding = {
        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";

        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-tab = "focus dfs-next --boundaries-action wrap-around-the-workspace";
        alt-shift-tab = "focus dfs-prev --boundaries-action wrap-around-the-workspace";

        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";

        alt-q = "workspace Q";
        alt-w = "workspace W";
        alt-e = "workspace E";
        alt-r = "workspace R";
        alt-t = "workspace T";

        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";

        alt-shift-q = "move-node-to-workspace Q";
        alt-shift-w = "move-node-to-workspace W";
        alt-shift-e = "move-node-to-workspace E";
        alt-shift-r = "move-node-to-workspace R";
        alt-shift-t = "move-node-to-workspace T";

        # alt-tab = "workspace-back-and-forth";
        # alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

        alt-shift-semicolon = "mode service";
      };

      workspace-to-monitor-force-assignment = {
        "1" = "main";
        "2" = "main";
        "3" = "main";
        "4" = "secondary";
        "5" = "secondary";
        "Q" = "main";
        "W" = "main";
        "E" = "main";
        "R" = "secondary";
        "T" = "secondary";
      };

      # Workspace design: the full app-to-workspace mapping lives here,
      # ordered by target workspace. Each entry references its app via
      # `apps.<name>.appId` from darwin/apps/<name>.nix, so the identifier
      # is defined once with the app it belongs to, and the layout
      # decision stays centralized here where it can be reasoned about as
      # a whole.
      on-window-detected = [
        # workspace 1: terminal
        {
          "if".app-id = apps.wezterm.appId;
          run = [ "move-node-to-workspace 1" ];
        }
        # workspace 2: coding agents
        {
          "if".app-id = apps.codex.appId;
          run = [ "move-node-to-workspace 2" ];
        }
        # workspace 3: browser
        {
          "if".app-id = apps.chrome.appId;
          run = [ "move-node-to-workspace 3" ];
        }
        # workspace 4: containers
        {
          "if".app-id = apps.orbstack.appId;
          run = [
            "layout floating"
            "move-node-to-workspace 4"
          ];
        }
        # floating, no target workspace
        {
          "if".app-id = apps.aqua-voice.appId;
          run = [ "layout floating" ];
        }
        # workspace Q: comms / reading
        {
          "if".app-id = apps.safari.appId;
          run = [ "move-node-to-workspace Q" ];
        }
        {
          "if".app-id = apps.slack.appId;
          run = [ "move-node-to-workspace Q" ];
        }
        # workspace W: chat-style agents (accordion for stacking)
        {
          "if".app-id = apps.chatgpt.appId;
          run = [
            "move-node-to-workspace W"
            "layout accordion"
          ];
        }
        {
          "if".app-id = apps.claude-desktop.appId;
          run = [
            "move-node-to-workspace W"
            "layout accordion"
          ];
        }
        # workspace E: design
        {
          "if".app-id = apps.figma.appId;
          run = [ "move-node-to-workspace E" ];
        }
        # workspace R: floating utilities
        {
          "if".app-id = apps.system-preferences.appId;
          run = [
            "layout floating"
            "move-node-to-workspace R"
          ];
        }
        {
          "if".app-id = apps.karabiner.appId;
          run = [
            "layout floating"
            "move-node-to-workspace R"
          ];
        }
        {
          "if".app-id = apps.music.appId;
          run = [
            "layout floating"
            "move-node-to-workspace R"
          ];
        }
        {
          "if".app-id = apps."1password".appId;
          run = [
            "layout floating"
            "move-node-to-workspace R"
          ];
        }
      ];

      mode.service.binding = {
        esc = [
          "reload-config"
          "mode main"
        ];
        r = [
          "flatten-workspace-tree"
          "mode main"
        ];
        f = [
          "layout floating tiling"
          "mode main"
        ];
        backspace = [
          "close-all-windows-but-current"
          "mode main"
        ];

        alt-shift-h = [
          "join-with left"
          "mode main"
        ];
        alt-shift-j = [
          "join-with down"
          "mode main"
        ];
        alt-shift-k = [
          "join-with up"
          "mode main"
        ];
        alt-shift-l = [
          "join-with right"
          "mode main"
        ];
      };
    };
  };
  # Disable auto-restart so that when AeroSpace loses its accessibility permission
  # after an update (e.g. codesign certificate renewal), it won't spin in a crash loop
  # before you re-grant the permission in System Settings.
  #
  # To start manually after granting accessibility permission:
  # $ launchctl start org.nixos.aerospace
  launchd.user.agents.aerospace.serviceConfig.KeepAlive = lib.mkForce false;
  };
}
