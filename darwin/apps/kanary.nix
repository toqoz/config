{ pkgs, ... }:
{
  my.unfreePackages = [ "kanary" ];
  environment.systemPackages = [ (pkgs.callPackage ../../packages/kanary.nix { }) ];
}
