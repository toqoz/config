{ lib, ... }:
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
}
