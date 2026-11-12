# Object storage declarations for ras01. Everything here is public; credentials
# exist only on the host (see nixos/object-storage/README.md).
{
  imports = [ ../../nixos/object-storage ];

  services.objectStorage = {
    enable = true;

    buckets = {
      # Large data, images, and artifacts passed between agents.
      handoff = { };
      # HTML, reports, and other results shown to people.
      published = { };
    };

    policies =
      let
        readWrite = [ "s3:ListBucket" "s3:GetObject" "s3:PutObject" "s3:DeleteObject" ];
      in
      {
        handoff-rw = {
          buckets = [ "handoff" ];
          actions = readWrite;
        };
        published-rw = {
          buckets = [ "published" ];
          actions = readWrite;
        };
      };

    identities = {
      agent = {
        type = "user";
        policies = [ "handoff-rw" ];
      };
      publisher = {
        type = "user";
        policies = [ "published-rw" ];
      };
    };
  };
}
