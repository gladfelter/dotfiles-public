#!/usr/bin/env bash
# Capture explicitly-installed packages from npm and pipx, writing lists
# to the dotfiles root so install_configs.sh can restore them on a new machine.
#
# Run this whenever you add or remove global npm/pipx packages.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- npm ---
NPM_OUT="$SCRIPT_DIR/npm-packages.txt"
if command -v npm &>/dev/null; then
  npm ls -g --depth=0 --json 2>/dev/null \
    | python3 -c "
import json, sys
deps = json.load(sys.stdin).get('dependencies', {})
for name in sorted(deps.keys()):
    print(name)
" > "$NPM_OUT"
  echo "npm:  captured $(wc -l < "$NPM_OUT") packages → npm-packages.txt"
else
  echo "npm:  not found, skipping"
fi

# --- pipx ---
PIPX_OUT="$SCRIPT_DIR/pipx-packages.txt"
if command -v pipx &>/dev/null; then
  pipx list --json 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
venvs = data.get('venvs', {})
pkgs = set()
for name, info in venvs.items():
    pkgs.add(name)
    for inj in info.get('metadata', {}).get('injected_packages', {}).keys():
        pkgs.add(inj)
for name in sorted(pkgs):
    print(name)
" > "$PIPX_OUT"
  count=$(wc -l < "$PIPX_OUT")
  if [[ "$count" -eq 0 ]]; then
    echo "pipx: 0 packages, wrote empty pipx-packages.txt"
  else
    echo "pipx: captured $count packages → pipx-packages.txt"
  fi
else
  echo "pipx: not found, skipping"
fi

echo ""
echo "Done. Review the files and commit:"
echo "  $NPM_OUT"
echo "  $PIPX_OUT"
