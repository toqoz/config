{ config, lib, ... }:
let
  user = config.system.primaryUser;
  home = config.users.users.${user}.home;
  fields = [ "hostname" "user" "identity_file" ];
  secretName = field: "ssh-dev-${field}";
  placeholder = field: config.sops.placeholder.${secretName field};
in
{
  sops.secrets = lib.genAttrs (map secretName fields) (name: {
    sopsFile = ../ssh.sops.yaml;
    key = "hosts/dev/${lib.removePrefix "ssh-dev-" name}";
    owner = user;
  });
  sops.templates.ssh-config = {
    owner = user;
    path = "${home}/.config/nix-contexts/ssh/config";
    content = ''
      Host dev
        HostName ${placeholder "hostname"}
        User ${placeholder "user"}
        IdentityFile ${placeholder "identity_file"}
        IdentitiesOnly no
    '';
  };
}
