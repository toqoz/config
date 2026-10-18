{ ... }:
{
  my.apps.chrome.appId = "org.google.Chrome";

  # Install Chrome via Homebrew; manage settings and extensions in Chrome.
  homebrew.casks = [ "google-chrome" ];
}
