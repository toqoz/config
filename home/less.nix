{ config, lib, ... }:
{
  home.sessionVariables = {
    LESSHISTFILE = "${config.xdg.dataHome}/less/history";

    # Force the initial position to the first line. less 600+ defaults to
    # placing EOF at the bottom row for files that fit on one screen, which
    # leaves blank rows above short content.
    LESS = "+g";
  };

  # less will not create the parent directory for LESSHISTFILE on first
  # write, so ensure it exists.
  home.activation.createLessHistDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.xdg.dataHome}/less"
  '';
}
