# forge01 app-server

Only `hosts/forge01/default.nix` imports `app-server.nix`. The user launch agent runs the shared llm-agents Codex package as `agent`, with `/Users/agent` as HOME and working directory. Codex keeps its existing state and account in `~/.codex`.

The backend listens on `ws://127.0.0.1:4500`. Tailscale Serve terminates TLS on HTTPS port 4500 and proxies WebSocket upgrades to that loopback address. The endpoint is `wss://<Self.DNSName>:4500/`. It has no LAN listener or Funnel exposure. Tailnet access policy still controls who can reach it.

Activation creates `${XDG_STATE_HOME}/codex-app-server` and its `log` directory with mode 0700. The persistent `capability-token` and `log/stdout.log` and `log/stderr.log` have mode 0600. The token contains 64 random hexadecimal characters. Reactivation preserves it and rejects invalid tokens, non-files, and symlinks. The service prints the stable WSS URL, never the token.

Native WebSocket clients send `Authorization: Bearer <capability-token>` on the upgrade request. Clients must omit the `Origin` header. Codex rejects any Origin, so browser JavaScript clients cannot connect directly. After the upgrade, clients use the Codex app-server initialize protocol.

Both this service and DeepSeek use `packages/tailscale-serve.bash`. The guard requires a running Tailscale node with valid DNS. It accepts an unused port or the exact existing root HTTPS proxy. It refuses conflicting handlers, foreground listeners, or Funnel on the requested port, without resetting Serve or changing other ports. DeepSeek retains port 3080. The launch agent retries failed startup with a 10-second throttle.
