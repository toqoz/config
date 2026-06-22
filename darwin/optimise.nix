{ ... }:
{
  launchd.user.agents.nix-optimise = {
    serviceConfig = {
      Label = "user.toqoz.nix-optimise";
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 30;
        }
      ];
    };
    command = "/nix/var/nix/profiles/default/bin/nix store optimise";
  };
}
