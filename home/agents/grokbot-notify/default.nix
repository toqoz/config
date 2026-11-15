{ config, lib, pkgs, ... }:
let
  package = pkgs.writeShellScriptBin "grokbot-notify" ''
    exec ${pkgs.python3}/bin/python3 -B ${./.}/main.py "$@"
  '';
in
{
  options.my.grokbotNotify.command = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "${config.home.profileDirectory}/bin/grokbot-notify";
    description = "Stable hook command path, independent of the Nix store generation.";
  };

  config = {
    home.packages = [ package ];
    launchd.agents.grokbot-notify = {
      enable = true;
      config = {
        ProgramArguments = [ "${package}/bin/grokbot-notify" "drain" ];
        RunAtLoad = true;
        StartInterval = 30;
        ProcessType = "Background";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          XDG_STATE_HOME = config.xdg.stateHome;
        };
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/grokbot-notify.log";
      };
    };
  };
}
