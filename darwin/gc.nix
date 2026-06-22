{ ... }:
{
  launchd.user.agents.nix-gc = {
    serviceConfig = {
      Label = "user.toqoz.nix-gc";
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 0;
        }
      ];
    };
    command = "/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d";
  };
}
