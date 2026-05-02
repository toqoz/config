{ ... }:
{
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
    };
  };

  programs.git = {
    enable = true;

    # Keep global ignores minimal — repo-specific rules belong in .gitignore
    ignores = [
      # OS
      ".DS_Store"
      "Thumbs.db"
      # Editor
      ".*~"
      "#*#"
      "*.sw[po]"
      # Build
      "*.out"
      # Env
      ".env"
      "*.env$"
      # Claude
      "settings.local.json"
      # Agents tools
      ".agents/cache"
      ".agents/share"
      ".agents/state"
      # Misc
      ".todo.md"
    ];

    settings = {
      user = {
        name = "Takatoshi Matsumoto";
        email = "toqoz403@gmail.com";
      };
      alias = {
        s = "!git stash list && git status -sb";
        dw = "diff --color-words";
        co = "checkout";
        ci = "commit -v";
        fi = "commit -v --fixup HEAD";
        br = "branch";
        wc = "whatchanged";
        unstage = "reset HEAD --";
        # http://qiita.com/uasi/items/f19a120e012c0c75d856
        uncommit = "reset HEAD^";
        recommit = "commit -c ORIG_HEAD";
      };

      core = {
        autocrlf = "input";
        quotepath = false;
        precomposeunicode = true;
        ignorecase = false;
      };

      push.default = "simple";
      grep.lineNumber = true;
      diff.algorithm = "histogram";
      merge.tool = "vimdiff";

      github.user = "ToQoz";
      ghq.root = "~/src";

      # k1LoW/git-wt: place worktrees under <repo>/.git/wt/<branch> so they
      # are inside the workspace (agent reachable), automatically untracked
      # (no .gitignore upkeep), and invisible to greps over the working tree
      # (agents won't accidentally pull worktree contents into context).
      # Relative paths in wt.basedir are resolved from the repo root.
      # ({gitroot} expands to the root *name*, not its path — do not prefix.)
      wt.basedir = ".git/wt";
    };
  };
}
