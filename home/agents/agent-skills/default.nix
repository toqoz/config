{ lib, pkgs, vercel-agent-browser, makenotion-skills, ... }:
let
  modern-web-guidance = pkgs.callPackage ../../../packages/modern-web-guidance.nix { };
  modernWebGuidanceBin = "${modern-web-guidance}/bin/modern-web-guidance";
  injectAfterFrontmatter = note: content:
    let
      parts = lib.splitString "\n---\n" content;
    in
    if builtins.length parts >= 2 then
      (builtins.head parts)
      + "\n---\n\n"
      + note
      + "\n"
      + lib.concatStringsSep "\n---\n" (builtins.tail parts)
    else
      note + "\n\n" + content;
  modernWebGuidanceTransform = { original, dependencies }:
    let
      nixUsage = ''
## Local Nix Usage Override

Use this Nix-pinned command instead of `npx`:

```sh
${modernWebGuidanceBin} <command> [args...]
```

The package and its model/assets are pinned by Nix, so do not install or fetch it with `npx`.

'';
      rewritten = builtins.replaceStrings [
        "npx -y modern-web-guidance@latest"
        "npx -y modern-web-guidance…"
        "npx.cmd"
        "npx --offline"
        "## Using npx"
        "Run `modern-web-guidance` directly with `npx`."
        "using `npx`"
        "with `npx`"
      ] [
        modernWebGuidanceBin
        modernWebGuidanceBin
        modernWebGuidanceBin
        modernWebGuidanceBin
        "## Using the Nix-pinned command"
        "Run the Nix-pinned command shown in the local override above."
        "using the Nix-pinned command"
        "with the Nix-pinned command"
      ] original;
    in
    injectAfterFrontmatter nixUsage rewritten;
in
{
  imports = [ ./anthropic.nix ];

  programs.agent-skills = {
    enable = true;
    sources = {
      local = {
        path = ../skills;
        filter.maxDepth = 1;
      };
      vercel = {
        path = vercel-agent-browser;
        subdir = "skills";
      };
      makenotion = {
        path = makenotion-skills;
        subdir = "skills";
      };
      googlechrome-modern-web-guidance = {
        path = "${modern-web-guidance}/lib/modern-web-guidance";
        subdir = "skills";
      };
    };
    skills = {
      enableAll = [
        "local"
        "vercel"
        "makenotion"
      ];
      explicit.modern-web-guidance = {
        from = "googlechrome-modern-web-guidance";
        path = "modern-web-guidance";
        transform = modernWebGuidanceTransform;
      };
    };
    targets.agents.enable = true;
    targets.claude.enable = true;
  };
}
