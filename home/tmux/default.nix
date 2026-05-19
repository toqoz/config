{ pkgs, ... }:

let
  tcmux = pkgs.callPackage ../../packages/tcmux.nix { };

  windowPicker = import ./scripts/window-picker.nix {
    inherit pkgs tcmux;
    tmux = pkgs.tmux;
    fzf = pkgs.fzf;
  };
  swapWindow = import ./scripts/swap-window.nix {
    inherit pkgs;
    tmux = pkgs.tmux;
  };
  tagWindow = import ./scripts/window-tag.nix {
    inherit pkgs;
    tmux = pkgs.tmux;
  };
in
{
  home.packages = [
    windowPicker
    swapWindow
    tagWindow
  ];

  programs.tmux = {
    enable = true;
    extraConfig = ''
      set-option -g prefix C-t
      unbind C-b

      set-option -g escape-time 0
      set-option -g set-clipboard on
      set-option -g set-titles on
      set-option -g mouse on

      # Forward extended key sequences (CSI u) so terminals that support
      # them can distinguish C-i from Tab, C-m from Enter, C-Shift-letter,
      # etc. Requires a terminal that advertises the `extkeys` feature.
      set-option -s extended-keys on
      set -g extended-keys-format csi-u
      set-option -as terminal-features 'xterm*:extkeys'

      # When the last pane in a session is killed, switch the client to
      # another session instead of detaching.
      set-option -g detach-on-destroy off

      # Appearance {{{
      set -g status-position top
      set -g status-style fg=white,bg=black,dim
      set -g status-left-length 32
      set -g status-right-length 150

      set -g pane-border-style fg='#6b5060'
      set -g pane-active-border-style fg='#f5c2e7'
      # Draw arrows on the active pane's borders in addition to the colour change,
      # so the active pane is obvious without touching pane contents (keeps the
      # terminal background transparency intact).
      set -g pane-border-indicators both

      set -g window-status-format " #I #W "
      set -g window-status-current-format "#[fg=black,bg=white] [*#I] #W "
      set -g window-status-style fg=white,bg=black
      set -g window-status-current-style fg=green,bg=black
      set -g window-status-last-style fg=blue

      set -g status-right '#{?mouse,[M],}#{?window_zoomed_flag, [Z] ,} > #H#[default]'
      set -g message-style fg=white,bg=red,bold

      set-window-option -g mode-keys vi
      set-window-option -g mode-style fg=black,bg=white
      # }}}

      unbind C-r
      bind C-r source-file ~/.config/tmux/tmux.conf \; display-popup -E -w 40 -h 3 'printf "\n  Configuration reloaded"; sleep 1'

      # Toggle mouse
      unbind m
      bind-key m \
        if-shell 'tmux show-options -g mouse | grep -q off' \
          'set-option -g mouse on' \
          'set-option -g mouse off' \; \
        refresh-client -S

      unbind P
      bind-key P command-prompt -p 'Capture pane and save it as file:' -I '~/.tmux.capture' 'capture-pane -S -32768 ; save-buffer %1 ; delete-buffer'

      # Window keybindings {{{
      # New
      unbind c
      bind c new-window

      # Split
      unbind |
      bind | split-window -h -c "#{pane_current_path}"
      unbind -
      bind - split-window -v -c "#{pane_current_path}"
      bind 'c' new-window -c "#{pane_current_path}"

      # Swap
      # http://toqoz.hateblo.jp/entry/2013/10/12/025544
      set-option -g renumber-windows on
      unbind H
      bind -r H run-shell "${swapWindow}/bin/tmux-swap-window left"
      unbind L
      bind -r L run-shell "${swapWindow}/bin/tmux-swap-window right"

      # Resize
      # @option -r: is enable to repeat
      unbind C-h
      bind -r C-h resize-pane -L 6
      unbind C-l
      bind -r C-l resize-pane -R 6
      unbind C-j
      bind -r C-j resize-pane -D 6
      unbind C-k
      bind -r C-k resize-pane -U 6
      # }}}

      bind w run-shell "${windowPicker}/bin/tmux-window-picker '#{session_name}:#{window_index}:'"

      # <prefix> g — pick a ghq repo via fzf in a popup and switch the
      # client to its session. Works while vim/claude/etc. are running
      # in the foreground pane (zle widgets cannot).
      bind g display-popup -E -w 80% -h 60% tmux-ghq-popup

      # Chord prefix: <prefix> s -> status table (mark windows)
      unbind s
      bind s switch-client -T status
      # <prefix> s d -> prefix window name with [done]
      bind -T status d run-shell "${tagWindow}/bin/tmux-window-tag done"
      # <prefix> s b -> prefix window name with [back later]
      bind -T status b run-shell "${tagWindow}/bin/tmux-window-tag 'back later'"

      # Pane keybindings {{{
      # Move pane like Vim
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Kill
      unbind K
      bind K confirm-before -p "Kill this WINDOW? (y/n)" kill-window
      unbind Q
      bind Q confirm-before -p "Kill this SESSION? (y/n)" kill-session
      unbind P
      bind P confirm-before -p "Kill this PANE? (y/n)" kill-pane

      # Cut off target-pane from window including this, then be single pane in new window.
      unbind 1
      bind 1 break-pane
      # }}}

      # Copy mode settings {{{
      unbind y
      bind y copy-mode
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel "pbcopy"
      unbind p
      bind p paste-buffer
      # }}}
    '';
  };
}
