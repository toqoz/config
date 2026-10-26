{ ... }:
{
  # The vendor cask supports in-app updates outside the read-only Nix store.
  # The bare `orca` cask is an unrelated Plotly app.
  homebrew.taps = [ "stablyai/orca" ];
  homebrew.casks = [ "stablyai/orca/orca" ];
}
