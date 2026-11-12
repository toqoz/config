#!/usr/bin/env bash
# Converge VersityGW IAM users, roles, inline policies, and buckets toward a
# desired-state document. Missing resources are created and differing policies
# are replaced. Nothing is deleted, and identities outside the managed IAM path are
# never touched. Access keys are left alone, except that buckets are created as the
# reserved bucketCreator user with a key that exists only for this run (the
# gateway's root cannot sign requests).
#
# Usage: reconcile.sh [--dry-run] DESIRED_JSON
# Env:   VGW_IAM_ENDPOINT, VGW_S3_ENDPOINT, VGW_ROOT_CREDENTIALS (file with the
#        root access key id and secret on two lines)
set -euo pipefail

dry_run=0
if [[ ${1:-} == --dry-run ]]; then
  dry_run=1
  shift
fi
desired=${1:?usage: reconcile.sh [--dry-run] DESIRED_JSON}
iam_endpoint=${VGW_IAM_ENDPOINT:?}
s3_endpoint=${VGW_S3_ENDPOINT:?}

mapfile -t root < "${VGW_ROOT_CREDENTIALS:?}"
export AWS_ACCESS_KEY_ID=${root[0]:?} AWS_SECRET_ACCESS_KEY=${root[1]:?}
unset root
export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true AWS_PAGER='' AWS_REGION=${AWS_REGION:-us-east-1}

iam() { aws iam --endpoint-url "$iam_endpoint" --output json "$@"; }

wait_ready() {
  local url=$1/health attempt
  for ((attempt = 0; attempt < 60; attempt++)); do
    curl -fsS -o /dev/null "$url" 2>/dev/null && return 0
    sleep 1
  done
  echo "reconcile: $url is not ready" >&2
  return 1
}

changes=0
conflicts=0

change() {
  local what=$1
  shift
  changes=$((changes + 1))
  if ((dry_run)); then
    echo "plan: $what"
  else
    "$@" > /dev/null
    echo "applied: $what"
  fi
}

# IAM may return a policy document as a JSON string or as an object.
canonical_document() { jq -S -c 'if type == "string" then fromjson else . end'; }

wait_ready "$iam_endpoint"
wait_ready "$s3_endpoint"

managed_path=$(jq -r .managedPath "$desired")
tag=Key=managed-by,Value=nix

# reconcile_policies KIND NAME EXISTS: KIND is user or role.
reconcile_policies() {
  local kind=$1 name=$2 exists=$3 current='' policy want have
  local flag=--$kind-name
  if ((exists)); then
    current=$(iam "list-$kind-policies" "$flag" "$name" | jq -r '.PolicyNames[]')
  fi
  while IFS= read -r policy; do
    [[ -n $policy ]] || continue
    want=$(jq -S -c --arg n "$name" --arg p "$policy" ".${kind}s[\$n].policies[\$p]" "$desired")
    if grep -qxF -- "$policy" <<< "$current"; then
      have=$(iam "get-$kind-policy" "$flag" "$name" --policy-name "$policy" | jq '.PolicyDocument' | canonical_document)
      [[ $have == "$want" ]] && continue
      change "update $kind $name policy $policy" iam "put-$kind-policy" "$flag" "$name" --policy-name "$policy" --policy-document "$want"
    else
      change "add $kind $name policy $policy" iam "put-$kind-policy" "$flag" "$name" --policy-name "$policy" --policy-document "$want"
    fi
  done < <(jq -r --arg n "$name" ".${kind}s[\$n].policies | keys[]" "$desired")
  while IFS= read -r policy; do
    [[ -n $policy ]] || continue
    jq -e --arg n "$name" --arg p "$policy" ".${kind}s[\$n].policies | has(\$p)" "$desired" > /dev/null \
      || echo "drift: $kind $name has undeclared inline policy $policy (kept)"
  done <<< "$current"
}

# reconcile_identities KIND LIST_JSON: create missing identities, then policies.
reconcile_identities() {
  local kind=$1 listing=$2 name path trust have
  local key=Users
  [[ $kind == role ]] && key=Roles
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    path=$(jq -r --arg n "$name" ".${key}[] | select(.${kind^}Name == \$n) | .Path" <<< "$listing")
    if [[ -z $path ]]; then
      if [[ $kind == role ]]; then
        trust=$(jq -S -c --arg n "$name" '.roles[$n].assumeRolePolicy' "$desired")
        change "create role $name" iam create-role --role-name "$name" --path "$managed_path" \
          --assume-role-policy-document "$trust" --tags "$tag"
      else
        change "create user $name" iam create-user --user-name "$name" --path "$managed_path" --tags "$tag"
      fi
      reconcile_policies "$kind" "$name" "$((dry_run ? 0 : 1))"
      continue
    fi
    if [[ $path != "$managed_path" ]]; then
      echo "conflict: $kind $name exists outside $managed_path (path $path); left untouched" >&2
      conflicts=$((conflicts + 1))
      continue
    fi
    if [[ $kind == role ]]; then
      trust=$(jq -S -c --arg n "$name" '.roles[$n].assumeRolePolicy' "$desired")
      have=$(iam get-role --role-name "$name" | jq '.Role.AssumeRolePolicyDocument' | canonical_document)
      [[ $have == "$trust" ]] \
        || change "update role $name trust policy" iam update-assume-role-policy --role-name "$name" --policy-document "$trust"
    fi
    reconcile_policies "$kind" "$name" 1
  done < <(jq -r ".${kind}s | keys[]" "$desired")
  jq -r --arg p "$managed_path" ".${key}[] | select(.Path == \$p) | .${kind^}Name" <<< "$listing" \
    | while IFS= read -r name; do
      jq -e --arg n "$name" ".${kind}s | has(\$n)" "$desired" > /dev/null \
        || echo "drift: managed $kind $name is no longer declared (kept)"
    done
}

users=$(iam list-users)
reconcile_identities user "$users"
reconcile_identities role "$(iam list-roles)"

bucket_creator=$(jq -r .bucketCreator "$desired")
bucket_access='' bucket_secret=''
creator_s3api() {
  AWS_ACCESS_KEY_ID=$bucket_access AWS_SECRET_ACCESS_KEY=$bucket_secret \
    aws s3api --endpoint-url "$s3_endpoint" --output json "$@"
}
drop_bucket_key() {
  iam delete-access-key --user-name "$bucket_creator" --access-key-id "$bucket_access" > /dev/null \
    || echo "reconcile: could not delete temporary key $bucket_access of $bucket_creator; the next run does" >&2
}
# Only this script creates keys for the bucket creator, so any existing key is a
# leftover of an interrupted run.
issue_bucket_key() {
  local ids id created
  ids=$(iam list-access-keys --user-name "$bucket_creator" | jq -r '.AccessKeyMetadata[].AccessKeyId')
  for id in $ids; do
    iam delete-access-key --user-name "$bucket_creator" --access-key-id "$id" > /dev/null
  done
  created=$(iam create-access-key --user-name "$bucket_creator")
  bucket_access=$(jq -r .AccessKey.AccessKeyId <<< "$created")
  trap drop_bucket_key EXIT
  bucket_secret=$(jq -r .AccessKey.SecretAccessKey <<< "$created")
}

# Empty if reconcile_identities just created it (or plans to).
creator_path=$(jq -r --arg n "$bucket_creator" '.Users[] | select(.UserName == $n) | .Path' <<< "$users")
if [[ -n $creator_path && $creator_path != "$managed_path" ]]; then
  # Already counted as a conflict; never mint a key for an unmanaged user.
  echo "reconcile: buckets not checked, $bucket_creator is not managed" >&2
else
  existing_buckets=''
  # Before the bucket creator exists, a dry run cannot list buckets.
  if ((!dry_run)) || [[ -n $creator_path ]]; then
    issue_bucket_key
    existing_buckets=$(creator_s3api list-buckets | jq -r '.Buckets[]?.Name')
  fi
  while IFS= read -r bucket; do
    [[ -n $bucket ]] || continue
    grep -qxF -- "$bucket" <<< "$existing_buckets" || change "create bucket $bucket" creator_s3api create-bucket --bucket "$bucket"
  done < <(jq -r '.buckets[]' "$desired")
fi

if ((dry_run)); then
  echo "reconcile: $changes change(s) planned, $conflicts conflict(s)"
else
  echo "reconcile: $changes change(s) applied, $conflicts conflict(s)"
fi
((conflicts == 0))
