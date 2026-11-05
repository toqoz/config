{ ... }:
{
  # The desktop app bundles its own server and provider CLIs; the `t3` command
  # can be linked from its Settings → About if a shell entry is wanted.
  my.apps.t3code.appId = "com.t3tools.t3code";

  homebrew.casks = [ "t3-code" ];
}
