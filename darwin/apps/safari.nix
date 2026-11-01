{ ... }:
{
  my.apps.safari.appId = "com.apple.Safari";

  homebrew.masApps."1Password for Safari" = 1569813296;

  system.defaults.CustomUserPreferences."com.apple.Safari" = {
    AutoFillFromAddressBook = false;
    AutoFillPasswords = false;
    AutoFillCreditCardData = false;
    AutoFillMiscellaneousForms = false;
    AutoOpenSafeDownloads = false;
    IncludeDevelopMenu = true;
    IncludeInternalDebugMenu = true;
    WebKitDeveloperExtrasEnabledPreferenceKey = true;
    "WebKitPreferences.developerExtrasEnabled" = true;
  };
}
