#!/usr/bin/env bash
# Create the VersityGW root account once: DIR/root-credentials holds the access key
# id and the secret on two lines. An existing file is never replaced, so a rebuild
# or reboot keeps the account that IAM state and backups were made with.
# Usage: root-credentials.sh DIR
set -euo pipefail

dir=${1:?usage: root-credentials.sh DIR}
file=$dir/root-credentials
umask 077
mkdir -p -- "$dir"
chmod 0700 -- "$dir"

if [[ -e $file ]]; then
  echo "root credentials present"
  exit 0
fi

# Leftovers of an interrupted run were never renamed into place.
rm -f -- "$dir"/.root-credentials.*

random_hex() { od -An -tx1 -N"$1" /dev/urandom | tr -d ' \n'; }
tmp=$(mktemp "$dir/.root-credentials.XXXXXX")
{
  random_hex 10 | tr 'a-f' 'A-F' | sed 's/^/VGWROOT/'
  echo
  random_hex 30
  echo
} > "$tmp"
chmod 0400 -- "$tmp"
mv -- "$tmp" "$file"
echo "root credentials created"
