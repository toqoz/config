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
  imports = [ ./object-storage.nix ];

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

  # Local console recovery. The board is headless and has no out-of-band access,
  # so a locked account would mean reflashing the SD card. The generic SD image
  # ships these same credentials through its installation-device profile; this
  # module has to restate them, because switching to it regenerates /etc/group
  # and /etc/sudoers from this configuration alone.
  #
  # The empty passwords only work at an attached console. Remote access stays
  # tailnet-only, and tightening this is a decision for when Tailscale SSH is
  # known to work on this host.
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialHashedPassword = "";
  };
  users.users.root.hashedPassword = "";
  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = "nixos";

  # 1 GB of RAM is not enough to evaluate this configuration: nixpkgs
  # evaluation alone peaks around 790 MB and the board has no EEPROM-style
  # recovery, so an OOM-killed `nix` just leaves the switch unfinished.
  #
  # Compressed memory carries the common case; the SD-backed file is a lower
  # priority backstop that only sees pressure during evaluation and builds.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
    priority = 100;
  };
  swapDevices = [
    {
      device = "/var/swap";
      size = 2048;
      priority = 10;
    }
  ];

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
