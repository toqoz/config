# NixOS host for the Raspberry Pi 3 Model B (aarch64-linux, 1 GB RAM).
#
# It is provisioned from the generic AArch64 SD image, so this module keeps that
# image's boot chain (Raspberry Pi firmware -> U-Boot -> extlinux) instead of
# managing the firmware partition itself. The firmware partition is left alone;
# `/` and the extlinux menu are the only pieces this system owns.
{
  ...
}:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "26.05";

  networking.hostName = "ras01";

  # Root partition label created by the generic SD image.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Remote access runs entirely over the tailnet. Tailscale SSH replaces sshd, so
  # there are no SSH keys to distribute or rotate.
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--ssh" ];
  };
  services.openssh.enable = false;

  # 1 GB of RAM: keep swap in compressed memory so build and transfer spikes do
  # not become SD-card writes.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # SD-card write budget. The journal stays in RAM and /tmp is a tmpfs, so
  # routine operation does not touch the card.
  services.journald.settings.Journal.Storage = "volatile";
  boot.tmp.useTmpfs = true;

  # Build one derivation at a time. A 1 GB board gets OOM-killed by parallel
  # compilation, and the vendor kernel comes from the binary cache anyway.
  nix.settings.max-jobs = 1;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Documentation costs build time and root filesystem space on a 2 GB root.
  documentation.enable = false;
  documentation.nixos.enable = false;
}
