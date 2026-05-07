{ config, lib, ... }:
{
  home.sessionVariables = {
    LESSHISTFILE = "${config.xdg.dataHome}/less/history";
  };

  # less will not create the parent directory for LESSHISTFILE on first
  # write, so ensure it exists.
  home.activation.createLessHistDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.xdg.dataHome}/less"
  '';
}
