{ ... }:
{
  # Nix is managed by the nix-installer; let it own /etc/nix/nix.conf and the
  # nix-daemon instead of nix-darwin.
  # See https://nix-darwin.github.io/nix-darwin/manual/#opt-nix.enable
  nix.enable = false;
  # Customizations loaded via the installer's `!include nix.custom.conf` hook.
  environment.etc."nix/nix.custom.conf".text = ''
    warn-dirty = false
    extra-substituters = https://cache.numtide.com
    extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
  '';
  # One-time migration: hand off the installer-written nix.custom.conf to
  # nix-darwin. Runs before the /etc conflict check; no-op once the target
  # is a nix-darwin symlink.
  system.activationScripts.preActivation.text = ''
    if [ -e /etc/nix/nix.custom.conf ] && [ ! -L /etc/nix/nix.custom.conf ]; then
      mv /etc/nix/nix.custom.conf /etc/nix/nix.custom.conf.before-nix-darwin
    fi
  '';
}
