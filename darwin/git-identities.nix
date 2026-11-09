{ config, lib, pkgs, ... }:
let
  user = config.system.primaryUser;
  home = config.users.users.${user}.home;
  root = "${home}/.config/nix-contexts";
  ids = [ "0" "1" "2" "3" ];
  fields = [ "org" "user" "author_name" "author_email" ];
  secretName = id: field: "git-identity-${id}-${field}";
  contextDir = id: "${root}/${id}";
  placeholder = id: field: config.sops.placeholder.${secretName id field};
in
{
  sops.defaultSopsFile = ../git.sops.yaml;
  sops.age.keyFile = "${home}/.config/sops/age/keys.txt";
  sops.secrets = lib.listToAttrs (lib.concatMap (id: map (field: {
    name = secretName id field;
    value = {
      key = "identities/${id}/github/${field}";
      owner = user;
      path = "${contextDir id}/${field}";
    };
  }) fields) ids);
  sops.templates = lib.listToAttrs (lib.concatMap (id: [
    {
      name = "git-identity-${id}-hosts";
      value = {
        owner = user;
        content = ''
          github.com:
              git_protocol: https
              users:
                  ${placeholder id "user"}:
              user: ${placeholder id "user"}
        '';
      };
    }
    {
      name = "git-identity-${id}-config";
      value = {
        owner = user;
        content = ''
          %YAML 1.1
          ---
          version: '1'
        '';
      };
    }
    {
      name = "git-identity-${id}-envrc";
      value = {
        owner = user;
        path = "${contextDir id}/envrc";
        content = ''
          export GH_CONFIG_DIR="$PWD/.gh"
          export GIT_AUTHOR_NAME='${placeholder id "author_name"}'
          export GIT_AUTHOR_EMAIL='${placeholder id "author_email"}'
          export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
          export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
        '';
      };
    }
  ]) ids);
  system.activationScripts.postActivation.text = lib.mkOrder 1600 (lib.concatMapStrings (id: ''
    if ! /usr/bin/install -d -o ${lib.escapeShellArg user} -g staff -m 700 ${lib.escapeShellArg "${contextDir id}/gh"} ||
       ! /usr/bin/sudo -u ${lib.escapeShellArg user} ${pkgs.bash}/bin/bash ${../scripts/link-git-identity.sh} \
         ${lib.escapeShellArg (contextDir id)} ${lib.escapeShellArg "${home}/src/github.com"} \
         ${lib.escapeShellArg config.sops.templates."git-identity-${id}-hosts".path} \
         ${lib.escapeShellArg config.sops.templates."git-identity-${id}-config".path}; then
      echo "Warning: Git identity ${id} was not installed; resolve the error and reapply." >&2
    fi
  '') ids);
}
