# Entry point for the Linux host, mirroring hosts/<host> on darwin: the flake
# passes these modules to `mkNixosHost`, so a new host is one attribute in
# `nixosConfigurations` plus these three files.
{
  username = "nixos";
  nixosModule = ./system.nix;
  homeModule = ./home.nix;
}
