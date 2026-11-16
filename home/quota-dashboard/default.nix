{ config, lib, pkgs, ... }:
let
  cfg = config.my.quotaDashboard;
  stateDir = "${config.xdg.stateHome}/quota-dashboard";
  dataDir = "${config.xdg.dataHome}/quota-dashboard";

  compose = pkgs.writeText "quota-dashboard-compose.yaml" ''
    services:
      otel-lgtm:
        image: ${cfg.stack.image}
        container_name: quota-otel-lgtm
        restart: unless-stopped
        ports:
          - "0.0.0.0:${toString cfg.stack.grafanaPort}:3000"
          - "0.0.0.0:${toString cfg.stack.otlpGrpcPort}:4317"
          - "0.0.0.0:${toString cfg.stack.otlpHttpPort}:4318"
        environment:
          - PROMETHEUS_EXTRA_ARGS=--storage.tsdb.retention.time=${cfg.stack.retention}
          # Read-only browsing for anything that can reach the host. Password
          # login is disabled because the admin/admin default would otherwise
          # allow dashboard edits from the local network; dashboards are
          # provisioned from this repository instead.
          - GF_AUTH_ANONYMOUS_ENABLED=true
          - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
          - GF_AUTH_BASIC_ENABLED=false
          - GF_AUTH_DISABLE_LOGIN_FORM=true
        volumes:
          - ${dataDir}/data:/data
          - ${./dashboards}:/otel-lgtm/grafana/dashboards/quota:ro
          - ${./provider.yaml}:/otel-lgtm/grafana/conf/provisioning/dashboards/quota-provider.yaml:ro
  '';

  # OrbStack starts at login, but the Docker socket may not be ready yet when
  # this agent runs, so wait for it before asking compose to converge.
  stackUp = pkgs.writeShellScript "quota-dashboard-stack-up" ''
    set -euo pipefail
    export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
    for _ in $(seq 1 150); do
      if docker info >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    docker compose --project-name quota-dashboard --file ${compose} up --detach --remove-orphans
  '';
in
{
  options.my.quotaDashboard = {
    enable = lib.mkEnableOption "AI subscription quota collection";

    host = lib.mkOption {
      type = lib.types.str;
      description = "`host.name` resource attribute attached to collected metrics.";
    };

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = if cfg.stack.enable then
        "http://127.0.0.1:${toString cfg.stack.otlpHttpPort}/v1/metrics"
      else
        "http://forge01:${toString cfg.stack.otlpHttpPort}/v1/metrics";
      defaultText = lib.literalExpression ''
        if stack.enable then
          "http://127.0.0.1:<stack.otlpHttpPort>/v1/metrics"
        else
          "http://forge01:<stack.otlpHttpPort>/v1/metrics"
      '';
      description = "OTLP/HTTP metrics endpoint the collector posts to.";
    };

    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Seconds between collection passes.";
    };

    stack = {
      enable = lib.mkEnableOption "the local Grafana + otel-lgtm stack";

      image = lib.mkOption {
        type = lib.types.str;
        default = "grafana/otel-lgtm:0.41.0";
        description = "Pinned image tag; `latest` is intentionally not used.";
      };

      grafanaPort = lib.mkOption {
        type = lib.types.port;
        default = 3370;
        description = "Host port for the Grafana UI (also reachable over the tailnet).";
      };

      otlpGrpcPort = lib.mkOption {
        type = lib.types.port;
        default = 43170;
        description = "Host port for OTLP/gRPC (forwarded to the container's 4317).";
      };

      otlpHttpPort = lib.mkOption {
        type = lib.types.port;
        default = 43180;
        description = "Host port for OTLP/HTTP (forwarded to the container's 4318).";
      };

      retention = lib.mkOption {
        type = lib.types.str;
        default = "90d";
        description = "Prometheus retention for the embedded time-series database.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation.prepareQuotaDashboardState = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] (
      ''
        umask 077
        mkdir -p ${lib.escapeShellArg stateDir}
        chmod 700 ${lib.escapeShellArg stateDir}
      ''
      + lib.optionalString cfg.stack.enable ''
        mkdir -p ${lib.escapeShellArg "${dataDir}/data"}
      ''
    );

    launchd.agents.quota-collector = {
      enable = true;
      domain = "gui";
      config = {
        ProgramArguments = [
          "${pkgs.python3}/bin/python3"
          "-B"
          "${./collector.py}"
        ];
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:${config.home.profileDirectory}/bin";
          QUOTA_HOST = cfg.host;
          QUOTA_ENDPOINT = cfg.endpoint;
          QUOTA_STATE_FILE = "${stateDir}/collector-state.json";
          QUOTA_INTERVAL = toString cfg.interval;
        };
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        ProcessType = "Background";
        Umask = 63;
        StandardErrorPath = "${stateDir}/collector.log";
      };
    };

    launchd.agents.quota-otel-lgtm = lib.mkIf cfg.stack.enable {
      enable = true;
      domain = "gui";
      config = {
        ProgramArguments = [ "${stackUp}" ];
        RunAtLoad = true;
        KeepAlive = false;
        # Re-converge periodically so a failed start (OrbStack still booting)
        # recovers without a login, and a removed container comes back.
        StartInterval = 600;
        ThrottleInterval = 60;
        ProcessType = "Background";
        Umask = 63;
        StandardOutPath = "${stateDir}/otel-lgtm.log";
        StandardErrorPath = "${stateDir}/otel-lgtm.log";
      };
    };
  };
}
