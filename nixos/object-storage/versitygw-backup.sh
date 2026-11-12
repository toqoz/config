#!/usr/bin/env bash
# Back up or restore VersityGW state: IAM state, S3 objects with their user.*
# xattrs (VersityGW keeps object and bucket metadata there), and the root account.
# Services stop for the duration so IAM state and object data come from one moment.
#
# Usage: versitygw-backup create DEST_DIR
#        versitygw-backup restore ARCHIVE
# Env:   VGW_BACKUP_ROOT (filesystem root the state paths live under, default /),
#        VGW_SYSTEMCTL (default systemctl),
#        VGW_ROOT_OWNER / VGW_IAM_OWNER / VGW_GATEWAY_OWNER (OWNER:GROUP applied
#        after restore), VGW_IAM_ENDPOINT / VGW_S3_ENDPOINT (checked after restore),
#        VGW_RESTORE_TIMEOUT (seconds allowed for start-up and those checks,
#        default 60)
set -euo pipefail

# Empty means the real filesystem root.
root=${VGW_BACKUP_ROOT:-}
systemctl=${VGW_SYSTEMCTL:-systemctl}
paths=(var/lib/versitygw var/lib/versitygw-root)
tar_xattrs=(--xattrs --xattrs-include='user.*')

die() {
  echo "versitygw-backup: $*" >&2
  exit 1
}

stop_services() { $systemctl stop versitygw-reconcile.service versitygw.service versitygw-iam.service; }
# The reconcile unit requires the gateway and IAM, so starting it starts all three
# and converges the declared state on top of whatever was restored.
start_services() { $systemctl start versitygw-reconcile.service; }

# Global so the EXIT trap still sees it after create() returns.
partial=''

create() {
  local dest=${1:?usage: versitygw-backup create DEST_DIR} name
  [[ -d $dest ]] || die "$dest is not a directory"
  for path in "${paths[@]}"; do
    [[ -d $root/$path ]] || die "$root/$path does not exist"
  done
  name=versitygw-$(date -u +%Y%m%dT%H%M%SZ).tar.gz
  partial=$(umask 077 && mktemp "$dest/.$name.XXXXXX")
  stop_services
  trap '[[ -z $partial ]] || rm -f -- "$partial"; start_services' EXIT
  tar --create --gzip "${tar_xattrs[@]}" --numeric-owner -C "${root:-/}" -f "$partial" "${paths[@]}"
  mv -- "$partial" "$dest/$name"
  echo "backup written to $dest/$name"
}

# Globals so the EXIT trap still sees them after restore() returns.
staging='' stamp='' installed=0 started=0

# On any failure after the services stopped, put the previous state back.
finish_restore() {
  if ((!installed)); then
    for path in "${paths[@]}"; do
      if [[ -e $root/$path.pre-restore-$stamp ]]; then
        rm -rf -- "$root/${path:?}"
        mv -- "$root/$path.pre-restore-$stamp" "$root/$path"
      fi
    done
    echo "versitygw-backup: restore failed; the previous state is back in place" >&2
  fi
  rm -rf -- "${staging:?}"
  ((started)) || start_services
}

# The restored state is only accepted once IAM answers a signed request with the
# restored root account and the gateway is up; a healthy listener alone can still
# hold IAM state it cannot parse. Every step is cut off at the shared deadline.
restored_state_serves() {
  local deadline=$1 left
  local -a creds
  mapfile -t creds < "$root/var/lib/versitygw-root/root-credentials"
  while left=$((deadline - SECONDS)); ((left > 0)); do
    if timeout "$left" curl -fsS -o /dev/null "${VGW_S3_ENDPOINT:?}/health" 2>/dev/null \
      && left=$((deadline - SECONDS)) && ((left > 0)) \
      && (
        export AWS_ACCESS_KEY_ID=${creds[0]} AWS_SECRET_ACCESS_KEY=${creds[1]} AWS_CONFIG_FILE=/dev/null \
          AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_REGION=us-east-1 AWS_MAX_ATTEMPTS=1 AWS_EC2_METADATA_DISABLED=true
        timeout "$left" aws iam --endpoint-url "${VGW_IAM_ENDPOINT:?}" list-users > /dev/null 2>&1
      ); then
      return 0
    fi
    sleep 1
  done
  return 1
}

restore() {
  local archive=${1:?usage: versitygw-backup restore ARCHIVE} entry bad types deadline
  [[ -f $archive ]] || die "$archive is not a file"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)

  # State holds only directories and regular files. Links or devices could reach
  # or alias a file outside the state, so the member types are checked before
  # anything is unpacked.
  types=$(tar --list --verbose --gzip -f "$archive" | cut -c1 | sort -u) || die "cannot read $archive"
  if [[ -n $types ]] && grep -qv '^[-d]$' <<< "$types"; then
    die "archive contains entries other than regular files and directories"
  fi

  # Unpack and check the whole archive before touching the running state. The
  # staging directory sits next to the state so installing it is a rename.
  staging=$(umask 077 && mktemp -d "$root/var/lib/.versitygw-restore.XXXXXX")
  trap 'rm -rf -- "$staging"' EXIT
  tar --extract --gzip "${tar_xattrs[@]}" --numeric-owner -C "$staging" -f "$archive" \
    || die "cannot unpack $archive"
  while IFS= read -r -d '' entry; do
    case $entry in
      ./var | ./var/lib | ./var/lib/versitygw | ./var/lib/versitygw/iam | ./var/lib/versitygw/iam/* \
        | ./var/lib/versitygw/data | ./var/lib/versitygw/data/* | ./var/lib/versitygw-root \
        | ./var/lib/versitygw-root/root-credentials) ;;
      *) die "unexpected archive member ${entry#./}" ;;
    esac
  done < <(cd "$staging" && find . -mindepth 1 -print0)
  bad=$(find "$staging" -mindepth 1 \( \( ! -type d ! -type f \) -o \( -type f -links +1 \) \) -print -quit)
  [[ -z $bad ]] || die "archive contains a link or special file: ${bad#"$staging"/}"
  [[ -s $staging/var/lib/versitygw-root/root-credentials && -f $staging/var/lib/versitygw/iam/iam.json \
    && -d $staging/var/lib/versitygw/data ]] || die "archive lacks the root credentials, IAM state, or data directory"
  local -a creds
  mapfile -t creds < "$staging/var/lib/versitygw-root/root-credentials"
  ((${#creds[@]} == 2)) && [[ -n ${creds[0]} && -n ${creds[1]} ]] \
    || die "archive root-credentials is not an access key id and a secret on two lines"
  unset creds
  jq -e 'type == "object" and all(.[]; . == null or type == "object") and all(.users // {} | .[]; type == "object")' \
    "$staging/var/lib/versitygw/iam/iam.json" > /dev/null 2>&1 \
    || die "archive iam.json is not VersityGW IAM state"

  stop_services
  trap finish_restore EXIT
  # Current state is moved aside, not deleted, so a wrong archive is recoverable.
  for path in "${paths[@]}"; do
    if [[ -e $root/$path ]]; then
      mv -- "$root/$path" "$root/$path.pre-restore-$stamp"
      echo "moved current $root/$path to $root/$path.pre-restore-$stamp"
    fi
  done
  for path in "${paths[@]}"; do
    mv -- "$staging/$path" "$root/$path"
  done
  # Service uids are allocated per machine, so the archive's numeric owners may
  # not match this one; the archive's modes are not trusted either.
  if [[ -n ${VGW_ROOT_OWNER:-} ]]; then
    chown -R -- "$VGW_ROOT_OWNER" "$root/var/lib/versitygw-root"
    chown -- "$VGW_ROOT_OWNER" "$root/var/lib/versitygw"
  fi
  if [[ -n ${VGW_IAM_OWNER:-} ]]; then
    chown -R -- "$VGW_IAM_OWNER" "$root/var/lib/versitygw/iam"
  fi
  if [[ -n ${VGW_GATEWAY_OWNER:-} ]]; then
    chown -R -- "$VGW_GATEWAY_OWNER" "$root/var/lib/versitygw/data"
  fi
  chmod -R go-rwx,ug-s "$root/var/lib/versitygw-root" "$root/var/lib/versitygw/iam" "$root/var/lib/versitygw/data"
  # The extra leading zero makes GNU chmod clear a directory's setuid/setgid bits too.
  chmod 00755 "$root/var/lib/versitygw"
  chmod 0400 "$root/var/lib/versitygw-root/root-credentials"

  deadline=$((SECONDS + ${VGW_RESTORE_TIMEOUT:-60}))
  if timeout "${VGW_RESTORE_TIMEOUT:-60}" "$systemctl" start versitygw-reconcile.service \
    && restored_state_serves "$deadline"; then
    installed=1 started=1
    echo "restored $archive"
    return
  fi
  echo "versitygw-backup: the restored state did not come up; rolling back" >&2
  stop_services || true
  exit 1
}

case ${1:-} in
  create) create "${2:-}" ;;
  restore) restore "${2:-}" ;;
  *)
    echo "usage: versitygw-backup create DEST_DIR | restore ARCHIVE" >&2
    exit 2
    ;;
esac
