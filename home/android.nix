{ ... }:
{
  my.unfreePackages = [
    "android-cli"
  ];

  # Android SDK + emulator via tadfisher/android-nixpkgs.
  # SDK is materialized at `~/.local/share/android` (the module default) and
  # exports ANDROID_HOME / ANDROID_SDK_ROOT.
  android-sdk = {
    enable = true;
    packages = sdk: with sdk; [
      cmdline-tools-latest
      platform-tools
      build-tools-36-0-0
      platforms-android-36
      emulator
      system-images-android-36-google-apis-playstore-arm64-v8a
    ];
  };
}
