{
  pkgs,
  llm-agents,
  sence,
  gws,
  herdr,
  ...
}:
{
  my.unfreePackages = [ "slack" "ntn" ];

  # General-purpose CLI tools and third-party packages without a dedicated
  # module. Tool-specific installs live with their owning module (e.g.
  # `pkgs.tmux` in `tmux.nix`) to keep each module self-contained.
  home.file.".npmrc".text = ''
    registry=https://npm.flatt.tech/
  '';

  xdg.configFile."pnpm/config.yaml".text = ''
    registry: https://npm.flatt.tech/
    minimumReleaseAge: 4320
  '';

  home.packages = with pkgs; [
    mkcert
    openssh
    wget
    oha
    tig
    ghq
    lazygit
    ripgrep
    fd
    bun
    deno
    pnpm
    zig
    mariadb.client
    # fonttools CLI (pyftsubset, ttx, fonttools, ...). brotli is an optional
    # dependency required for WOFF2 read/write.
    (python3.withPackages (ps: with ps; [ fonttools brotli ]))
    git-wt
    (callPackage ../packages/tcmux.nix { })
    # The wrapper at packages/fence.nix layers worktree-aware allowWrite paths
    # onto the real binary so non-zsh callers (e.g. `sence`) get them too.
    (callPackage ../packages/fence.nix { })
    slack
    (callPackage ../packages/portless.nix { })
    (callPackage ../packages/ntn.nix { })
    (callPackage ../packages/orca.nix { })
    (callPackage ../packages/jrf.nix { })
    (callPackage ../packages/ketch.nix { })
    (callPackage ../packages/vite-plus.nix { })
    sence.packages.${pkgs.stdenv.hostPlatform.system}.default
    gws.packages.${pkgs.stdenv.hostPlatform.system}.default
    herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ccusage
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
  ];
}
