{
  username = "agent";

  darwinModule = { ... }:
  {
    # Preserve Homebrew declaration order when combining shared and host apps.
    imports = builtins.sort (a: b: toString a < toString b) ((import ../../darwin/base.nix) ++ [
      ../../darwin/apps/rpi-imager.nix
    ]);

    nixpkgs.hostPlatform = "aarch64-darwin";
    system.stateVersion = 6;

    networking = {
      hostName = "forge01";
      localHostName = "forge01";
      computerName = "forge01";
    };
  };

  homeModule = { ... }:
  {
    imports = [
      ../../home/base.nix
      ../../home/agents/claude-code
      ../../home/agents/mcp.nix
      ../../home/agents/codex/app-server.nix
      ../../home/deepseek-harness
      ../../home/quota-dashboard
      ../../home/t3code.nix
    ];

    my.t3code.enable = true;

    # This host also runs the aggregation stack; the collector posts to it
    # over loopback so collection keeps working without the tailnet.
    my.quotaDashboard = {
      enable = true;
      host = "forge01";
      stack.enable = true;
      # Tailscale Serve terminates HTTPS for the loopback Grafana; root_url
      # keeps Grafana-generated links on the tailnet URL.
      stack.rootUrl = "https://forge01.tail99f21.ts.net:3370/";
    };
  };
}
