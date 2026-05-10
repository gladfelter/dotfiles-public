#!/usr/bin/env bash
# Install pi agent config from dotfiles.
# Decrypts secrets with SSH key, writes auth.json, symlinks portable configs.
#
# Usage: ./install.sh [--apply]
#
# Default: dry-run (shows what would be written)
# --apply: actually write the files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$HOME/.pi/agent"
AGE_BIN="${AGE_BIN:-~/bin/age}"

# If age not in ~/bin, try PATH
if ! command -v "$AGE_BIN" &>/dev/null; then
  AGE_BIN="$(command -v age 2>/dev/null || true)"
fi

if [[ -z "$AGE_BIN" ]]; then
  echo "age not found. Install: https://github.com/FiloSottile/age"
  exit 1
fi

apply=false
for arg in "$@"; do
  if [[ "$arg" == "--apply" ]]; then
    apply=true
  fi
done

# Ensure target dir exists
mkdir -p "$PI_DIR"

# --- Decrypt secrets ---
secrets_file=$(mktemp)
trap 'rm -f "$secrets_file"' EXIT

if [[ ! -f "$SCRIPT_DIR/secrets.age.txt" ]]; then
  echo "secrets.age.txt not found in $(dirname "$SCRIPT_DIR")"
  exit 1
fi

ssh_key="$HOME/.ssh/id_github_key"
if [[ ! -f "$ssh_key" ]]; then
  echo "SSH key not found at $ssh_key. Ensure it's available."
  exit 1
fi

if ! "$AGE_BIN" -i "$ssh_key" -d "$SCRIPT_DIR/secrets.age.txt" > "$secrets_file" 2>/dev/null; then
  echo "Failed to decrypt secrets. Ensure your SSH key is available."
  exit 1
fi

# Parse secrets
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  declare "$key=$value"
done < "$secrets_file"

# Build auth.json
auth_content=$(cat <<ENDJSON
{
  "deepseek": {
    "type": "api_key",
    "key": "${PI_AUTH_DEEPSEEK_KEY}"
  }
}
ENDJSON
)

# Build web-search.json
web_search_content=$(cat <<ENDJSON
{
  "provider": "gemini",
  "searchModel": "gemini-flash-lite-latest",
  "geminiApiKey": "${PI_AUTH_GEMINI_KEY}"
}
ENDJSON
)

# --- Report ---
files_to_link=(
  "settings.json"
  "models.json"
)
files_to_write=(
  "auth.json"
  "web-search.json"
)

echo ""
echo "Would install ${#files_to_link[@]} symlink(s) and ${#files_to_write[@]} file(s) to $PI_DIR:"
for f in "${files_to_link[@]}"; do
  echo "  $f (symlink)"
done
for f in "${files_to_write[@]}"; do
  echo "  $f"
done

if $apply; then
  for f in "${files_to_link[@]}"; do
    rm -f "$PI_DIR/$f"
    ln -s "$SCRIPT_DIR/$f" "$PI_DIR/$f"
  done
  echo "$auth_content" > "$PI_DIR/auth.json"
  chmod 600 "$PI_DIR/auth.json"
  echo "$web_search_content" > "$HOME/.pi/web-search.json"
  chmod 600 "$HOME/.pi/web-search.json"
  echo ""
  echo "Applied. Pi agent config installed to $PI_DIR"
else
  echo ""
  echo "No changes written. Pass --apply to write to $PI_DIR"
fi
