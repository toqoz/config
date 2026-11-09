if [[ ! -o interactive && -n ${T3CODE_THREAD_ID:-} ]]; then
  function _t3_direnv_export() {
    eval "$(direnv export zsh)"
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _t3_direnv_export
  _t3_direnv_export
fi
