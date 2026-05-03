{ config, ... }:
{
  # Environment variables for small tools that have no dedicated module
  # and whose only customization is "stop writing to $HOME; honor XDG".
  #
  # If any of these tools later grows a real config surface, move that
  # tool out to its own module.
  home.sessionVariables = {
    # Many XDG-aware tools (tig, yazi, fd, ...) check this. Home Manager's
    # xdg.dataHome is the canonical value but is not exported by default
    # when xdg.enable is off.
    XDG_DATA_HOME = config.xdg.dataHome;

    WGETHSTS = "${config.xdg.cacheHome}/wget/hsts";
  };
}
