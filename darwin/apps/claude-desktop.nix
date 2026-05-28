{ ... }:
{
  my.apps.claude-desktop.appId = "com.anthropic.claudefordesktop";

  homebrew.casks = [ "claude" ];

  # Claude Chrome extension (force-installed via managed policy)
  my.chromeForceInstallExtensions = [ "fcoeoabgfenejglbffodgkkbkcdhcgfn" ];
}
