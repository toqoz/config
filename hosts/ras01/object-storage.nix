# Public declarations only. Each host uses its own separately delivered key.
{ lib, ... }:
let
  buckets = [ "handoff" "published" ];
  hosts = [ "remilis" "forge01" "ras01" "grokbot" ];
  readAll = {
    inherit buckets;
    actions = [ "s3:ListAllMyBuckets" "s3:ListBucket" "s3:GetObject" "s3:ListBucketMultipartUploads" ];
  };
in
{
  imports = [ ../../nixos/object-storage ];

  services.objectStorage = {
    enable = true;
    buckets = lib.genAttrs buckets (_: { });

    policies = {
      read-all = readAll;
      # Keep old policy names so reconcile replaces their previous write grants.
      handoff-rw = readAll;
      published-rw = readAll;
    } // lib.listToAttrs (map (host: lib.nameValuePair "${host}-write" {
        inherit buckets;
        prefixes = [ "${host}/" ];
        actions = [
          "s3:PutObject"
          "s3:DeleteObject"
          "s3:AbortMultipartUpload"
          "s3:ListMultipartUploadParts"
        ];
      }) hosts);

    identities = {
      # Shared credentials remain valid for reads while hosts move to their keys.
      agent = { type = "user"; policies = [ "handoff-rw" ]; };
      publisher = { type = "user"; policies = [ "published-rw" ]; };
    } // lib.genAttrs hosts (host: {
      type = "user";
      policies = [ "read-all" "${host}-write" ];
    });
  };
}
