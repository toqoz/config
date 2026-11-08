# T3 Code sleep watcher

Remilis uses Keepresso automation leases to inhibit idle sleep while local T3
Code agents work. Closing the laptop lid is outside this watcher's scope.

The Home Manager service currently runs in **observe-only mode**. Keepresso is
declared in the remilis Homebrew configuration. Neither installation nor service
activation happens until the user applies the configuration.

## Commands

From the repository root, with Node.js 24 and `t3` on PATH:

```sh
node home/t3-sleep-watcher/main.mts --once
node home/t3-sleep-watcher/main.mts --watch
```

These commands do not inhibit sleep. After installing Keepresso, verify its
automation preferences and end action before explicitly enabling leases:

```sh
KEEPRESSO_CLI=/Applications/Keepresso.app/Contents/Helpers/keepresso \
  node home/t3-sleep-watcher/main.mts --watch --lease
```

Once live behavior has been verified, set
`my.t3code.sleepWatcher.keepAwake = true` in `home/home.nix` to use leases from
launchd. The module is imported only by remilis.

## Policy

- Running, queued, preparing, starting, approval and other unresolved non-input
  requests hold the lease.
  When the shell summary shows input, the watcher reads the full thread
  projection as well so a newer question cannot hide an older pending approval.
- Explicit blocking `user_input` requests hold for up to ten minutes from their
  creation time. An async question does not stop an otherwise working agent.
- A parent waiting for known children uses the children's own states. Unknown
  child work conservatively holds. Awaited background commands hold; unattended
  servers without `awaited` do not.
- The transition from working to fully idle starts one five-minute grace period.
  Input timeout receives no additional completion grace.
- A fresh launch with only idle threads does not acquire a lease. Completion
  grace is in memory and is not restored after a watcher restart.
- Lease TTL is 90 seconds; heartbeat interval is 30 seconds. The six-day rotation
  checks that the previous lease is still live, acquires its replacement, then
  releases the old lease before the seven-day hard ceiling.
- Source disconnect, parse failure and stream silence stop renewal. Keepresso
  expires the lease on its reconciliation tick after the TTL. No direct
  `caffeinate` fallback is used.
- A revoked/expired lease or disabled automation suspends further lease calls
  until an explicit watcher restart. Keepresso battery/thermal safety pauses
  remain effective and are reported as `safety-paused`.
- SIGINT/SIGTERM also leave any lease to expire. Another application's sleep
  assertions, or Keepresso's other triggers, can still hold the machine awake.

## Protocol and validation

Verified on the installed remilis `t3 v0.1.7` with a real, read-only WebSocket
subscription: 248 shell rows, including 242 rows with parent lineage. The
watcher reads the runtime origin from `~/.t3/userdata/server-runtime.json`,
issues a one-hour `orchestration:read` bearer through the installed `t3` CLI,
exchanges it for `/api/auth/websocket-ticket`, and connects to
`/ws?orchestrationProtocol=2`. Tokens stay in memory and are revoked on disconnect;
expiry bounds leftover authentication if the process crashes. The connection
rotates every 30 minutes and always reloads a full snapshot, including archived
threads. Thread contents and credentials are not logged.

The shell contract and authenticated CLI flow were checked against the Nix
source used by the installed package:
`/nix/store/lak98930y3add5qdcnz76ywrgsvjq1ar-source`.
Relevant upstream files are `packages/contracts/src/orchestrationV2.ts` and
`apps/server/src/cli/thread.ts`. This is an internal protocol; unsupported
changes fail closed by stopping lease renewal.

The transport sends Effect RPC Ping frames and acknowledges each Chunk. It
requests a synchronization marker and withholds decisions until it arrives.
Project-enrichment snapshots marked with `resolvedRepositoryIdentityRoots`
carry empty thread arrays and must not replace thread state.

Keepresso source inspected at commit
`daa4b0397983bcf93a96d63feec52dd7183671d2`:

- `Sources/KeepressoCore/AutomationLease.swift`: TTL clamps to 10–86400 seconds;
  hard lifetime caps at 604800 seconds. Expiry is the earlier horizon.
- `Sources/KeepressoCore/LeaseClient.swift`: acquire acknowledgement, heartbeat,
  release, exit codes, safety pause reporting, and explicit revocation behavior.
- `Sources/KeepressoCore/CLICommand.swift`: actual CLI arguments.

Keepresso's upstream tests could not compile in the current local Swift setup:
the `TestingMacros` plugin was not found. The CLI itself built successfully.
Ten direct assertions against the unmodified record/policy source passed,
covering TTL bounds, heartbeat extension, expiry and the lifetime ceiling.
The live T3 stream was also exercised with a fake Keepresso CLI, verifying an
acquire followed by a heartbeat for the same UUID without changing power state.
Keepresso was not installed/running during development, so actual macOS sleep
assertion acquisition, crash TTL expiry, and end actions remain unverified.
Do not enable the launchd lease option before checking these behaviors.

Run isolated watcher checks with:

```sh
node --test t/t3-sleep-watcher.test.mts
```

Before live use, verify acquisition and release with `pmset -g assertions`,
blocking approval versus input on the providers in use, a live child after its
parent returns, disconnect/reconnect, and crash expiry. Keepresso's final-session
end action should be off if the intended behavior is to resume normal idle
sleep rather than force sleep immediately.
