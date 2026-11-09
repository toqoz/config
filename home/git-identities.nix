{ config, lib, ... }:
{
  xdg.configFile."gh/config.yml".enable = lib.mkForce false;
  home.activation.removeOldGhHosts = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run rm -f ${lib.escapeShellArg "${config.xdg.configHome}/gh/hosts.yml"}
  '';
}
