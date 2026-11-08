{ config, lib, pkgs, ... }:
let
  cfg = config.my.t3code.sleepWatcher;
  logDir = "${config.xdg.stateHome}/t3-sleep-watcher";
in
{
  options.my.t3code.sleepWatcher = {
    enable = lib.mkEnableOption "the T3 Code sleep watcher";
    keepAwake = lib.mkEnableOption "Keepresso leases (otherwise observe only)";
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.my.t3code.enable && config.my.t3code.server.enable;
      message = "The sleep watcher requires the local T3 Code server.";
    }];

    home.activation.prepareT3SleepWatcherLogs = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
      if [ -L ${lib.escapeShellArg logDir} ]; then
        echo "t3-sleep-watcher: log directory must not be a symlink" >&2
        exit 1
      fi
      mkdir -p ${lib.escapeShellArg logDir}
      chmod 700 ${lib.escapeShellArg logDir}
    '';

    launchd.agents.t3-sleep-watcher = {
      enable = true;
      domain = "gui";
      config = {
        ProgramArguments = [
          "${pkgs.nodejs}/bin/node"
          "${./.}/main.mts"
          "--watch"
        ] ++ lib.optional cfg.keepAwake "--lease";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          KEEPRESSO_CLI = "/Applications/Keepresso.app/Contents/Helpers/keepresso";
          PATH = "${config.home.profileDirectory}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        Umask = 63;
        StandardErrorPath = "${logDir}/watcher.log";
      };
    };
  };
}
