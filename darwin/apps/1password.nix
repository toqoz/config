{ ... }:
{
  my.apps."1password".appId = "com.1password.1password";

  # 1Password CLI (system-level)
  programs._1password.enable = true;
  my.unfreePackages = [ "1password-cli" ];

  # 1Password desktop (GUI + browser integration)
  homebrew.casks = [ "1password" ];
}
