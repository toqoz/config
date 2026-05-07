{ config, pkgs, ... }:
{
  home.sessionVariables = {
    Z_DATA_DIR = "${config.xdg.dataHome}/zsh";
    Z_CACHE_DIR = "${config.xdg.cacheHome}/zsh";
  };

  # Autoloaded site-functions: one function per file under functions/.
  # Real .zsh files avoid Nix heredoc escaping (''${...}) and play nicely
  # with editors and shellcheck.
  xdg.configFile."zsh/functions".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.repoPath}/home/zsh/functions";

  programs.zsh = {
    enable = true;
    package = pkgs.emptyDirectory;
    dotDir = "${config.xdg.configHome}/zsh";
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      # Keep extra history in memory for smarter trimming before save.
      size = 200000;
      save = 150000;
      # Store timestamps and durations with history entries.
      extended = true;
      # Drop a command if it is identical to the previous entry.
      ignoreDups = true;
      # When trimming history, remove older duplicate entries first.
      expireDuplicatesFirst = true;
      # Do not record commands that start with a space.
      ignoreSpace = true;
    };
    syntaxHighlighting = {
      enable = true;
    };
    autosuggestion = {
      enable = false;
      strategy = [
        "history"
        "completion"
      ];
    };
    enableCompletion = true; # For autocomplete
    setOptions = [
      "IGNORE_EOF"
      # Remove superfluous blanks before saving a command.
      "HIST_REDUCE_BLANKS"
    ];
    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
        file = "fzf-tab.plugin.zsh";
      }
    ];
    # .zshenv
    envExtra = ''
      source "${pkgs.asdf-vm}/etc/profile.d/asdf-prepare.sh"
      fpath=(${pkgs.asdf-vm}/share/zsh/site-functions ${config.xdg.configHome}/zsh/functions $fpath)

      # Autoload agent wrappers here (not in .zshrc) so git aliases and
      # other non-interactive zsh subshells can resolve them.
      autoload -Uz claude codex op
    '';
    # .zprofile
    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv zsh)"
    '';
    # .zshrc (completion)
    completionInit = ''
      # Show group headers
      zstyle ':completion:*:descriptions' format '[%d]'
      # extact -> case sensitive -> case insensitive → fuzzy
      zstyle ':completion:*' matcher-list ''' 'm:{a-z}={A-Z}' '+m:{A-Z}={a-z}' 'r:|=*' 'l:|=* r:|=*'
      # Disable zsh completion UI
      zstyle ':completion:*' menu no
    '';
    # .zshrc
    initContent = ''
      # fzf-tab
      # Preview for cd
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 $realpath'
      # Show fzf on the first TAB even when matches share a common prefix.
      # Upstream -ftb-complete mirrors zsh's default of inserting the
      # unambiguous prefix first, requiring a second TAB to open fzf.
      functions[-ftb-complete]="''${functions[-ftb-complete]/\(\( ! _ftb_continue_last \)\)/false}"

      autoload -U edit-command-line
      zle -N edit-command-line

      # Never auto-execute on paste; Enter is always required.
      autoload -Uz bracketed-paste-magic
      zle -N bracketed-paste bracketed-paste-magic

      # Site-functions dir already added to fpath in .zshenv.
      autoload -Uz enter-workspace tmux ghq ai-commit ai-commit-all ai-commit-staged git-wt-now
      zle -N enter-workspace

      # C-Space: Start completion
      bindkey '^@' fzf-tab-complete
      # C-g: Use editor to edit command line
      bindkey "^g" edit-command-line
      # C-x g: pick a repo and switch to its tmux session
      bindkey "^xg" enter-workspace
      # Unbind C-t (fzf file widget) so tmux prefix passes through
      bindkey -r '^t'
      # Cmd-r: Redo
      bindkey "^[r" redo # Cmd-r

      # SHARE_HISTORY auto-imports new entries on prompt redraw, which is
      # enough for ↑ history navigation. fzf-history-widget reads the
      # $history parameter, which can lag behind entries appended by
      # sibling tmux panes mid-prompt. Force a re-import right before the
      # widget runs so Ctrl-R always sees the latest.
      function _fzf-history-widget-fresh() {
        fc -RI 2>/dev/null
        zle fzf-history-widget
      }
      zle -N _fzf-history-widget-fresh
      bindkey '^R' _fzf-history-widget-fresh

      # Auto-launch tmux for shells spawned directly by wezterm.
      # Unset first so tmux panes' shells (and any coding agent subshells)
      # don't re-trigger. Only exit on tmux's normal termination (detach);
      # fzf cancel or abnormal exits drop into the prompt.
      if [[ -n "$WEZTERM_AUTORUN" ]]; then
        unset WEZTERM_AUTORUN
        tmux && exit
      fi

      # Starship: skip in sandbox shells (e.g. fence) where the prompt
      # would be wasted. HM's auto integration is disabled in
      # home/starship/default.nix so this branch is the sole source.
      if [[ -n "$FENCE_SANDBOX" ]]; then
        PS1="[sandbox] %~ %# "
        RPROMPT=""
      else
        if [[ $TERM != "dumb" ]]; then
          eval "$(${pkgs.starship}/bin/starship init zsh)"
        fi
      fi
    '';
  };
}
