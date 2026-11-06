{ config, lib, pkgs, llm-agents, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  # Reuse the provider CLIs the rest of the host already installs so T3 Code
  # shares their ~/.codex and ~/.claude logins and settings instead of pulling
  # a second copy of each CLI.
  t3code = llm-agents.packages.${system}.t3code.override {
    providerPackages = [
      llm-agents.packages.${system}.codex
      llm-agents.packages.${system}.claude-code
    ];
  };
  # The desktop output of the same derivation, so the app carries the same
  # version and the same slim provider set as the CLI.
  t3codeDesktop = t3code.desktop;
  servePort =
    if config.my.t3code.server.servePort != null
    then config.my.t3code.server.servePort
    else config.my.t3code.server.port;
  server = rec {
    logDir = "${config.xdg.stateHome}/t3code/log";
    stdout = "${logDir}/stdout.log";
    stderr = "${logDir}/stderr.log";
  };
in
{
  options.my.t3code = {
    enable = lib.mkEnableOption "the T3 Code CLI";

    desktop = {
      enable = lib.mkEnableOption "the T3 Code desktop app";
    };

    server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run `t3 serve` as a user launchd agent.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 3773;
        description = "Loopback port the T3 Code server listens on.";
      };
      servePort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          HTTPS port for the Tailscale Serve listener. Defaults to `port`, so
          the tailnet URL mirrors `http://127.0.0.1:<port>`; set it to keep
          the tailnet port distinct from the loopback one.
        '';
      };
    };
  };

  config = lib.mkIf config.my.t3code.enable {
    home.packages = [ t3code ];

    # macOS only surfaces apps through ~/Applications; a store path on its own
    # is not indexed by LaunchServices. The bundle comes from the same pinned
    # llm-agents revision as the server, so both hosts run one version.
    home.file = lib.mkIf config.my.t3code.desktop.enable {
      "Applications/T3 Code (Beta).app".source =
        "${t3codeDesktop}/Applications/T3 Code (Beta).app";
    };

    # The desktop app refuses to share a T3 home with a server it did not
    # start: it tries to take ownership of ~/.t3 and shows "This T3 home is
    # unavailable" when the service already holds it. Point the app at the
    # service instead by turning off its local environment, which makes it a
    # pure client for the paired environment.
    home.activation.mergeT3CodeDesktopSettings =
      lib.mkIf (config.my.t3code.desktop.enable && config.my.t3code.server.enable)
        (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          export PATH="${lib.makeBinPath [ pkgs.jq ]}:$PATH"

          state="$HOME/.t3/userdata/desktop-settings.json"

          umask 077
          mkdir -p "$(dirname "$state")"
          tmp=$(mktemp "$state.XXXXXX")
          trap 'rm -f "$tmp"' EXIT

          if [ -e "$state" ]; then
            jq '. + {localEnvironmentEnabled: false}' "$state" > "$tmp"
          else
            jq -n '{localEnvironmentEnabled: false}' > "$tmp"
          fi

          mv "$tmp" "$state"
          chmod 600 "$state"
          trap - EXIT
        '');

    # launchd cannot create the log directory, and a symlinked log target would
    # let the service write outside its own state.
    home.activation.prepareT3CodeLogs = lib.mkIf config.my.t3code.server.enable (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ] ''
        run ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg ''
          set -euo pipefail
          umask 077
          state_dir=${lib.escapeShellArg server.logDir}
          fail() {
            echo "t3code: $*" >&2
            exit 1
          }
          [ ! -L "$state_dir" ] || fail "log directory must not be a symlink"
          mkdir -p "$state_dir"
          chmod 700 "$state_dir"
          for log in ${lib.escapeShellArgs [ server.stdout server.stderr ]}; do
            [ ! -L "$log" ] || fail "log must not be a symlink: $log"
            [ ! -e "$log" ] || [ -f "$log" ] || fail "log must be a regular file: $log"
            touch "$log"
            chmod 600 "$log"
          done
        ''}
      ''
    );

    # The server keeps threads alive across terminal sessions and gives the
    # desktop app and outside agents a stable endpoint.
    launchd.agents.t3code = lib.mkIf config.my.t3code.server.enable {
      enable = true;
      domain = "user";
      config = {
        # A resident server should never try to open a browser on login, and
        # Tailscale Serve is the only way the desktop app reaches it from
        # another host. The server still binds 127.0.0.1; Serve proxies the
        # tailnet HTTPS URL to it.
        ProgramArguments = [
          "${t3code}/bin/t3"
          "serve"
          "--no-browser"
          "--tailscale-serve"
          # Publish on `servePort` (the loopback port unless overridden), so
          # the tailnet URL is https://<host>.<tailnet>.ts.net:<servePort>
          # rather than :443.
          "--tailscale-serve-port"
          (toString servePort)
        ];
        WorkingDirectory = config.home.homeDirectory;
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          T3CODE_HOST = "127.0.0.1";
          T3CODE_PORT = toString config.my.t3code.server.port;
          # /usr/local/bin carries the Tailscale.app CLI shim; launchd does
          # not read the shell rc that puts it on PATH, and `t3 serve
          # --tailscale-serve` shells out to `tailscale`.
          PATH = lib.concatStringsSep ":" (config.home.sessionPath ++ [
            "/usr/local/bin"
            "${config.home.profileDirectory}/bin"
            "/run/current-system/sw/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ]);
        };
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        Umask = 63;
        StandardOutPath = server.stdout;
        StandardErrorPath = server.stderr;
      };
    };
  };
}
