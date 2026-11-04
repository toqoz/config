{ config, lib, pkgs, llm-agents, ... }:
let
  appServer = rec {
    port = 4500;
    stateDir = "${config.xdg.stateHome}/codex-app-server";
    tokenFile = "${stateDir}/capability-token";
    stdout = "${stateDir}/log/stdout.log";
    stderr = "${stateDir}/log/stderr.log";
  };
  codex = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
  tailscaleServe = pkgs.callPackage ../../../packages/tailscale-serve.nix { };
  service = pkgs.writeShellScript "codex-app-server" (lib.replaceStrings
    [ "@tailscaleServe@" "@codex@" "@port@" "@tokenFile@" ]
    [ (toString tailscaleServe) (lib.getExe codex) (toString appServer.port) appServer.tokenFile ]
    (builtins.readFile ./app-server-service.sh));
in
{
  home.activation.prepareCodexAppServer = lib.hm.dag.entryBetween
    [ "setupLaunchAgents" ] [ "linkGeneration" "mergeCodexConfig" ] ''
      run ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg ''
        set -euo pipefail
        umask 077
        export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep ]}
        state_dir=${lib.escapeShellArg appServer.stateDir}
        token_file=${lib.escapeShellArg appServer.tokenFile}
        fail() {
          echo "codex-app-server: $*" >&2
          exit 1
        }
        for dir in "$state_dir" "$state_dir/log"; do
          [ ! -L "$dir" ] || fail "state directory must not be a symlink"
          mkdir -p "$dir"
          chmod 700 "$dir"
        done
        if [ ! -e "$token_file" ] && [ ! -L "$token_file" ]; then
          tmp_token=$(mktemp "$state_dir/.token.XXXXXX")
          trap 'rm -f "$tmp_token"' EXIT
          ${lib.getExe pkgs.openssl} rand -hex 32 > "$tmp_token"
          ln "$tmp_token" "$token_file"
          rm -f "$tmp_token"
          trap - EXIT
        fi
        [ -f "$token_file" ] && [ ! -L "$token_file" ] || fail "token must be a regular file, not a symlink"
        if [ "$(wc -c < "$token_file")" -gt 65 ] || ! LC_ALL=C grep -aExq '[0-9a-f]{64}' "$token_file"; then
          fail "invalid capability token"
        fi
        chmod 600 "$token_file"
        for log in ${lib.escapeShellArgs [ appServer.stdout appServer.stderr ]}; do
          [ ! -L "$log" ] && { [ ! -e "$log" ] || [ -f "$log" ]; } || fail "log must be a regular file, not a symlink"
          touch "$log"
          chmod 600 "$log"
        done
      ''}
    '';

  launchd.agents.codex-app-server = {
    enable = true;
    domain = "user";
    config = {
      ProgramArguments = [ (toString service) ];
      WorkingDirectory = config.home.homeDirectory;
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = lib.concatStringsSep ":" (config.home.sessionPath ++ [
          "${config.home.profileDirectory}/bin"
          "/run/current-system/sw/bin"
          "/usr/bin" "/bin" "/usr/sbin" "/sbin"
        ]);
      };
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      Umask = 63;
      StandardOutPath = appServer.stdout;
      StandardErrorPath = appServer.stderr;
    };
  };
}
