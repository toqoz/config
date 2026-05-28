{ config, lib, pkgs, ... }:
let
  chromePolicy = {
    BrowserSignin = 0;
    ExtensionSettings = {
      "*" = {
        installation_mode = "allowed";
      };
    }
    // builtins.listToAttrs (
      map (id: {
        name = id;
        value = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      }) config.my.chromeForceInstallExtensions
    );
  };

  chromePolicyPlist = pkgs.writeText "com.google.Chrome.plist" (
    lib.generators.toPlist { escape = true; } chromePolicy
  );
in
{
  options.my.chromeForceInstallExtensions = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Chrome extension IDs to force-install via the managed-policy plist.
      Each owning app module should append its extension ID here so the
      install is declared alongside the app it belongs to.
    '';
  };

  config = {
    my.apps.chrome.appId = "org.google.Chrome";

    # Chrome itself (installed via Homebrew so updates land through Chrome's
    # own mechanism rather than Nix).
    homebrew.casks = [ "google-chrome" ];

    # Force-install extensions that are not owned by a dedicated app module.
    # Per-app extensions (e.g. 1Password) append their own IDs from their
    # own modules.
    my.chromeForceInstallExtensions = [
      "fmkadmapgofadopljbjfkapdkoienihi" # React Developer Tools
    ];

    system.activationScripts.postActivation.text = ''
      # Install Chrome Managed Policy
      install -d -m 0755 "/Library/Managed Preferences"
      install -m 0644 "${chromePolicyPlist}" "/Library/Managed Preferences/com.google.Chrome.plist"
      chown root:wheel "/Library/Managed Preferences/com.google.Chrome.plist"

      # Chrome reads macOS managed preferences through cfprefsd, which can keep
      # serving stale policy values after the plist is replaced.
      /usr/bin/killall cfprefsd 2>/dev/null || true
    '';
  };
}
