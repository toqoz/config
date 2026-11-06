{ pkgs, lib, llm-agents, forge, remilis }:
let
  forgeHome = forge.home-manager.users.agent;
  remilisHome = remilis.home-manager.users.toqoz;
  paths = packages: map (package: package.outPath) packages;
  toolPaths = home: builtins.filter
    (path: path != home.home.sessionVariablesPackage.outPath)
    (paths home.home.packages);
  # deepseek-harness and t3code are the permitted home.packages divergences:
  # both are forge01-only by design, asserted present there and absent on
  # remilis below. The T3 Code desktop bundle on remilis comes from the same
  # pinned llm-agents revision as the CLI.
  byPname = pname: builtins.filter (package: (package.pname or "") == pname);
  forgeDeepseek = byPname "deepseek-harness" forgeHome.home.packages;
  remilisDeepseek = byPname "deepseek-harness" remilisHome.home.packages;
  deepseekAgent = forgeHome.launchd.agents.deepseek-harness;
  deepseekInstall = forgeHome.home.activation.installDeepseekHarness;
  deepseekData = "${forgeHome.xdg.dataHome}/deepseek-harness";
  codexAgent = forgeHome.launchd.agents.codex-app-server;
  codexPrepare = forgeHome.home.activation.prepareCodexAppServer;
  codexState = "${forgeHome.xdg.stateHome}/codex-app-server";
  forgeT3Code = byPname "t3code" forgeHome.home.packages;
  remilisT3Code = byPname "t3code" remilisHome.home.packages;
  t3codeAgent = forgeHome.launchd.agents.t3code;
  remilisT3codeAgent = remilisHome.launchd.agents.t3code;
  t3codePrepare = forgeHome.home.activation.prepareT3CodeLogs;
  t3codeState = "${forgeHome.xdg.stateHome}/t3code";
  extraHome = lib.subtractLists
    (toolPaths remilisHome ++ paths forgeDeepseek ++ paths forgeT3Code)
    (toolPaths forgeHome);
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
    "tmux-window-picker" "tmux-swap-window" "tmux-window-tag" "claude-code"
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
assert lib.assertMsg (builtins.length forgeDeepseek == 1)
  "forge01 must install exactly one deepseek-harness package";
assert lib.assertMsg (
  remilisDeepseek == [ ]
  && !(remilisHome.home.activation ? installDeepseekHarness)
  && !(remilisHome.launchd.agents ? deepseek-harness)
) "remilis must not install or run deepseek-harness";
assert lib.assertMsg (
  lib.elem "writeBoundary" deepseekInstall.after
  && lib.elem "linkGeneration" deepseekInstall.after
  && lib.elem "setupLaunchAgents" deepseekInstall.before
  && forgeHome.home.activation ? setupLaunchAgents
  && lib.hasInfix "run mkdir -p" deepseekInstall.data
  && lib.hasInfix "run chmod 700" deepseekInstall.data
  && lib.hasInfix "run touch" deepseekInstall.data
  && lib.hasInfix "run chmod 600" deepseekInstall.data
  && lib.hasInfix "umask 077" deepseekInstall.data
  && lib.hasInfix
    (builtins.unsafeDiscardStringContext "run env DEEPSEEK_HARNESS_HOME=${lib.escapeShellArg deepseekData} ${(builtins.head forgeDeepseek).outPath}/bin/deepseek-harness-install")
    deepseekInstall.data
) "forge01 must install deepseek-harness privately after user configuration and before launchd setup";
assert lib.assertMsg (
  deepseekAgent.enable
  && deepseekAgent.domain == "gui"
  && deepseekAgent.config.LimitLoadToSessionType == null
  && deepseekAgent.config.ProgramArguments == [ "${(builtins.head forgeDeepseek).outPath}/bin/deepseek-harness-service" ]
  && deepseekAgent.config.WorkingDirectory == forgeHome.home.homeDirectory
  && lib.all (path: lib.elem path (lib.splitString ":" deepseekAgent.config.EnvironmentVariables.PATH))
    (forgeHome.home.sessionPath ++ [ "${forgeHome.home.profileDirectory}/bin" "/run/current-system/sw/bin" "/usr/bin" "/bin" ])
  && deepseekAgent.config.RunAtLoad
  && deepseekAgent.config.KeepAlive == true
  && deepseekAgent.config.ThrottleInterval == 10
  && deepseekAgent.config.Umask == 63
  && deepseekAgent.config.StandardOutPath == "${deepseekData}/log/stdout.log"
  && deepseekAgent.config.StandardErrorPath == "${deepseekData}/log/stderr.log"
) "forge01 must automatically start and restart the pinned service in HOME with private logs, from the gui domain so the login keychain is available";
assert lib.assertMsg (
  !(remilisHome.home.activation ? prepareCodexAppServer)
  && !(remilisHome.launchd.agents ? codex-app-server)
  && lib.elem "linkGeneration" codexPrepare.after
  && lib.elem "mergeCodexConfig" codexPrepare.after
  && lib.elem "setupLaunchAgents" codexPrepare.before
) "Codex app-server must be forge01-only and prepare state after Codex config but before launchd setup";
assert lib.assertMsg (
  codexAgent.enable
  && codexAgent.domain == "user"
  && builtins.length codexAgent.config.ProgramArguments == 1
  && lib.hasPrefix "/nix/store/" (builtins.head codexAgent.config.ProgramArguments)
  && lib.hasSuffix "-codex-app-server" (builtins.head codexAgent.config.ProgramArguments)
  && codexAgent.config.WorkingDirectory == forgeHome.home.homeDirectory
  && codexAgent.config.EnvironmentVariables.HOME == forgeHome.home.homeDirectory
  && codexAgent.config.EnvironmentVariables.PATH == deepseekAgent.config.EnvironmentVariables.PATH
  && codexAgent.config.RunAtLoad
  && codexAgent.config.KeepAlive == true
  && codexAgent.config.ThrottleInterval == 10
  && codexAgent.config.Umask == 63
  && codexAgent.config.StandardOutPath == "${codexState}/log/stdout.log"
  && codexAgent.config.StandardErrorPath == "${codexState}/log/stderr.log"
) "forge01 must run the store-pinned Codex app-server in HOME with private logs and automatic restart";
assert lib.assertMsg (
  builtins.length forgeT3Code == 1
  && builtins.length remilisT3Code == 1
  && (builtins.head forgeT3Code).outPath == (builtins.head remilisT3Code).outPath
) "both hosts must install the same pinned T3 Code CLI";
assert lib.assertMsg (
  remilisHome.home.file ? "Applications/T3 Code (Beta).app"
  && !(forgeHome.home.file ? "Applications/T3 Code (Beta).app")
  && !(lib.elem "t3-code" (map (cask: cask.name) remilis.homebrew.casks))
) "remilis must link the T3 Code desktop bundle from nix instead of installing the cask";
assert lib.assertMsg (
  !(forgeHome.home.activation ? mergeT3CodeDesktopSettings)
  && remilisHome.home.activation ? mergeT3CodeDesktopSettings
  && lib.hasInfix "localEnvironmentEnabled: false"
    remilisHome.home.activation.mergeT3CodeDesktopSettings.data
) "remilis must turn off the desktop app's local environment so it can use the service";
assert lib.assertMsg (
  remilisT3codeAgent.enable
  && remilisT3codeAgent.domain == "user"
  && remilisT3codeAgent.config.ProgramArguments == [
    "${(builtins.head remilisT3Code).outPath}/bin/t3"
    "serve"
    "--no-browser"
    "--tailscale-serve"
    "--tailscale-serve-port"
    "3373"
  ]
  && remilisT3codeAgent.config.EnvironmentVariables.T3CODE_HOST == "127.0.0.1"
  && remilisT3codeAgent.config.EnvironmentVariables.T3CODE_PORT == "3773"
  && lib.elem "/usr/local/bin"
    (lib.splitString ":" remilisT3codeAgent.config.EnvironmentVariables.PATH)
  && remilisHome.home.activation ? prepareT3CodeLogs
) "remilis must run the same T3 Code server as forge01, with its own tailnet port";
assert lib.assertMsg (
  t3codeAgent.enable
  && t3codeAgent.domain == "user"
  && t3codeAgent.config.ProgramArguments == [
    "${(builtins.head forgeT3Code).outPath}/bin/t3"
    "serve"
    "--no-browser"
    "--tailscale-serve"
    "--tailscale-serve-port"
    "3773"
  ]
  && lib.elem "/usr/local/bin"
    (lib.splitString ":" t3codeAgent.config.EnvironmentVariables.PATH)
  && t3codeAgent.config.WorkingDirectory == forgeHome.home.homeDirectory
  && t3codeAgent.config.EnvironmentVariables.T3CODE_HOST == "127.0.0.1"
  && t3codeAgent.config.EnvironmentVariables.T3CODE_PORT == "3773"
  && t3codeAgent.config.RunAtLoad
  && t3codeAgent.config.KeepAlive == true
  && t3codeAgent.config.ThrottleInterval == 10
  && t3codeAgent.config.Umask == 63
  && t3codeAgent.config.StandardOutPath == "${t3codeState}/log/stdout.log"
  && t3codeAgent.config.StandardErrorPath == "${t3codeState}/log/stderr.log"
  && lib.elem "linkGeneration" t3codePrepare.after
  && lib.elem "setupLaunchAgents" t3codePrepare.before
) "forge01 must run the T3 Code server on loopback with private logs and automatic restart";
assert lib.assertMsg (
  remilis.my.apps.t3code == { appId = "org.nixos.T3 Code (Beta)"; }
  && !(forge.my.apps ? t3code)
) "remilis must register the T3 Code bundle identifier; forge01 must not";
assert lib.assertMsg (extraSystem == [ ])
  "forge01 environment.systemPackages contains packages absent from remilis: ${lib.concatStringsSep ", " extraSystem}";
assert lib.assertMsg (missingTools == [ ])
  "forge01 is missing required tools: ${lib.concatStringsSep ", " missingTools}";
assert lib.assertMsg (missingToolNames == [ ])
  "forge01 is missing shared tools: ${lib.concatStringsSep ", " missingToolNames}";
assert lib.assertMsg (lib.sort builtins.lessThan (map (cask: cask.name) forge.homebrew.casks) == [ "1password" "chatgpt" "google-chrome" "orbstack" "tailscale-app" ])
  "forge01 must manage exactly the 1password, chatgpt, google-chrome, orbstack, and tailscale-app casks";
assert lib.assertMsg (forge.homebrew.brews == [ ] && forge.homebrew.masApps == { })
  "forge01 must not manage Homebrew formulae or Mac App Store apps";
assert lib.assertMsg (forge.my.apps == {
  "1password".appId = "com.1password.1password";
  chatgpt.appId = "com.openai.chat";
  chrome.appId = "org.google.Chrome";
  orbstack.appId = "dev.kdrag0n.MacVirt";
  slack.appId = "com.tinyspeck.slackmacgap";
  tailscale.appId = "io.tailscale.ipn.macsys";
}) "forge01 must register exactly 1Password, ChatGPT, Chrome, OrbStack, Slack, and Tailscale";
assert lib.assertMsg (
  lib.all (host:
    let casks = map (cask: cask.name) host.homebrew.casks;
    in lib.elem "chatgpt" casks && !(lib.elem "codex-app" casks)
  ) [ forge remilis ]
  && forge.my.apps.chatgpt == remilis.my.apps.chatgpt
  && lib.all (home:
    lib.elem llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex.outPath
      (paths home.home.packages)
  ) [ forgeHome remilisHome ]
) "both hosts must share ChatGPT without Codex.app and retain the llm-agents Codex CLI";
assert lib.assertMsg (
  forge.programs._1password.enable
  && forge.programs._1password.package.outPath == remilis.programs._1password.package.outPath
  && forge.my.apps."1password" == remilis.my.apps."1password"
  && remilis.homebrew.masApps."1Password for Safari" == 1569813296
) "forge01 must share 1Password desktop and CLI while keeping the Safari extension on remilis";
assert lib.assertMsg (
  lib.elem "tailscale-app" (map (cask: cask.name) remilis.homebrew.casks)
  && forge.my.apps.tailscale == remilis.my.apps.tailscale
  && !(forge.services.tailscale.enable or false)
  && !(remilis.services.tailscale.enable or false)
) "both hosts must use the shared Tailscale app without the Nix daemon";
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
  && lib.all (home:
    !(home.home.file ? ".pi/agent/pstack-models.md")
    && !(home.home.file ? ".agents/pstack-src")
    && !(home.programs.agent-skills.sources ? pstack)
    && !(home.programs.agent-skills.skills.explicit ? pstack-dsh)
  ) [ forgeHome remilisHome ]
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
