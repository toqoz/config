# Safety contract of ras01's object storage, checked by evaluation: the network
# exposure, how root credentials reach the services, that the gateway's own root
# cannot sign S3 requests, and that each host reads all data but writes only
# beneath its own prefix. The scripts are also built here for darwin so shellcheck runs on them
# without a Linux builder.
{ pkgs, lib, ras01 }:
let
  cfg = ras01.services.objectStorage;
  services = ras01.systemd.services;
  units = [ "versitygw-iam" "versitygw" "versitygw-reconcile" ];
  execStart = name: services.${name}.serviceConfig.ExecStart;
  firewall = ras01.networking.firewall;
  hosts = [ "remilis" "forge01" "ras01" "grokbot" ];
  readResources = [
    "arn:aws:s3:::handoff" "arn:aws:s3:::handoff/*"
    "arn:aws:s3:::published" "arn:aws:s3:::published/*"
  ];
  statements = user: lib.concatMap (doc: doc.Statement)
    (lib.attrValues cfg.desiredState.users.${user}.policies);
  readOnly = statement: lib.all
    (action: lib.elem action [ "s3:ListAllMyBuckets" "s3:ListBucket" "s3:GetObject" "s3:ListBucketMultipartUploads" ])
    statement.Action;
  shellchecked = map
    (name: pkgs.writeShellApplication {
      inherit name;
      text = builtins.readFile ../nixos/object-storage/${name}.sh;
    })
    [ "with-root-credentials" "root-credentials" "reconcile" "provision-s3-credential" "versitygw-backup" ];
in
assert lib.assertMsg (
  lib.hasInfix "--port 127.0.0.1:${toString cfg.iamPort} " (execStart "versitygw-iam")
  && services.versitygw-iam.serviceConfig.IPAddressDeny == "any"
) "the IAM API must listen on loopback only";
assert lib.assertMsg (
  lib.hasInfix "--iam-standalone-endpoint /run/versitygw/iam.sock " (execStart "versitygw")
  && lib.hasInfix "--private-ports /run/versitygw/iam.sock " (execStart "versitygw-iam")
  && lib.hasInfix "--iam-cache-disable " (execStart "versitygw")
) "the gateway must reach IAM over the unix socket and never cache IAM decisions";
assert lib.assertMsg (
  lib.elem "versitygw-iam.service" services.versitygw.wants
  && lib.elem "versitygw-iam.service" services.versitygw.after
  && (services.versitygw.serviceConfig.KillSignal or "SIGTERM") == "SIGTERM"
) "the gateway must start IAM first and preserve upstream graceful shutdown";
assert lib.assertMsg (
  lib.hasInfix "/bin/with-root-credentials --gateway " (execStart "versitygw")
  && lib.hasInfix "/bin/with-root-credentials /" (execStart "versitygw-iam")
) "the gateway must run with an unusable root secret so every S3 request is authenticated by IAM";
assert lib.assertMsg (
  firewall.enable
  && !(lib.elem cfg.s3Port firewall.allowedTCPPorts)
  && lib.elem cfg.s3Port firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts
  && lib.all (i: i == cfg.tailnetInterface || !(lib.elem cfg.s3Port firewall.interfaces.${i}.allowedTCPPorts))
    (lib.attrNames firewall.interfaces)
) "the S3 port must be open on the tailnet interface only";
assert lib.assertMsg (
  lib.all
    (name:
      services.${name}.serviceConfig.LoadCredential == [ "root-credentials:/var/lib/versitygw-root/root-credentials" ]
      && !(lib.any (n: lib.hasPrefix "ROOT_" n || lib.hasPrefix "AWS_" n) (lib.attrNames services.${name}.environment))
      && !(services.${name}.serviceConfig ? EnvironmentFile))
    units
) "root credentials must reach services only through LoadCredential";
assert lib.assertMsg (
  lib.all (name: lib.all readOnly (statements name)) [ "agent" "publisher" ]
  && lib.all
    (host:
      let
        policies = cfg.desiredState.users.${host}.policies;
        read = lib.head policies.read-all.Statement;
        write = lib.head policies.${host + "-write"}.Statement;
      in
      readOnly read && read.Resource == readResources
      && lib.elem { Effect = "Allow"; Action = [ "s3:ListAllMyBuckets" ]; Resource = [ "arn:aws:s3:::*" ]; } policies.read-all.Statement
      && write.Resource == [ "arn:aws:s3:::handoff/${host}/*" "arn:aws:s3:::published/${host}/*" ]
      && write.Action == [ "s3:PutObject" "s3:DeleteObject" "s3:AbortMultipartUpload" "s3:ListMultipartUploadParts" ])
    hosts
) "hosts must read all data, write only their own prefixes, and legacy shared users must be read-only";
pkgs.runCommand "ras01-object-storage-contract" { } ''
  echo ${lib.escapeShellArgs shellchecked} > "$out"
''
