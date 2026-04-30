{
  pkgs,
  llm-agents,
  sence,
  gws,
  ...
}:
{
  my.unfreePackages = [ "slack" ];

  # General-purpose CLI tools and third-party packages without a dedicated
  # module. Tool-specific installs live with their owning module (e.g.
  # `pkgs.tmux` in `tmux.nix`) to keep each module self-contained.
  home.packages = with pkgs; [
    mkcert
    wget
    tig
    ghq
    lazygit
    ripgrep
    fd
    bun
    deno
    mariadb.client
    # nixpkgs ships an older git-wt (0.17.0). The 0.27.0 release added --json
    # output and a deletehook config, both of which the `git-worktrees` skill
    # benefits from. Once nixpkgs catches up to >= 0.27.0, delete this
    # callPackage line and restore plain `git-wt`.
    (callPackage ../packages/git-wt.nix { })
    (callPackage ../packages/tcmux.nix { })
    # The wrapper at packages/fence.nix layers worktree-aware allowWrite paths
    # onto the real binary so non-zsh callers (e.g. `sence`) get them too.
    (callPackage ../packages/fence.nix { })
    slack
    (callPackage ../packages/portless.nix { })
    (callPackage ../packages/mo.nix { })
    (callPackage ../packages/vite-plus.nix { })
    sence.packages.${pkgs.stdenv.hostPlatform.system}.default
    gws.packages.${pkgs.stdenv.hostPlatform.system}.default
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi
  ];
}
