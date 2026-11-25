# User-level profile for ras01, applied by Home Manager.
{ osConfig, ... }:
{
  imports = [ ../../home/linux-base.nix ];
  home.file.".config/versitygw/config".text = ''
    [profile ${osConfig.networking.hostName}]
    region = us-east-1
    endpoint_url = http://ras01:7070
  '';
}
