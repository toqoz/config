{ vercel-agent-browser, makenotion-skills, ... }:
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
    };
    skills.enableAll = [
      "local"
      "vercel"
      "makenotion"
    ];
    targets.agents.enable = true;
    targets.claude.enable = true;
  };
}
