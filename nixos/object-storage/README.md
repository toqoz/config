# Object storage (VersityGW + Standalone IAM)

`services.objectStorage` runs an S3-compatible gateway on ras01 for agent
handoff data (`handoff`) and results shown to people (`published`). The
declarations live in `hosts/ras01/object-storage.nix` and are public. Every
credential exists only on the host.

Design decisions and their evidence are recorded in
`docs/decisions/005-ras01-object-storage.md`.

## Layout

| Unit | Runs as | State | Listens |
|---|---|---|---|
| `versitygw-root-credentials` (oneshot) | root | `/var/lib/versitygw-root/root-credentials` (0400) | none |
| `versitygw-iam` | `versitygw-iam` | `/var/lib/versitygw/iam` (`iam.json`) | `127.0.0.1:7071`, `/run/versitygw/iam.sock` (0660) |
| `versitygw` | `versitygw` | `/var/lib/versitygw/data` (objects + `user.*` xattrs) | `:7070`, firewall-open on `tailscale0` only |
| `versitygw-reconcile` (oneshot) | dynamic user | none | none |

The root account is created once by `versitygw-root-credentials` and reaches the
other units only through `LoadCredential=`. `with-root-credentials` exports it as
`ROOT_ACCESS_KEY_ID` / `ROOT_SECRET_ACCESS_KEY` for the exec'd process, because
versitygw has no file-based option. It never appears in argv, unit files, the
Nix store, or the journal.

### Fail-closed

The root account is an IAM-only credential. It signs the IAM API and the
gateway's private calls to IAM, but it cannot sign S3 requests:
`with-root-credentials --gateway` hands the gateway the root access key id (the
owner of every bucket) with a random secret generated at each gateway start,
which exists only in the gateway process and is never stored. A request signed
with the real root secret gets `SignatureDoesNotMatch`.

So every authenticated S3 request is checked by IAM: the gateway asks IAM over
the socket to derive the signing key and to evaluate the policy, with no cache
(1.9.0 has none, and `--iam-cache-disable` keeps it off after upgrades). No new
request is authorized without a fresh IAM answer. Anonymous requests are denied,
because no bucket policy or ACL grants them and no identity may set one.

A transfer authorized before IAM fails may finish, and an upload may still be
committed. This is the accepted behavior. The gateway does not recheck IAM before
publishing an upload. IAM failure does not force the gateway or its open
connections to stop.

When IAM stops or crashes, new authenticated requests fail with HTTP 500. A hung
IAM causes them to fail after the upstream 10 s timeout. The stored root secret
still gets `SignatureDoesNotMatch`. IAM restarts automatically after a crash. To
recover from a hang, run `systemctl restart versitygw-iam`.

Starting the gateway also starts IAM and orders the gateway after it. Routine
stops and restarts use upstream's graceful SIGTERM shutdown with a 10 s shutdown
timeout. Upstream can cancel an active request during shutdown, so completion
is not guaranteed when the gateway itself stops. To stop both services, run
`systemctl stop versitygw versitygw-iam`.

## Declaring identities

Add buckets, policies, and identities in `hosts/ras01/object-storage.nix`, then
switch. `versitygw-reconcile` reruns whenever the declarations change:

- It creates missing users, roles, and buckets, and replaces inline policies
  that differ from the declaration.
- It never deletes anything and never touches access keys. A user, role, or
  inline policy that is no longer declared is kept and logged as
  `drift: ... (kept)`; remove it by hand with the IAM API if intended.
- Identities it manages carry IAM path `/nix-managed/` and tag
  `managed-by=nix`. A same-named identity outside that path is reported as a
  `conflict` and the unit fails without changing it.
- Buckets are created by the reserved managed user `versitygw-reconcile`
  (inline policy `buckets`: `s3:CreateBucket` on the declared buckets and
  `s3:ListAllMyBuckets`), because root cannot sign S3 requests. Each run,
  including `--dry-run`, deletes any key that user has, creates one access key,
  uses it for the bucket list and creation, and deletes it on exit. The secret
  stays in the reconcile process. A key left by a killed run is deleted by the
  next run. Do not issue keys for this user; two reconcile runs at the same time
  can delete each other's key and fail, so rerun one of them.

Preview what the deployed declarations would change, or rerun them, on the host:

```sh
sudo versitygw-reconcile --dry-run
sudo systemctl restart versitygw-reconcile
```

Roles are reconciled, but upstream 1.9.0 has no STS `AssumeRole`. A role is
usable only through `AssumeRoleWithWebIdentity` once an OIDC provider exists.

Standalone IAM limits inline policies to 2048 bytes per user and 10240 bytes
per role in total; evaluation fails before deployment if a declaration exceeds
them.

## Access keys

Keys are issued only by an explicit command on the host, as root:

```sh
sudo provision-s3-credential list agent
sudo provision-s3-credential create agent --out /root/agent.ini [--owner USER:GROUP]
sudo provision-s3-credential rotate agent --out /root/agent-next.ini
sudo provision-s3-credential revoke agent AKIA... [--force]
```

- The secret is written once, to a new 0600 file in AWS shared-credentials
  format with a profile named after the user. Existing files are never
  overwritten. Only key ids are printed.
- The `--out` directory is resolved to its physical path once, and every later
  step uses that path. It and all its ancestors must be owned by root (or the
  invoking user). The directory itself must not be writable by other users,
  even if sticky; ancestors may be sticky (`/tmp`). Otherwise another user
  could swap files between the steps, so the command refuses. Write into a
  root-only directory and hand the file over from there. `--owner` is applied
  only after the complete file is in place.
- If the file cannot be written or published after IAM created the key, the
  key is deleted again so no undelivered key occupies one of the two slots.
- Deliver the file over an authenticated channel (for example
  `tailscale file cp`), then delete the host copy. Clients use
  `AWS_SHARED_CREDENTIALS_FILE=<file> AWS_PROFILE=<user>` with
  `--endpoint-url http://ras01:7070` (region `us-east-1`).
- Rotation keeps both keys active. `revoke` deletes the old key only after the
  replacement has been used at least once, as reported by IAM; `--force`
  skips that check and is also required to delete a user's last active key.
- IAM allows two keys per user, so `rotate` needs exactly one existing key.

## Backup and restore

Back up to a separate, access-restricted medium:

```sh
sudo versitygw-backup create /mnt/backup
```

This stops the reconcile unit, the gateway, and IAM, archives
`/var/lib/versitygw` and `/var/lib/versitygw-root` with `user.*` xattrs into a
0600 `versitygw-<UTC timestamp>.tar.gz`, and starts the services again.
Downtime lasts as long as the archive takes. The archive contains the root
account and every user's secret key in plaintext (`iam.json`); treat it as
secret material.

Restore on the same or a freshly installed host (after a switch to this
configuration):

```sh
sudo versitygw-backup restore /mnt/backup/versitygw-<timestamp>.tar.gz
```

Restore checks the archive before anything else happens. It refuses archives
that cannot be read, contain entries other than regular files and directories,
contain anything besides `versitygw/iam/`, `versitygw/data/`, and
`versitygw-root/root-credentials`, lack one of those, or hold root credentials
or `iam.json` that are not in the expected shape; the running services are
untouched in that case. It then unpacks into a private staging directory next to
the state, stops the services, moves the current state aside to
`*.pre-restore-<UTC timestamp>` (nothing is deleted), installs the staged state,
re-owns it to this host's service users, strips group/other permissions and
setuid/setgid bits, and starts the services. The restore counts as done only
when the gateway is up and IAM answers a signed request with the restored root
account within 60 seconds; otherwise, or if any earlier step fails, the
services are stopped, the previous state is moved back, and the services start
again on it. Reconcile then applies the current declarations on top. Existing
access keys, inline policies, objects, and the root account come back
unchanged. Remove the `*.pre-restore-*` directories once the restore is confirmed.

The root account authenticates IAM and the gateway to each other; it does not
encrypt `iam.json`. If `/var/lib/versitygw-root/root-credentials` is lost
without a backup, users and their keys in the IAM state remain valid: stop the
services, let `versitygw-root-credentials` generate a new root account (delete
the leftover file if only part of it survived), and start them again. Only the
old root credentials themselves are gone.

## Rollback

NixOS rollback does not touch IAM state or data. Rolling back to a generation
without a user or bucket keeps it (reported as drift). Rolling back to a
generation without this module stops the services and leaves
`/var/lib/versitygw*` in place.

## Upgrades

Upstream 1.11 adds a signing-key cache to the gateway; the module already
passes `--iam-cache-disable`, which keeps revocation immediate and IAM loss
fail-closed. Upgrade IAM before the gateway (the gateway is ordered after
`versitygw-iam`). Recheck the fail-closed section against the new release:
it depends on the gateway resolving only its own root locally and asking IAM
for every other access key, and on the gateway's 10 s SIGTERM drain.

## Verification

- `node --test t/object-storage.test.mts` runs the scripts against real
  versitygw and awscli processes (backup/restore runs on Linux only, because
  GNU tar on darwin lacks xattr support).
- `nix flake check` includes `ras01-object-storage`, which checks the network
  exposure, credential delivery, and per-user bucket scope by evaluation and
  shellchecks the scripts.
