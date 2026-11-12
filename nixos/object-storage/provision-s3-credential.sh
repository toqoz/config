#!/usr/bin/env bash
# Explicit access key lifecycle for VersityGW IAM users. Declarative reconcile
# never creates or changes keys; this command is the only path that does.
#
# Usage:
#   provision-s3-credential list USER
#   provision-s3-credential create USER --out FILE [--owner OWNER[:GROUP]]
#   provision-s3-credential rotate USER --out FILE [--owner OWNER[:GROUP]]
#   provision-s3-credential revoke USER ACCESS_KEY_ID [--force]
#
# create/rotate write the new key as an AWS shared-credentials profile named USER
# into FILE (mode 0600, never overwritten). Only key ids reach stdout/stderr.
# Env: VGW_IAM_ENDPOINT, VGW_ROOT_CREDENTIALS (file with the root access key id
#      and secret on two lines)
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: provision-s3-credential list USER
       provision-s3-credential create USER --out FILE [--owner OWNER[:GROUP]]
       provision-s3-credential rotate USER --out FILE [--owner OWNER[:GROUP]]
       provision-s3-credential revoke USER ACCESS_KEY_ID [--force]
EOF
  exit 2
}
die() {
  echo "provision-s3-credential: $*" >&2
  exit 1
}

(($# >= 2)) || usage
command=$1 user=$2
shift 2

out='' owner='' key='' force=0 tmp=''
trap '[[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
case $command in
  list) (($# == 0)) || usage ;;
  create | rotate)
    while (($#)); do
      case $1 in
        --out) out=${2:?--out needs a path}; shift 2 ;;
        --owner) owner=${2:?--owner needs OWNER[:GROUP]}; shift 2 ;;
        *) usage ;;
      esac
    done
    [[ -n $out ]] || die "--out FILE is required"
    ;;
  revoke)
    (($# >= 1)) || usage
    key=$1
    shift
    while (($#)); do
      case $1 in
        --force) force=1; shift ;;
        *) usage ;;
      esac
    done
    ;;
  *) usage ;;
esac

mapfile -t root < "${VGW_ROOT_CREDENTIALS:?}"
export AWS_ACCESS_KEY_ID=${root[0]:?} AWS_SECRET_ACCESS_KEY=${root[1]:?}
unset root
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true AWS_PAGER='' AWS_REGION=us-east-1
iam() { aws iam --endpoint-url "${VGW_IAM_ENDPOINT:?}" --output json "$@"; }

keys=$(iam list-access-keys --user-name "$user")
count=$(jq '.AccessKeyMetadata | length' <<< "$keys")

last_used() {
  iam get-access-key-last-used --access-key-id "$1" | jq -r '.AccessKeyLastUsed.LastUsedDate // "never"'
}

# Every step below names files by path, so no other user may be able to add,
# rename, or remove entries along it: the destination directory and each
# ancestor must belong to root or the invoking user, the destination must be
# writable by nobody else, and an ancestor only if it is sticky.
require_trusted_dir() {
  local dir=$1 uid owner mode leaf=1
  uid=$(id -u)
  while :; do
    read -r owner mode < <(stat -c '%u %a' -- "$dir")
    [[ $owner == 0 || $owner == "$uid" ]] || die "$dir is owned by uid $owner; deliver into a directory only root controls"
    if ((8#$mode & 8#022)) && { ((leaf)) || ! ((8#$mode & 8#1000)); }; then
      die "$dir is writable by other users; deliver into a directory only root controls"
    fi
    [[ $dir == / ]] && return
    dir=$(dirname -- "$dir")
    leaf=0
  done
}

# deliver: create a key and write it to $out without ever printing the secret.
deliver() {
  local dir response id
  dir=$(dirname -- "$out")
  [[ -d $dir ]] || die "directory $dir does not exist"
  # Everything below uses the physical path that was checked, never a path that
  # could lead through a symlink someone else can repoint.
  dir=$(cd -P -- "$dir" && pwd -P) || die "cannot resolve $dir"
  out=$dir/$(basename -- "$out")
  require_trusted_dir "$dir"
  [[ ! -e $out && ! -L $out ]] || die "refusing to overwrite $out"
  tmp=$(umask 077 && mktemp "$dir/.s3-credential.XXXXXX")
  # The response stays in memory, so the new key can be deleted again whatever
  # happens to the file.
  response=$(iam create-access-key --user-name "$user")
  id=$(printf '%s' "$response" | jq -r .AccessKey.AccessKeyId)
  if ! printf '%s' "$response" \
    | jq -r --arg p "$user" '"[\($p)]\naws_access_key_id = \(.AccessKey.AccessKeyId)\naws_secret_access_key = \(.AccessKey.SecretAccessKey)"' \
      > "$tmp"; then
    iam delete-access-key --user-name "$user" --access-key-id "$id" > /dev/null \
      || die "could not write the new key $id nor delete it; run: provision-s3-credential revoke $user $id --force"
    die "could not write the new key; key $id was deleted again"
  fi
  unset response
  # A hard link never replaces an existing name. If $out appeared meanwhile, the
  # key that nobody received is deleted again so it cannot linger in a key slot.
  if ! ln -- "$tmp" "$out" 2>/dev/null; then
    iam delete-access-key --user-name "$user" --access-key-id "$id" > /dev/null \
      || die "could not write $out nor delete the new key $id; run: provision-s3-credential revoke $user $id --force"
    die "refusing to overwrite $out; the new key $id was deleted again"
  fi
  # Hand the file over only once it is complete and in place; until then the
  # recipient owns nothing it could swap.
  if [[ -n $owner ]]; then
    chown -h -- "$owner" "$out"
  fi
  echo "created access key $id for $user in $out"
}

case $command in
  list)
    printf 'ACCESS_KEY_ID\tSTATUS\tCREATED\tLAST_USED\n'
    jq -r '.AccessKeyMetadata[] | [.AccessKeyId, .Status, .CreateDate] | @tsv' <<< "$keys" \
      | while IFS=$'\t' read -r id status created; do
        printf '%s\t%s\t%s\t%s\n' "$id" "$status" "$created" "$(last_used "$id")"
      done
    ;;
  create)
    ((count == 0)) || die "$user already has $count access key(s); use rotate"
    deliver
    ;;
  rotate)
    ((count == 1)) || die "rotate needs exactly one existing key, $user has $count; revoke one first"
    old=$(jq -r '.AccessKeyMetadata[0].AccessKeyId' <<< "$keys")
    deliver
    echo "old key $old stays active; switch clients to $out, then run: provision-s3-credential revoke $user $old"
    ;;
  revoke)
    jq -e --arg k "$key" '.AccessKeyMetadata | any(.AccessKeyId == $k)' <<< "$keys" > /dev/null \
      || die "$key is not an access key of $user"
    replacement=$(jq -r --arg k "$key" '[.AccessKeyMetadata[] | select(.AccessKeyId != $k and .Status == "Active") | .AccessKeyId][0] // ""' <<< "$keys")
    if ((!force)); then
      [[ -n $replacement ]] || die "$key is the last active key of $user; pass --force to cut off access"
      [[ $(last_used "$replacement") != never ]] \
        || die "replacement key $replacement has never been used; switch clients first or pass --force"
    fi
    iam delete-access-key --user-name "$user" --access-key-id "$key" > /dev/null
    echo "revoked access key $key of $user"
    ;;
esac
