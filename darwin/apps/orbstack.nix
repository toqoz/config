{ ... }:
{
  my.apps.orbstack.appId = "dev.kdrag0n.MacVirt";

  homebrew.casks = [ "orbstack" ];

  launchd.user.agents.orbstack-headless.serviceConfig = {
    ProgramArguments = [
      "/opt/homebrew/bin/orbctl"
      "start"
    ];
    RunAtLoad = true;
    KeepAlive = false;
    StandardOutPath = "/tmp/orbstack-headless.log";
    StandardErrorPath = "/tmp/orbstack-headless.err.log";
  };
}
