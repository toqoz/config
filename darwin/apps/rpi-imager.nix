{ ... }:
{
  # Raspberry Pi Imager writes OS images to microSD cards. Kept off the shared
  # module list because only forge01 has the card reader and target hardware.
  homebrew.casks = [ "raspberry-pi-imager" ];
}
