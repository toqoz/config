#!/usr/bin/env bash
# Exec a command with the VersityGW root account exported as ROOT_ACCESS_KEY_ID /
# ROOT_SECRET_ACCESS_KEY. versitygw reads root credentials only from flags or the
# environment; the environment keeps them out of argv and is readable only by the
# service's own uid and root.
#
# With --gateway, the root account instead signs the gateway's calls to IAM
# (VGW_IAM_STANDALONE_ACCESS/SECRET), and the gateway's own S3 root keeps the access
# key id (the bucket owner) but gets a fresh random secret that exists only in the
# gateway process. Nobody can sign as that root, so every S3 request is
# authenticated by IAM and fails while IAM is stopped, dead, or hung.
# Usage: with-root-credentials [--gateway] COMMAND...
set -euo pipefail

gateway=0
if [[ ${1:-} == --gateway ]]; then
  gateway=1
  shift
fi

mapfile -t root < "${CREDENTIALS_DIRECTORY:?}/root-credentials"
if ((${#root[@]} < 2)) || [[ -z ${root[0]} || -z ${root[1]} ]]; then
  echo "root-credentials must hold the access key id and the secret on two lines" >&2
  exit 1
fi
if ((gateway)); then
  unusable=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
  ((${#unusable} == 64)) || { echo "cannot read /dev/urandom" >&2; exit 1; }
  export VGW_IAM_STANDALONE_ACCESS=${root[0]} VGW_IAM_STANDALONE_SECRET=${root[1]}
  export ROOT_ACCESS_KEY_ID=${root[0]} ROOT_SECRET_ACCESS_KEY=$unusable
  unset unusable
else
  export ROOT_ACCESS_KEY_ID=${root[0]} ROOT_SECRET_ACCESS_KEY=${root[1]}
fi
unset root
exec "$@"
