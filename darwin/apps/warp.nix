{ ... }:
{
  my.apps.warp.appId = "dev.warp.Warp-Stable";

  # nixpkgs' `warp-terminal` currently fails to unpack the upstream APFS DMG
  # on darwin, so install the macOS app through Homebrew cask instead.
  homebrew.casks = [ "warp" ];
}
