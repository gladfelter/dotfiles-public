#!/usr/bin/env bash
# Suggest apt packages from bash history that aren't already in the
# checked-in list.  Verifies each candidate is a real apt package before
# presenting it.
#
# Run interactively when you want to discover packages you've installed
# but haven't added to apt-packages.txt yet.
set -euo pipefail

HISTFILE="${HISTFILE:-$HOME/.bash_history}"
APT_LIST="$HOME/dotfiles/apt-packages.txt"

# ---- 1. read the checked-in apt list (plain file, one pkg per line) ------
checked=$(grep -vE '^[[:space:]]*(#|$)' "$APT_LIST" 2>/dev/null | sort -u)

# ---- 2. extract candidate packages from bash history ---------------------
candidates=$(
  grep -E '(sudo )?apt(-get)? install' "$HISTFILE" 2>/dev/null \
    | sed -E '
        s/sudo //
        s/apt-get /apt /
        s/apt install (-y|--yes) //
        s/apt install //
        s/#.*//
      ' \
    | tr ' ' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -vE '^(-y|--yes|)$' \
    | sort -u
)

# ---- 3. keep only candidates that are real, currently-installed packages -
real=()
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  if dpkg -s "$pkg" &>/dev/null; then
    real+=("$pkg")
  fi
done <<< "$candidates"

if [[ ${#real[@]} -eq 0 ]]; then
  echo "No real apt packages found in history."
  exit 0
fi

# ---- 4. set subtraction: candidates \ checked = new ----------------------
# comm -13: suppress lines only in checked (-1) and common (-3),
#           showing only lines that are in candidates but not in checked (-2).
new=$(
  comm -13 \
    <(echo "$checked") \
    <(printf '%s\n' "${real[@]}" | sort -u)
)

# ---- 5. report -----------------------------------------------------------
echo "Already in apt-packages.txt:"
comm -12 \
  <(echo "$checked") \
  <(printf '%s\n' "${real[@]}" | sort -u) \
  | sed 's/^/  ✓  /'

echo ""
echo "New (not yet in apt-packages.txt):"
if [[ -z "$new" ]]; then
  echo "  (none)"
else
  echo "$new" | sed 's/^/  ✦  /'
  echo ""
  echo "To add them, append to apt-packages.txt and run capture_packages.sh."
fi
