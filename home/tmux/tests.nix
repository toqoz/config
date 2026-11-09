# Nix-level tests for the tmux helper scripts. Auto-discovered by
# `flake.nix` and exposed under `checks.<system>.tmux-<key>`.
#
# Each fake (`tmux`, `fzf`) is its own `writeShellScriptBin` and
# is injected into the script-under-test via the script's Nix function
# args. Every fake call is appended (prefixed with the tool name) to a
# unified log at `$TMUX_FAKE_LOG`; tests assert the *exact* expected
# call sequence with `diff`, so any unexpected invocation fails the
# test.
{ pkgs }:

let
  # `tmux` fake. `display-message -p '#I'` echoes the configured index;
  # everything else is recorded only.
  fakeTmux = pkgs.writeShellScriptBin "tmux" ''
    log=''${TMUX_FAKE_LOG:?TMUX_FAKE_LOG must be set}
    printf 'tmux %s\n' "$*" >> "$log"
    case "$1" in
      list-windows) cat "''${TMUX_FAKE_OUTPUT:?TMUX_FAKE_OUTPUT must be set}" ;;
      display-message)
        case "''${3:-}" in
          "#I") printf '%s\n' "''${TMUX_FAKE_INDEX:-0}" ;;
        esac
        ;;
    esac
  '';

  # `fzf` fake: read stdin (so upstream `printf | ...` doesn't blow up)
  # and emit the line indexed by `$FZF_FAKE_PICK` (1-based, default 1).
  fakeFzf = pkgs.writeShellScriptBin "fzf" ''
    log=''${TMUX_FAKE_LOG:?TMUX_FAKE_LOG must be set}
    printf 'fzf %s\n' "$*" >> "$log"
    sed -n "''${FZF_FAKE_PICK:-1}p"
  '';

  swapWindow = import ./scripts/swap-window.nix {
    inherit pkgs;
    tmux = fakeTmux;
  };
  windowPicker = import ./scripts/window-picker.nix {
    inherit pkgs;
    tmux = fakeTmux;
    fzf = fakeFzf;
  };

  mkCheck = name: scriptDrv: body:
    pkgs.runCommand "test-${name}"
      {
        nativeBuildInputs = [ scriptDrv pkgs.diffutils ];
      } ''
      set -eu
      export TMUX_FAKE_LOG="$PWD/calls.log"
      : > "$TMUX_FAKE_LOG"
      ${body}
      touch "$out"
    '';
in
{
  swap-window-usage = mkCheck "swap-window-usage" swapWindow ''
    if tmux-swap-window 2>err.log; then
      echo "expected non-zero exit" >&2
      exit 1
    fi
    grep -q "^usage:" err.log
    [ ! -s "$TMUX_FAKE_LOG" ]
  '';

  swap-window-bad-arg = mkCheck "swap-window-bad-arg" swapWindow ''
    if tmux-swap-window middle 2>err.log; then
      echo "expected non-zero exit" >&2
      exit 1
    fi
    grep -q "^usage:" err.log
    [ ! -s "$TMUX_FAKE_LOG" ]
  '';

  swap-window-left-edge = mkCheck "swap-window-left-edge" swapWindow ''
    export TMUX_FAKE_INDEX=0
    tmux-swap-window left
    diff -u <(printf '%s\n' "tmux display-message -p #I") "$TMUX_FAKE_LOG"
  '';

  swap-window-left-mid = mkCheck "swap-window-left-mid" swapWindow ''
    export TMUX_FAKE_INDEX=3
    tmux-swap-window left
    diff -u <(printf '%s\n' \
      "tmux display-message -p #I" \
      "tmux swap-window -s 3 -t 2") "$TMUX_FAKE_LOG"
  '';

  swap-window-right = mkCheck "swap-window-right" swapWindow ''
    export TMUX_FAKE_INDEX=3
    tmux-swap-window right
    diff -u <(printf '%s\n' \
      "tmux display-message -p #I" \
      "tmux swap-window -s 3 -t 4") "$TMUX_FAKE_LOG"
  '';

  window-picker-usage = mkCheck "window-picker-usage" windowPicker ''
    if tmux-window-picker 2>err.log; then
      echo "expected non-zero exit" >&2
      exit 1
    fi
    grep -q "usage:" err.log
    [ ! -s "$TMUX_FAKE_LOG" ]
  '';

  window-picker-happy = mkCheck "window-picker-happy" windowPicker ''
    cat > tmux-out <<'EOF'
    default:0: foo (1 panes)
    default:1: bar (2 panes)
    default:2: baz (1 panes)
    EOF
    export TMUX_FAKE_OUTPUT="$PWD/tmux-out"
    export FZF_FAKE_PICK=2
    tmux-window-picker 'default:1:'
    diff -u <(printf '%s\n' \
      "tmux list-windows -a -F #{session_name}:#{window_index}: #{window_name} (#{window_panes} panes)" \
      "fzf --sync --ansi --layout reverse --tmux 80%,50% --bind start:pos(2)" \
      "tmux switch-client -t default:1") "$TMUX_FAKE_LOG"
  '';

  # No prefix match → pos is empty → fzf gets pos(1).
  window-picker-no-current-match = mkCheck "window-picker-no-current-match" windowPicker ''
    cat > tmux-out <<'EOF'
    default:0: foo (1 panes)
    default:1: bar (1 panes)
    EOF
    export TMUX_FAKE_OUTPUT="$PWD/tmux-out"
    export FZF_FAKE_PICK=1
    tmux-window-picker 'other:9:'
    diff -u <(printf '%s\n' \
      "tmux list-windows -a -F #{session_name}:#{window_index}: #{window_name} (#{window_panes} panes)" \
      "fzf --sync --ansi --layout reverse --tmux 80%,50% --bind start:pos(1)" \
      "tmux switch-client -t default:0") "$TMUX_FAKE_LOG"
  '';
}
