{ pkgs, ... }:
{
  my.unfreePackages = [ "kanary" ];
  environment.systemPackages = [ (pkgs.callPackage ../../packages/kanary.nix { }) ];
  system.defaults.CustomUserPreferences."download.kanary" = {
    SUEnableAutomaticChecks = false;
    SUAutomaticallyUpdate = false;
  };
}
