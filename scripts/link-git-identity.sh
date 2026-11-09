set -eu

context=$1
base=$2
hosts_source=$3
config_source=$4
org=$(cat "$context/org")
user=$(cat "$context/user")
for value in "$org" "$user"; do
  case "$value" in
    ''|*[!a-zA-Z0-9-]*|-*|*-) echo 'Invalid GitHub organization or user' >&2; exit 1 ;;
  esac
done
for field in author_name author_email; do
  value=$(cat "$context/$field")
  case "$value" in
    ''|*"'"*|*'
'*) echo 'Invalid Git author value' >&2; exit 1 ;;
  esac
done

for name in hosts config; do
  case "$name" in
    hosts) source=$hosts_source ;;
    config) source=$config_source ;;
  esac
  destination="$context/gh/$name.yml"
  if [ ! -e "$destination" ] || [ -L "$destination" ]; then
    tmp=$(mktemp "$context/gh/.${name}.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    cp "$source" "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$destination"
  fi
done

target="$base/$org"
mkdir -p "$target"
for name in .gh .envrc; do
  if [ -e "$target/$name" ] && [ ! -L "$target/$name" ]; then
    echo "Refusing to replace existing $name" >&2
    exit 1
  fi
done
ln -sfn "$context/gh" "$target/.gh"
ln -sfn "$context/envrc" "$target/.envrc"
