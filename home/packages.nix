{
  pkgs,
  llm-agents,
  sence,
  herdr,
  ...
}:
{
  # General-purpose CLI tools and third-party packages without a dedicated
  # module. Tool-specific installs live with their owning module (e.g.
  # `pkgs.tmux` in `tmux.nix`) to keep each module self-contained.
  home.packages = with pkgs; [
    mkcert
    oha
    tig
    lazygit
    bun
    deno
    zig
    # fonttools CLI (pyftsubset, ttx, fonttools, ...). brotli is an optional
    # dependency required for WOFF2 read/write.
    (python3.withPackages (ps: with ps; [ fonttools brotli ]))
    (callPackage ../packages/tcmux.nix { })
    # The wrapper at packages/fence.nix layers worktree-aware allowWrite paths
    # onto the real binary so non-zsh callers (e.g. `sence`) get them too.
    (callPackage ../packages/fence.nix { })
    (callPackage ../packages/jrf.nix { })
    (callPackage ../packages/vite-plus.nix { })
    sence.packages.${pkgs.stdenv.hostPlatform.system}.default
    herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ccusage
  ];
}
