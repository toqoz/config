{ pkgs, ... }:
{
  # Keyboard remap — Caps Lock as Control. Done via system.keyboard so
  # the change persists across boots without depending on Karabiner.
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToControl = true;

  # TouchID for sudo, with pam-reattach so it still works inside tmux.
  # The `security.pam.services.sudo_local.touchIdAuth` shortcut does not
  # set up pam-reattach, so write the file directly.
  environment.systemPackages = [
    pkgs.pam-reattach
  ];
  environment.etc."pam.d/sudo_local".text = ''
    # managed by nix-darwin
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
    auth       sufficient     pam_tid.so
  '';

  # macOS `defaults` — the rest of this file is the long tail of UI/UX
  # tweaks that aren't worth splitting further. Per-app defaults that
  # belong with a specific app (Safari, ChatGPT) live in the app module.
  system.defaults = {
    NSGlobalDomain = {
      _HIHideMenuBar = true;
      AppleShowAllExtensions = true;
      ApplePressAndHoldEnabled = false; # For fast key repeat
      InitialKeyRepeat = 16;
      KeyRepeat = 4;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
    };

    dock = {
      autohide = true;
      show-recents = false;
      launchanim = false;
      expose-animation-duration = 0.1;
      persistent-apps = [ ];
      persistent-others = [ ];
    };

    finder = {
      # Show dotfiles
      AppleShowAllFiles = true;
      # Search Scope = cwd
      FXDefaultSearchScope = "SCcf";
      # List style
      FXPreferredViewStyle = "Nlsv";
      # Don't confirm changing file ext
      FXEnableExtensionChangeWarning = false;
      # Show filepath in title
      _FXShowPosixPathInTitle = true;
      # Don't show icons on desktop
      CreateDesktop = false;
      # Open ~
      NewWindowTarget = "Home";
    };

    screencapture = {
      target = "clipboard";
    };

    hitoolbox = {
      AppleFnUsageType = "Do Nothing";
    };

    CustomUserPreferences = {
      "com.apple.TextEdit" = {
        AddExtensionToNewPlainTextFiles = false;
        ShowRuler = false;
        SmartCopyPaste = false;
        SmartDashes = false;
        SmartQuotes = false;
        RichText = false;
        TextReplacement = false;
      };

      # Disable Spotlight file/folder results and app-provided content that
      # otherwise clutters launcher-style searches.
      "com.apple.Spotlight" = {
        EnabledPreferenceRules = [
          "System.files"
          "System.folders"
          "com.apple.AddressBook"
          "com.apple.AppStore"
          "com.apple.Dictionary"
          "com.apple.MobileSMS"
          "com.apple.Notes"
          "com.apple.Photos"
          "com.apple.Safari"
          "com.apple.VoiceMemos"
          "com.apple.calculator"
          "com.apple.helpviewer"
          "com.apple.iBooksX"
          "com.apple.iCal"
          "com.apple.mail"
          "com.apple.podcasts"
          "com.apple.reminders"
          "com.apple.shortcuts"
          "com.apple.systempreferences"
        ];
      };

      # When modifying com.apple.symbolichotkeys, you may need to run
      # /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # IME: Control+Space -> disable
          "60" = {
            enabled = false;
          };
          # Spotlight: Command+Space -> Option-Space
          "64" = {
            enabled = true;
            value = {
              type = "standard";
              parameters = [
                32
                49
                524288
              ]; # Option+Space
            };
          };
        };
      };
    };
  };
}
