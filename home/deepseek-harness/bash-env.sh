# Load the project's direnv environment in the non-interactive bash shells the
# harness spawns. `dsh.sh` exports this file as BASH_ENV, which bash reads
# before running its `-c` command — exactly the form the bash tool uses.
#
# bash has no chpwd hook, so directory changes are followed by shadowing the
# `cd` builtin instead: bash resolves a function before a builtin, and every
# `cd`/`pushd`/`popd` in the command (or in the scripts it runs) re-exports.
#
# Two details keep this safe in arbitrary scripts:
#
# - `direnv export` evaluates `.envrc` with bash, which would read BASH_ENV
#   again and recurse forever. `_TOQOZ_DIRENV_GUARD` makes that nested shell
#   skip the hook.
# - The export is skipped when the environment already belongs to `$PWD`, so
#   nested shells and commands that never change directory stay cheap.
if [ -z "${_TOQOZ_DIRENV_GUARD:-}" ] && command -v direnv >/dev/null 2>&1; then
  _toqoz_direnv_refresh() {
    local saved_log_format=${DIRENV_LOG_FORMAT-}
    local had_log_format=${DIRENV_LOG_FORMAT+x}
    export _TOQOZ_DIRENV_GUARD=1
    # The harness reports combined output; keep the per-command
    # "direnv: loading ..." line out of it. Errors keep their own prefix.
    export DIRENV_LOG_FORMAT=
    eval "$(direnv export bash)" || :
    if [ -n "$had_log_format" ]; then
      export DIRENV_LOG_FORMAT=$saved_log_format
    else
      unset DIRENV_LOG_FORMAT
    fi
    unset _TOQOZ_DIRENV_GUARD
  }
  _toqoz_direnv_sync() {
    [ "${_TOQOZ_DIRENV_PWD:-}" = "$PWD" ] && return 0
    _toqoz_direnv_refresh
    export _TOQOZ_DIRENV_PWD=$PWD
  }
  cd() { builtin cd "$@" || return; _toqoz_direnv_sync; }
  pushd() { builtin pushd "$@" || return; _toqoz_direnv_sync; }
  popd() { builtin popd "$@" || return; _toqoz_direnv_sync; }
  _toqoz_direnv_sync
fi
