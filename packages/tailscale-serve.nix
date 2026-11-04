{ lib, writeShellScript, jq }:
writeShellScript "tailscale-serve" (lib.replaceStrings
  [ "@tailscale@" "@jq@" ]
  [ "/Applications/Tailscale.app/Contents/MacOS/Tailscale" (lib.getExe jq) ]
  (builtins.readFile ./tailscale-serve.bash))
