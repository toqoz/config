# `prefix w`: pick a window across all sessions via fzf, with the cursor
# pre-positioned on the current one. Takes the current
# `<session>:<idx>:` prefix as $1 — tmux substitutes the `#{...}`
# placeholders before the script runs, so the script itself never has to
# know tmux's format vocabulary.
#
# `tmux` and `fzf` are injected so tests can pass fakes.
{ pkgs, tmux, fzf }:
pkgs.writeShellScriptBin "tmux-window-picker" ''
  set -eu
  current_prefix=''${1:?usage: tmux-window-picker <session>:<window>:}
  list=$(${tmux}/bin/tmux list-windows -a \
    -F '#{session_name}:#{window_index}: #{window_name} (#{window_panes} panes)')
  pos=$(printf '%s\n' "$list" \
    | grep -nF -- "$current_prefix" \
    | head -n1 | cut -d: -f1) || true
  printf '%s\n' "$list" \
    | ${fzf}/bin/fzf --sync --ansi --layout reverse --tmux 80%,50% \
        --bind "start:pos(''${pos:-1})" \
    | cut -d: -f1-2 \
    | xargs ${tmux}/bin/tmux switch-client -t
''
