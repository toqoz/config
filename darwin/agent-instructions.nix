{ config, lib, ... }:
let
  user = config.system.primaryUser;
  home = config.users.users.${user}.home;
  ids = [ "0" "1" ];
  secretName = id: "figma-profile-${id}-name";
  org = id: config.sops.placeholder."git-identity-${id}-org";
in
{
  sops.secrets = lib.genAttrs (map secretName ids) (name: {
    sopsFile = ../figma.sops.yaml;
    key = "profiles/${lib.removeSuffix "-name" (lib.removePrefix "figma-profile-" name)}/name";
    owner = user;
  });

  sops.templates.agent-instructions = {
    owner = user;
    path = "${home}/.config/nix-contexts/agent-instructions/AGENTS.md";
    content = builtins.readFile ../home/agents/AGENTS.md + ''

      ## Figma Accounts

      ${lib.concatMapStringsSep "\n" (id: "- Figma_${id}: ${config.sops.placeholder.${secretName id}}") ids}

      For Figma operations, select the MCP server for the project's GitHub
      organization. Use Figma_0 for `${org "0"}` and `${org "1"}`, and
      Figma_1 for `${org "2"}`. Use Figma_0 by default for other projects.
    '';
  };
}
