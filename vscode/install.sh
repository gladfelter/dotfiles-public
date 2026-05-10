#!/usr/bin/env bash
# Install VS Code WSL-specific settings from dotfiles.
#
# Writes to the WSL remote settings directory so Windows projects
# keep default VS Code settings.
#
# Usage: ./install.sh [--apply]
#
# Default: dry-run (shows what would be written)
# --apply: actually write the files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apply=false
for arg in "$@"; do
  if [[ "$arg" == "--apply" ]]; then
    apply=true
  fi
done

# Detect Windows VS Code remote settings location
# Remote settings live on the Windows side:
#   %APPDATA%\Code\User\remote\wsl+<distro>\
if [[ -d "/mnt/c/Users" ]]; then
  for user in /mnt/c/Users/*/; do
    candidate="${user}AppData/Roaming/Code/User/remote"
    if [[ -d "$candidate" ]]; then
      # Find the WSL remote folder
      remote_dir="$candidate"
      break
    fi
  done
  if [[ -z "${remote_dir:-}" ]]; then
    # Remote folder doesn't exist yet — find first user
    for user in /mnt/c/Users/*/; do
      [[ -d "${user}AppData/Roaming/Code" ]] && {
        remote_dir="${user}AppData/Roaming/Code/User/remote"
        break
      }
    done
  fi
else
  echo "Windows filesystem not mounted (WSL expected)"
  exit 1
fi

# Use distro name for the remote subfolder
distro="${WSL_DISTRO_NAME:-Ubuntu}"
vscode_dir="$remote_dir/wsl+$distro"

mkdir -p "$vscode_dir"

# Check if 'code' CLI is available (requires WSL Server Connector)
has_code=false
if command -v code &>/dev/null; then
  has_code=true
fi

# --- Report ---
files_to_write=(
  "settings.json"
  "mcp.json"
)

# Count extensions
ext_count=0
if [[ -f "$SCRIPT_DIR/extensions.json" ]]; then
  ext_count=$(wc -l < "$SCRIPT_DIR/extensions.json")
  ext_count=$((ext_count > 0 ? ext_count : 0))
fi

echo ""
echo "Would install ${#files_to_write[@]} file(s) to $vscode_dir (wsl+$distro):"
for f in "${files_to_write[@]}"; do
  echo "  $f"
done
if [[ $ext_count -gt 0 ]]; then
  echo "  $ext_count extension(s)"
  if ! $has_code; then
    echo ""
    echo "NOTE: 'code' CLI not available. Extensions will be skipped."
    echo "To install them, open VS Code → Extensions → search for each,"
    echo "or run: code --install-extension <extension-id>"
  fi
fi

# Check if there's a diff to show
has_diff=false
if [[ -f "$vscode_dir/settings.json" ]]; then
  if ! diff -q "$SCRIPT_DIR/wsl-settings.json" "$vscode_dir/settings.json" &>/dev/null; then
    has_diff=true
  fi
else
  has_diff=true
fi

if $apply; then
  # Show diff and prompt if there are changes
  if $has_diff; then
    echo ""
    echo "Diff (current → dotfiles):"
    if [[ -f "$vscode_dir/settings.json" ]]; then
      diff -u "$vscode_dir/settings.json" "$SCRIPT_DIR/wsl-settings.json" || true
    else
      echo "  (no existing settings.json — will create new)"
    fi
    read -r -p "Apply changes? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Skipped."
      exit 0
    fi
  else
    echo ""
    echo "No changes — settings already match dotfiles."
  fi

  cp "$SCRIPT_DIR/wsl-settings.json" "$vscode_dir/settings.json"
  if [[ -f "$SCRIPT_DIR/mcp.json" ]]; then
    cp "$SCRIPT_DIR/mcp.json" "$vscode_dir/mcp.json"
  fi
  if [[ -f "$SCRIPT_DIR/extensions.json" && $ext_count -gt 0 && "$has_code" == "true" ]]; then
    echo ""
    echo "Installing $ext_count extension(s)..."
    while IFS= read -r ext; do
      [[ -z "$ext" ]] && continue
      echo "  Installing: $ext"
      code --install-extension "$ext" || echo "    (skipped — $ext already installed or failed)"
    done < "$SCRIPT_DIR/extensions.json"
  fi
  echo ""
  echo "Applied. VS Code WSL settings installed to $vscode_dir"
  echo "Windows projects keep default VS Code settings."
  echo "Restart VS Code (or Ctrl+Shift+P → Reload Window) to apply changes."
else
  echo ""
  echo "No changes written. Pass --apply to write to $vscode_dir"
fi
