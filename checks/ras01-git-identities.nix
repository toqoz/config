# Wiring of ras01's sops-managed Git identities, checked by evaluation: the
# secrets land in the account's context tree, the link script runs as that
# account after the secrets are installed, and the Home Manager side keeps the
# gh config per repository instead of a global one.
{ pkgs, lib, ras01 }:
let
  config = ras01;
  user = config.my.gitIdentities.user;
  home = config.users.users.${user}.home;
  ids = [ "0" "1" "2" "3" ];
  fields = [ "org" "user" "author_name" "author_email" ];
  secret = id: field: config.sops.secrets."git-identity-${id}-${field}";
  template = id: name: config.sops.templates."git-identity-${id}-${name}";
  linkScript = config.system.activationScripts.linkGitIdentities;
  hm = config.home-manager.users.${user};
in
assert lib.assertMsg (user == "nixos" && config.my.gitIdentities.enable)
  "the identities must be enabled for the host's account";
assert lib.assertMsg (config.sops.age.keyFile == "${home}/.config/sops/age/keys.txt")
  "the identities must be decrypted with the account's own age key";
assert lib.assertMsg (
  lib.all
    (id:
      lib.all
        (field:
          let
            s = secret id field;
          in
          s.path == "${home}/.config/nix-contexts/${id}/${field}"
          && s.owner == user
          && s.key == "identities/${id}/github/${field}"
          && s.mode == "0400")
        fields)
    ids
) "every identity field must decrypt into its own context file for the account";
assert lib.assertMsg (
  lib.all (id: (template id "hosts").owner == user && (template id "config").owner == user) ids
) "gh templates must be owned by the account";
assert lib.assertMsg (
  lib.all (id: lib.hasPrefix "/run/secrets/rendered/git-identity-${id}-" (template id "hosts").path) ids
) "gh templates must stay in the sops mount point until the link script copies them";
assert lib.assertMsg (config.system.activationScripts ? setupSecrets)
  "the link script relies on sops installing secrets during activation";
assert lib.assertMsg (
  linkScript.deps == [ "users" "setupSecrets" ]
  && lib.hasInfix "runuser -u ${user} --" linkScript.text
  && lib.hasInfix "link-git-identity.sh" linkScript.text
) "the link script must run as the account after the secrets are installed";
assert lib.assertMsg (hm.xdg.configFile."gh/config.yml".enable == false)
  "the global gh config must stay disabled so GH_CONFIG_DIR selects the identity";
pkgs.runCommand "ras01-git-identities-contract" { } ''
  echo ${lib.escapeShellArgs ids} > "$out"
''
