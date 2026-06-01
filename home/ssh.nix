{ ... }:
{
  home.file.".ssh/config".text = ''
    TCPKeepAlive yes
    ServerAliveInterval 60
    ServerAliveCountMax 5

    # Added by OrbStack: 'orb' SSH host for Linux machines
    # This only works if it's at the top of ssh_config (before any Host blocks).
    # This won't be added again if you remove it.
    Include ~/.orbstack/ssh/config

    Include ~/src/github.com/toqoz/private/ssh/config

    Host *
      # OpenSSH 10.3 ignores deprecated aliases like "lowdelay throughput".
      IPQoS af21 cs1
  '';
}
