{ pkgs, ... }:
let
  shared = import ./git-shared.nix { inherit pkgs; };
in
{
  programs.git = {
    enable = true;
    inherit (shared) ignores settings package;
  };
}
