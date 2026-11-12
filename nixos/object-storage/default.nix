# S3-compatible object storage: VersityGW (POSIX backend) with its Standalone IAM
# service. Buckets, IAM identities, and inline policies are declared here and
# converged by versitygw-reconcile. Every credential lives only on the host:
# the root account is generated there once, and access keys are issued
# explicitly with provision-s3-credential. See ./README.md for operations.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.objectStorage;
  inherit (lib) mkOption types;

  rootDir = "/var/lib/versitygw-root";
  rootCredentials = "${rootDir}/root-credentials";
  socket = "/run/versitygw/iam.sock";
  iamEndpoint = "http://127.0.0.1:${toString cfg.iamPort}";
  s3Endpoint = "http://127.0.0.1:${toString cfg.s3Port}";
  managedPath = "/nix-managed/";
  # Reserved managed IAM user that creates buckets. The gateway's own root is
  # unusable (see with-root-credentials --gateway), so bucket creation goes through
  # IAM like every other S3 request. Its only access key lives for one reconcile run.
  bucketCreator = "versitygw-reconcile";
  bucketCreatorPolicies = {
    buckets = {
      Version = "2012-10-17";
      Statement = [
        {
          Effect = "Allow";
          Action = [ "s3:CreateBucket" ];
          Resource = map (b: "arn:aws:s3:::${b}") (lib.attrNames cfg.buckets);
        }
        {
          Effect = "Allow";
          Action = [ "s3:ListAllMyBuckets" ];
          Resource = [ "arn:aws:s3:::*" ];
        }
      ];
    };
  };
  policyBytes = policies: lib.foldl' (n: doc: n + lib.stringLength (builtins.toJSON doc)) 0 (lib.attrValues policies);

  policyDocument = policy: {
    Version = "2012-10-17";
    Statement = [{
      Effect = "Allow";
      Action = policy.actions;
      Resource = lib.concatMap (b: [ "arn:aws:s3:::${b}" "arn:aws:s3:::${b}/*" ]) policy.buckets;
    }];
  };
  inlinePolicies = identity: lib.genAttrs identity.policies (name: policyDocument cfg.policies.${name});
  identitiesOfType = type: lib.filterAttrs (_: identity: identity.type == type) cfg.identities;

  desired = {
    inherit managedPath bucketCreator;
    buckets = lib.attrNames cfg.buckets;
    users = lib.mapAttrs (_: identity: { policies = inlinePolicies identity; }) (identitiesOfType "user")
      // { ${bucketCreator}.policies = bucketCreatorPolicies; };
    roles = lib.mapAttrs
      (_: identity: {
        inherit (identity) assumeRolePolicy;
        policies = inlinePolicies identity;
      })
      (identitiesOfType "role");
  };
  desiredFile = pkgs.writeText "object-storage-desired.json" (builtins.toJSON cfg.desiredState);

  script = name: runtimeInputs: env: pkgs.writeShellApplication {
    inherit name runtimeInputs;
    text = lib.concatMapStrings (n: "export ${n}=${lib.escapeShellArg env.${n}}\n") (lib.attrNames env)
      + builtins.readFile ./${name}.sh;
  };
  withRootCredentials = script "with-root-credentials" [ pkgs.coreutils ] { };
  rootCredentialsScript = script "root-credentials" [ pkgs.coreutils pkgs.gnused ] { };
  reconcile = script "reconcile" [ pkgs.awscli2 pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnugrep ] {
    VGW_IAM_ENDPOINT = iamEndpoint;
    VGW_S3_ENDPOINT = s3Endpoint;
  };
  # Operator entry point: the same reconcile against the deployed declarations,
  # e.g. `sudo versitygw-reconcile --dry-run`.
  reconcileCli = pkgs.writeShellApplication {
    name = "versitygw-reconcile";
    text = ''
      export VGW_ROOT_CREDENTIALS=${rootCredentials}
      exec ${lib.getExe reconcile} "$@" ${desiredFile}
    '';
  };
  provisionCredential = script "provision-s3-credential" [ pkgs.awscli2 pkgs.jq pkgs.coreutils pkgs.gnused ] {
    VGW_IAM_ENDPOINT = iamEndpoint;
    VGW_ROOT_CREDENTIALS = rootCredentials;
  };
  backup = script "versitygw-backup" [ pkgs.gnutar pkgs.gzip pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.jq pkgs.curl pkgs.awscli2 ] {
    VGW_IAM_ENDPOINT = iamEndpoint;
    VGW_S3_ENDPOINT = s3Endpoint;
    VGW_ROOT_OWNER = "root:root";
    VGW_IAM_OWNER = "versitygw-iam:versitygw-iam";
    VGW_GATEWAY_OWNER = "versitygw:versitygw";
  };

  # Shared by the long-running services; each unit adds what it needs on top.
  hardening = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" "~@privileged" ];
    SystemCallErrorNumber = "EPERM";
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    UMask = "0077";
  };

  bucketName = types.strMatching "[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]";
  identityName = types.strMatching "[A-Za-z0-9+=,.@_-]{1,64}";
in
{
  options.services.objectStorage = {
    enable = lib.mkEnableOption "VersityGW S3 object storage with Standalone IAM";

    package = lib.mkPackageOption pkgs "versitygw" { };

    s3Port = mkOption {
      type = types.port;
      default = 7070;
      description = "S3 API port. Reachable only through `tailnetInterface` and loopback.";
    };

    iamPort = mkOption {
      type = types.port;
      default = 7071;
      description = "IAM API port, bound to 127.0.0.1 only.";
    };

    tailnetInterface = mkOption {
      type = types.str;
      default = "tailscale0";
      description = "The only non-loopback interface the firewall opens the S3 port on.";
    };

    buckets = mkOption {
      type = types.attrsOf (types.submodule { });
      default = { };
      description = "Buckets to create. Undeclared buckets are kept.";
    };

    policies = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          buckets = mkOption { type = types.nonEmptyListOf bucketName; };
          actions = mkOption { type = types.nonEmptyListOf (types.strMatching "s3:[A-Za-z*]+"); };
        };
      });
      default = { };
      description = ''
        Reusable policies. Standalone IAM has no managed policies, so each one is
        written as an inline policy of every identity that lists it.
      '';
    };

    desiredState = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      internal = true;
      default = desired;
      description = "The document versitygw-reconcile converges to; exposed for tests.";
    };

    identities = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          type = mkOption { type = types.enum [ "user" "role" ]; };
          policies = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          assumeRolePolicy = mkOption {
            type = types.nullOr (types.attrsOf types.anything);
            default = null;
            description = "Trust policy document, required for roles.";
          };
        };
      });
      default = { };
      description = "IAM users and roles. Access keys are managed with provision-s3-credential.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      let
        names = lib.attrNames;
      in
      [
        {
          assertion = config.networking.firewall.enable;
          message = "services.objectStorage relies on the firewall to keep the S3 port off non-tailnet interfaces.";
        }
        {
          assertion = !(cfg.identities ? ${bucketCreator});
          message = "services.objectStorage.identities.${bucketCreator} is reserved for bucket creation by versitygw-reconcile.";
        }
        {
          assertion = policyBytes bucketCreatorPolicies <= 2048;
          message = "services.objectStorage: too many buckets for the ${bucketCreator} inline policy (2048-byte IAM limit).";
        }
      ]
      ++ lib.mapAttrsToList
        (name: identity: {
          assertion = lib.all (p: cfg.policies ? ${p}) identity.policies;
          message = "services.objectStorage.identities.${name} lists an undeclared policy.";
        })
        cfg.identities
      ++ lib.mapAttrsToList
        (name: identity: {
          assertion = (identity.type == "role") == (identity.assumeRolePolicy != null);
          message = "services.objectStorage.identities.${name}: roles need assumeRolePolicy and users must not set it.";
        })
        cfg.identities
      ++ lib.mapAttrsToList
        (name: identity:
          let
            # Standalone IAM caps the inline policies of one identity in total.
            limit = if identity.type == "user" then 2048 else 10240;
          in
          {
            assertion = lib.all (p: cfg.policies ? ${p}) identity.policies
              -> policyBytes (inlinePolicies identity) <= limit;
            message = "services.objectStorage.identities.${name}: inline policies exceed the ${toString limit}-byte IAM limit for a ${identity.type}.";
          })
        cfg.identities
      ++ lib.mapAttrsToList
        (name: policy: {
          assertion = lib.all (b: lib.elem b (names cfg.buckets)) policy.buckets;
          message = "services.objectStorage.policies.${name} refers to an undeclared bucket.";
        })
        cfg.policies;

    users.users.versitygw-iam = {
      isSystemUser = true;
      group = "versitygw-iam";
    };
    users.groups.versitygw-iam = { };
    users.users.versitygw = {
      isSystemUser = true;
      group = "versitygw";
      # The IAM private socket is 0660 versitygw-iam:versitygw-iam.
      extraGroups = [ "versitygw-iam" ];
    };
    users.groups.versitygw = { };

    environment.systemPackages = [ provisionCredential backup reconcileCli ];

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.s3Port ];

    systemd.services.versitygw-root-credentials = {
      description = "Create the VersityGW root account once";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe rootCredentialsScript} ${rootDir}";
        UMask = "0077";
        StateDirectory = "versitygw-root";
        StateDirectoryMode = "0700";
        PrivateNetwork = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    systemd.services.versitygw-iam = {
      description = "VersityGW Standalone IAM";
      wantedBy = [ "multi-user.target" ];
      requires = [ "versitygw-root-credentials.service" ];
      after = [ "versitygw-root-credentials.service" ];
      serviceConfig = hardening // {
        Type = "simple";
        User = "versitygw-iam";
        Group = "versitygw-iam";
        StateDirectory = "versitygw/iam";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "versitygw";
        RuntimeDirectoryMode = "0750";
        LoadCredential = [ "root-credentials:${rootCredentials}" ];
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe withRootCredentials)
          (lib.getExe cfg.package)
          "--port 127.0.0.1:${toString cfg.iamPort}"
          "--health /health"
          "iam"
          "--dir /var/lib/versitygw/iam"
          "--private-ports ${socket}"
          "--private-socket-perm 0660"
        ];
        Restart = "on-failure";
        RestartSec = 2;
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
      };
    };

    systemd.services.versitygw = {
      description = "VersityGW S3 gateway (POSIX backend)";
      wantedBy = [ "multi-user.target" ];
      # The gateway authenticates every new S3 request through IAM (its own root
      # secret is random and unknown), so new requests fail while IAM is stopped,
      # dead, or hung. Transfers already authorized by IAM may finish.
      wants = [ "versitygw-iam.service" ];
      after = [ "versitygw-iam.service" "network.target" ];
      serviceConfig = hardening // {
        Type = "simple";
        User = "versitygw";
        Group = "versitygw";
        StateDirectory = "versitygw/data";
        StateDirectoryMode = "0700";
        LoadCredential = [ "root-credentials:${rootCredentials}" ];
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe withRootCredentials)
          "--gateway"
          (lib.getExe cfg.package)
          "--port :${toString cfg.s3Port}"
          "--health /health"
          "--iam-standalone-endpoint ${socket}"
          # 1.9.0 never caches standalone IAM lookups; newer releases do unless this
          # is set, which would let a revoked key work until the cache expires.
          "--iam-cache-disable"
          "posix"
          "/var/lib/versitygw/data"
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    systemd.services.versitygw-reconcile = {
      description = "Converge declared VersityGW IAM identities, policies, and buckets";
      wantedBy = [ "multi-user.target" ];
      # Wants, not Requires: a gateway restart must not take this unit down with it.
      wants = [ "versitygw-iam.service" "versitygw.service" ];
      after = [ "versitygw-iam.service" "versitygw.service" ];
      environment = {
        VGW_ROOT_CREDENTIALS = "%d/root-credentials";
        # awscli needs a writable HOME.
        HOME = "/tmp";
      };
      serviceConfig = hardening // {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
        LoadCredential = [ "root-credentials:${rootCredentials}" ];
        # The desired-state path is part of the unit, so changing a declaration
        # restarts this unit on switch.
        ExecStart = "${lib.getExe reconcile} ${desiredFile}";
        # awscli is Python and may need W+X pages.
        MemoryDenyWriteExecute = false;
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
      };
    };
  };
}
