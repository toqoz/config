{
  pkgs,
  llm-agents,
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
    (callPackage ../packages/jrf.nix { })
    (callPackage ../packages/vite-plus.nix { })
    herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ccusage
  ];
}
