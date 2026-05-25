{ pkgs, ... }:
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
    # `git -C <repo>` changes Git's working directory, but it does not reload
    # direnv for that target repo. When a shell already carries another repo's
    # direnv-managed Git identity, author/committer metadata can leak into the
    # target repo. Route -C invocations through `direnv exec <repo>` so Git sees
    # the environment that belongs to the repository it is operating on.
    package = pkgs.writeShellScriptBin "git" ''
      real_git=${pkgs.git}/bin/git

      if [ -n "''${GIT_WRAPPER_NO_DIRENV:-}" ]; then
        exec "$real_git" "$@"
      fi

      dir=
      next_is_c=0
      for arg in "$@"; do
        if [ "$next_is_c" = 1 ]; then
          if [ "''${arg#/}" != "$arg" ]; then
            dir=$arg
          elif [ -n "$dir" ]; then
            dir=$dir/$arg
          else
            dir=$PWD/$arg
          fi
          next_is_c=0
          continue
        fi

        if [ "$arg" = "-C" ]; then
          next_is_c=1
        fi
      done

      if [ -n "$dir" ] && command -v direnv >/dev/null 2>&1; then
        current_dir=$(pwd -P)
        target_dir=$(cd "$dir" 2>/dev/null && pwd -P)
        if [ -n "$target_dir" ] && [ "$target_dir" != "$current_dir" ]; then
          exec direnv exec "$dir" "$real_git" "$@"
        fi
      fi

      exec "$real_git" "$@"
    '';


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
