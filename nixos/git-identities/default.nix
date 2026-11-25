# Git identities for Linux hosts, mirroring darwin/git-identities.nix. sops
# decrypts each identity into ~/.config/nix-contexts/<id>, and the account's
# repositories under ~/src/github.com/<org> get .gh/.envrc symlinks so direnv
# supplies the author metadata and gh config per repository.
#
# The age key is the account's own key (the one `.sops.yaml` lists as a
# recipient); the system activation reads it as root, so no root-owned copy is
# kept. Only git.sops.yaml is read here: the other secrets are not needed on
# these hosts.
{ config, lib, pkgs, ... }:
let
  cfg = config.my.gitIdentities;
  user = cfg.user;
  userSpec = config.users.users.${user};
  home = userSpec.home;
  root = "${home}/.config/nix-contexts";
  ids = [ "0" "1" "2" "3" ];
  fields = [ "org" "user" "author_name" "author_email" ];
  secretName = id: field: "git-identity-${id}-${field}";
  contextDir = id: "${root}/${id}";
  placeholder = id: field: config.sops.placeholder.${secretName id field};
  linkScript = ../../scripts/link-git-identity.sh;
  runAsUser =
    command:
    "${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg user} -- ${pkgs.coreutils}/bin/env PATH=${
      lib.escapeShellArg "${lib.makeBinPath [ pkgs.coreutils pkgs.bash ]}:/run/current-system/sw/bin"
    } ${command}";
in
{
  options.my.gitIdentities = {
    enable = lib.mkEnableOption "sops-managed Git identities";

    user = lib.mkOption {
      type = lib.types.str;
      description = ''
        Account that owns the decrypted identities and the repository
        credentials. Its age key must already exist at
        `~/.config/sops/age/keys.txt`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.defaultSopsFile = ../../git.sops.yaml;
    sops.age.keyFile = "${home}/.config/sops/age/keys.txt";

    sops.secrets = lib.listToAttrs (lib.concatMap (id: map (field: {
      name = secretName id field;
      value = {
        key = "identities/${id}/github/${field}";
        owner = user;
        path = "${contextDir id}/${field}";
      };
    }) fields) ids);

    # The gh files are copied into the context by the link script rather than
    # written here, because `gh auth login` updates them and a switch must not
    # overwrite the credentials the user just obtained.
    sops.templates =
      lib.listToAttrs
        (lib.concatMap
          (id: [
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
          ])
          ids);

    system.activationScripts.linkGitIdentities = lib.stringAfter [ "users" "setupSecrets" ] (
      lib.concatMapStrings
        (id: ''
          if ! ${pkgs.coreutils}/bin/install -d -o ${lib.escapeShellArg user} -g ${lib.escapeShellArg userSpec.group} -m 700 ${lib.escapeShellArg "${contextDir id}/gh"} ||
             ! ${runAsUser "${pkgs.bash}/bin/bash"} ${linkScript} \
               ${lib.escapeShellArg (contextDir id)} ${lib.escapeShellArg "${home}/src/github.com"} \
               ${lib.escapeShellArg config.sops.templates."git-identity-${id}-hosts".path} \
               ${lib.escapeShellArg config.sops.templates."git-identity-${id}-config".path}; then
            echo "Warning: Git identity ${id} was not installed; resolve the error and reapply." >&2
          fi
        '')
        ids
    );
  };
}
