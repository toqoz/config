{ config, pkgs, lib, ... }:
let
  service = {
    port = 3080;
    dataDir = "${config.xdg.dataHome}/deepseek-harness";
  };
  # Single source of truth for the toqoz fork pin and its toolchain.
  # The fork is a personal fork of shiguredo/deepseek-harness that squashes
  # per-feature commits onto `toqoz/main` (currently mobile Enter inserts a
  # newline, and an unauthenticated load offers the launch URL while retrying
  # a withheld-cookie PWA launch once).
  # It has no releases, so the installer clones this revision into a
  # dedicated XDG data checkout at runtime instead of fetching a tarball.
  source = {
    url = "https://github.com/toqoz/deepseek-harness.git";
    rev = "701f13ec19413c811aa2742c1becfa94251de280";
    version = "0.2.2-rc.1"; # root package.json version at rev
  };

  # The runtime's native loader inspects Node machine code and rejects the
  # Nix-built binary. Keep the official binary intact for this application.
  node = pkgs.stdenvNoCC.mkDerivation {
    pname = "deepseek-node";
    version = "24.21.0";
    src = pkgs.fetchurl {
      url = "https://nodejs.org/dist/v24.21.0/node-v24.21.0-darwin-arm64.tar.gz";
      hash = "sha256-vtfupTJeEQjzLOUijd1qXw8IpJnuQqp0Qq6lg3AvYFc=";
    };
    dontFixup = true;
    installPhase = ''
      mkdir -p "$out"
      cp -R bin include lib share "$out/"
    '';
    meta = {
      mainProgram = "node";
      platforms = [ "aarch64-darwin" ];
    };
  };

  # The fork declares packageManager: pnpm@11.28.5; pin the exact npm
  # tarball the way packages/portless.nix does instead of pkgs.pnpm.
  pnpm = pkgs.stdenv.mkDerivation {
    pname = "pnpm";
    version = "11.28.5";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-11.28.5.tgz";
      hash = "sha256-HvTkR6aHE2VgZPPxdMD0RxmWCgQ6P+IpkWnQjPHb+O4=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    unpackPhase = ''
      mkdir -p "$out/lib/node_modules/pnpm"
      tar xzf "$src" --strip-components=1 -C "$out/lib/node_modules/pnpm"
    '';
    installPhase = ''
      mkdir -p "$out/bin"
      makeWrapper ${node}/bin/node "$out/bin/pnpm" \
        --add-flags "$out/lib/node_modules/pnpm/bin/pnpm.mjs"
    '';
    meta.mainProgram = "pnpm";
  };

  vars = {
    inherit (source) url rev version;
    inherit (service) dataDir;
    git = lib.getExe pkgs.git;
    node = lib.getExe node;
    pnpm = lib.getExe pnpm;
    ccPath = lib.makeBinPath [ pkgs.stdenv.cc ];
  };

  package = pkgs.stdenv.mkDerivation {
    pname = "deepseek-harness";
    inherit (source) version;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m 755 ${pkgs.replaceVars ./install.sh vars} "$out/bin/deepseek-harness-install"
      install -m 755 ${pkgs.replaceVars ./dsh.sh { inherit (vars) node rev dataDir; }} "$out/bin/dsh"
      install -m 755 ${pkgs.replaceVars ./service.sh {
        inherit (service) dataDir;
        port = toString service.port;
        tailscaleServe = pkgs.callPackage ../../packages/tailscale-serve.nix { };
      }} "$out/bin/deepseek-harness-service"
      runHook postInstall
    '';
    meta = {
      description = "Pinned toqoz/deepseek-harness Web CLI installer and dsh launcher";
      mainProgram = "dsh";
    };
  };
in
{
  home.packages = [ package ];

  home.activation.installDeepseekHarness = lib.hm.dag.entryBetween
    [ "setupLaunchAgents" ] [ "writeBoundary" "linkGeneration" ] ''
      (
        umask 077
        run mkdir -p ${lib.escapeShellArgs [ service.dataDir "${service.dataDir}/state" "${service.dataDir}/log" ]}
        run chmod 700 ${lib.escapeShellArgs [ service.dataDir "${service.dataDir}/state" "${service.dataDir}/log" ]}
        run touch ${lib.escapeShellArgs [ "${service.dataDir}/log/stdout.log" "${service.dataDir}/log/stderr.log" ]}
        run chmod 600 ${lib.escapeShellArgs [ "${service.dataDir}/log/stdout.log" "${service.dataDir}/log/stderr.log" ]}
        run env DEEPSEEK_HARNESS_HOME=${lib.escapeShellArg service.dataDir} ${package}/bin/deepseek-harness-install
      )
    '';

  launchd.agents.deepseek-harness = {
    enable = true;
    # The `user` domain runs in a Background session, which cannot unlock the
    # login keychain, so keychain-backed tools (gh's token, git's credential
    # helper) fail with errSecInteractionNotAllowed. The `gui` domain runs in
    # the Aqua session, where the keychain is unlocked while the user is
    # logged in. A true logout stops the service; screen lock does not.
    domain = "gui";
    config = {
      ProgramArguments = [ "${package}/bin/deepseek-harness-service" ];
      WorkingDirectory = config.home.homeDirectory;
      EnvironmentVariables.PATH = lib.concatStringsSep ":" (config.home.sessionPath ++ [
        "${config.home.profileDirectory}/bin"
        "/run/current-system/sw/bin"
        "/usr/bin" "/bin" "/usr/sbin" "/sbin"
      ]);
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      Umask = 63;
      StandardOutPath = "${service.dataDir}/log/stdout.log";
      StandardErrorPath = "${service.dataDir}/log/stderr.log";
    };
  };
}
