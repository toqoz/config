{ pkgs, lib, llm-agents, forge, remilis }:
let
  forgeHome = forge.home-manager.users.agent;
  remilisHome = remilis.home-manager.users.toqoz;
  paths = packages: map (package: package.outPath) packages;
  toolPaths = home: builtins.filter
    (path: path != home.home.sessionVariablesPackage.outPath)
    (paths home.home.packages);
  extraHome = lib.subtractLists (toolPaths remilisHome) (toolPaths forgeHome);
  extraSystem = lib.subtractLists
    (paths remilis.environment.systemPackages)
    (paths forge.environment.systemPackages);
  requiredTools = with pkgs; [
    ripgrep fd git-wt openssh wget mariadb.client
    llm-agents.packages.${stdenv.hostPlatform.system}.codex
  ];
  missingTools = lib.subtractLists (toolPaths forgeHome) (paths requiredTools);
  requiredToolNames = [
    "asdf-vm" "erlang" "direnv" "gh" "ghq" "pnpm" "slack" "gws"
    "portless" "ntn" "ketch" "pi" "agent-browser" "fzf" "starship" "tmux"
    "tmux-window-picker" "tmux-swap-window" "tmux-window-tag"
  ];
  missingToolNames = lib.subtractLists (map lib.getName forgeHome.home.packages) requiredToolNames;
  normalize = home: lib.replaceStrings [ home.home.homeDirectory ] [ "$HOME" ];
  sameText = path:
    normalize forgeHome forgeHome.home.file.${path}.text
    == normalize remilisHome remilisHome.home.file.${path}.text;
  sameVariable = name:
    normalize forgeHome forgeHome.home.sessionVariables.${name}
    == normalize remilisHome remilisHome.home.sessionVariables.${name};
  shellFiles = [ ".zshenv" ".config/zsh/.zshenv" ".config/zsh/.zprofile" ".config/zsh/.zshrc" ];
  # Home Manager embeds the host's session-vars store path. remilis alone
  # adds WezTerm integration and Neovim's vimdiff alias to the shared rc.
  normalizeShell = home: text: normalize home (lib.replaceStrings
    [ home.home.sessionVariablesPackage.outPath ] [ "$SESSION_VARS" ] text);
  remilisShellExtras = [
    "source \"${remilisHome.programs.wezterm.package}/etc/profile.d/wezterm.sh\"\n\n"
    "alias -- vimdiff='nvim -d'\n"
  ];
  sameShell = path:
    normalizeShell forgeHome forgeHome.home.file.${path}.text
    == normalizeShell remilisHome (lib.replaceStrings remilisShellExtras [ "" "" ] remilisHome.home.file.${path}.text);
  zshrc = forgeHome.home.file.".config/zsh/.zshrc".text;
  zprofile = forgeHome.home.file.".config/zsh/.zprofile".text;
  repoLink = home: source: target:
    toString source == toString (home.lib.file.mkOutOfStoreSymlink "${home.my.repoPath}/${target}");
  forgeSkills = forgeHome.programs.agent-skills;
  remilisSkills = remilisHome.programs.agent-skills;
in
assert lib.assertMsg (
  forge.networking.hostName == "forge01"
  && forge.networking.localHostName == "forge01"
  && forge.networking.computerName == "forge01"
) "forge01 must set all macOS host names to forge01";
assert lib.assertMsg (
  forge.system.primaryUser == "agent"
  && builtins.attrNames forge.home-manager.users == [ "agent" ]
  && forge.users.users.agent.home == "/Users/agent"
  && forgeHome.home.username == "agent"
  && forgeHome.home.homeDirectory == "/Users/agent"
) "forge01 must manage the agent account at /Users/agent";
assert lib.assertMsg (extraHome == [ ])
  "forge01 home.packages contains packages absent from remilis: ${lib.concatStringsSep ", " extraHome}";
assert lib.assertMsg (extraSystem == [ ])
  "forge01 environment.systemPackages contains packages absent from remilis: ${lib.concatStringsSep ", " extraSystem}";
assert lib.assertMsg (missingTools == [ ])
  "forge01 is missing required tools: ${lib.concatStringsSep ", " missingTools}";
assert lib.assertMsg (missingToolNames == [ ])
  "forge01 is missing shared tools: ${lib.concatStringsSep ", " missingToolNames}";
assert lib.assertMsg (lib.sort builtins.lessThan (map (cask: cask.name) forge.homebrew.casks) == [ "codex-app" "google-chrome" "orbstack" ])
  "forge01 must manage exactly the codex-app, google-chrome, and orbstack casks";
assert lib.assertMsg (forge.homebrew.brews == [ ] && forge.homebrew.masApps == { })
  "forge01 must not manage Homebrew formulae or Mac App Store apps";
assert lib.assertMsg (forge.my.apps == {
  codex.appId = "com.openai.codex";
  chrome.appId = "org.google.Chrome";
  orbstack.appId = "dev.kdrag0n.MacVirt";
  slack.appId = "com.tinyspeck.slackmacgap";
}) "forge01 must register exactly Codex, Chrome, OrbStack, and Slack";
assert lib.assertMsg (
  forgeHome.android-sdk.enable
  && forgeHome.android-sdk.finalPackage.outPath == remilisHome.android-sdk.finalPackage.outPath
  && normalize forgeHome forgeHome.android-sdk.path == normalize remilisHome remilisHome.android-sdk.path
  && lib.all sameVariable [ "ANDROID_HOME" "ANDROID_SDK_ROOT" ]
) "forge01 must share the Android SDK, emulator, system image, and paths with remilis";
assert lib.assertMsg (
  forge.launchd.user.agents.orbstack-headless == remilis.launchd.user.agents.orbstack-headless
) "forge01 must share OrbStack headless startup with remilis";
assert lib.assertMsg (!forge.services.aerospace.enable && !forge.system.keyboard.enableKeyMapping)
  "forge01 must not enable Aerospace or keyboard remapping";
assert lib.assertMsg (
  forgeHome.programs.git.enable
  && forgeHome.programs.git.settings == remilisHome.programs.git.settings
  && forgeHome.programs.git.ignores == remilisHome.programs.git.ignores
  && forgeHome.programs.git.package.outPath == remilisHome.programs.git.package.outPath
  && forgeHome.xdg.configFile."git/config".source == remilisHome.xdg.configFile."git/config".source
  && forgeHome.xdg.configFile."git/ignore".source == remilisHome.xdg.configFile."git/ignore".source
) "forge01 must use the same Git settings, generated files, and wrapper as remilis";
assert lib.assertMsg (
  forgeSkills.enable
  && forgeSkills.catalog == remilisSkills.catalog
  && forgeSkills.bundlePath == remilisSkills.bundlePath
  && forgeSkills.targets == remilisSkills.targets
  && forgeSkills.targetBundlePaths == remilisSkills.targetBundlePaths
  && forgeHome.home.activation.agent-skills.data == remilisHome.home.activation.agent-skills.data
) "forge01 must deploy the same skill catalog, bundles, and targets as remilis";
assert lib.assertMsg (
  forgeHome.programs.zsh.enable
  && forge.programs.zsh.enable
  && forge.programs.zsh.enableCompletion
  && lib.hasInfix "autoload -U compinit && compinit" forge.environment.etc.zshrc.text
  && forgeHome.programs.zsh.dotDir == "${forgeHome.xdg.configHome}/zsh"
  && remilisHome.programs.zsh.dotDir == "${remilisHome.xdg.configHome}/zsh"
  && lib.all sameShell shellFiles
  && lib.hasInfix "source ${forgeHome.programs.zsh.dotDir}/.zshenv" forgeHome.home.file.".zshenv".text
  && builtins.length (lib.splitString "brew shellenv zsh" zprofile) == 2
  && !lib.hasInfix "brew shellenv zsh" forge.programs.zsh.interactiveShellInit
  && forgeHome.programs.fzf.enable
  && forgeHome.programs.fzf.enableZshIntegration
  && forgeHome.programs.starship.enable
  && forgeHome.programs.tmux.enable
  && lib.hasInfix (builtins.unsafeDiscardStringContext "${forgeHome.programs.fzf.package}/share/fzf/key-bindings.zsh") zshrc
  && lib.hasInfix (builtins.unsafeDiscardStringContext "${forgeHome.programs.starship.package}/bin/starship init zsh") zshrc
  && forgeHome.programs.direnv.enable
  && forgeHome.programs.direnv.enableZshIntegration
  && forgeHome.programs.direnv.nix-direnv.enable
  && lib.hasInfix
    (builtins.unsafeDiscardStringContext "${lib.getExe forgeHome.programs.direnv.package} hook zsh")
    zshrc
  && forgeHome.programs.codex.enable
) "forge01 must use the full shared zsh with one Homebrew init, fzf, starship, tmux, and direnv";
assert lib.assertMsg (
  lib.all sameVariable [ "ASDF_CONFIG_FILE" "ASDF_DATA_DIR" "XDG_CONFIG_HOME" "XDG_DATA_HOME" "Z_DATA_DIR" "Z_CACHE_DIR" "DISABLE_TELEMETRY" "STARSHIP_CONFIG" "WGETHSTS" ]
  && forgeHome.home.sessionVariables.XDG_CONFIG_HOME == forgeHome.xdg.configHome
  && normalize forgeHome forgeHome.my.repoPath == normalize remilisHome remilisHome.my.repoPath
  && map (normalize forgeHome) forgeHome.home.sessionPath == map (normalize remilisHome) remilisHome.home.sessionPath
  && forgeHome.home.file.".local/share/home-scripts/bin".source == remilisHome.home.file.".local/share/home-scripts/bin".source
  && lib.all (home:
    repoLink home home.xdg.configFile."asdf/.asdfrc".source "home/asdf/.asdfrc"
    && repoLink home home.home.file.".tool-versions".source "home/asdf/.tool-versions"
    && repoLink home home.xdg.configFile."zsh/functions".source "home/zsh/functions"
    && repoLink home home.xdg.configFile."starship.toml".source "home/starship/config.toml"
  ) [ forgeHome remilisHome ]
  && normalize forgeHome forgeHome.xdg.configFile."tmux/tmux.conf".text
    == normalize remilisHome remilisHome.xdg.configFile."tmux/tmux.conf".text
  && normalize forgeHome forgeHome.home.activation.installAsdfPlugins.data
    == normalize remilisHome remilisHome.home.activation.installAsdfPlugins.data
  && forgeHome.home.activation.installAsdfPlugins.after == remilisHome.home.activation.installAsdfPlugins.after
  && forgeHome.home.activation.installAsdfPlugins.before == remilisHome.home.activation.installAsdfPlugins.before
) "forge01 must share asdf, XDG paths, checkout links, and shell support configuration with remilis";
assert lib.assertMsg (
  forgeHome.home.activation.installPiPackages == remilisHome.home.activation.installPiPackages
  && forgeHome.home.file.".pi/agent/AGENTS.md".source == remilisHome.home.file.".pi/agent/AGENTS.md".source
  && forgeHome.home.file.".pi/agent/pstack-models.md".source == remilisHome.home.file.".pi/agent/pstack-models.md".source
  && sameText ".pi/agent/keybindings.json"
) "forge01 must share Pi configuration and package activation with remilis";
assert lib.assertMsg (
  sameText ".npmrc"
  && forgeHome.home.file.".npmrc".text == "registry=https://npm.flatt.tech/\n"
  && forgeHome.xdg.configFile."pnpm/config.yaml".text == remilisHome.xdg.configFile."pnpm/config.yaml".text
  && forgeHome.xdg.configFile."pnpm/config.yaml".text == ''
    registry: https://npm.flatt.tech/
    minimumReleaseAge: 4320
  ''
) "forge01 must use the shared npm and pnpm Takumi Guard registry with minimumReleaseAge 4320";
pkgs.runCommand "forge01-contract" { } ''
  touch "$out"
''
