#!/usr/bin/env bash
# Local install for a checkout. Marketplace installs use `omarchy plugin add`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST="$CONFIG_HOME/omarchy/plugins/apach.switcher"
HYPR_DIR="$CONFIG_HOME/hypr"
STAMP="$(date +%Y%m%d%H%M%S)"

mkdir -p "$(dirname "$DEST")" "$HYPR_DIR"
if [[ ! -d $DEST ]]; then
  mkdir -p "$DEST"
  rsync -a --exclude='.git' "$REPO/" "$DEST/"
else
  # Keep the installed copy in sync with this checkout.
  rsync -a --exclude='.git' "$REPO/" "$DEST/"
fi

if [[ ! -f $HYPR_DIR/switcher.lua ]]; then
  cp "$REPO/hypr/switcher.lua" "$HYPR_DIR/switcher.lua"
  echo "Created $HYPR_DIR/switcher.lua"
else
  echo "Kept existing $HYPR_DIR/switcher.lua"
fi

if [[ -f $HYPR_DIR/hyprland.lua ]] && ! grep -q 'require("hypr.switcher")' "$HYPR_DIR/hyprland.lua"; then
  cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.bak.$STAMP"
  printf '\nrequire("hypr.switcher")\n' >> "$HYPR_DIR/hyprland.lua"
  echo "Added require(\"hypr.switcher\") to $HYPR_DIR/hyprland.lua"
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable apach.switcher >/dev/null 2>&1 || true
hyprctl reload >/dev/null 2>&1 || true

cat <<EOF

Installed apach.switcher.

  All windows       Alt + Tab
  Dropdown only     Ctrl + Tab
  Settings          Super + Alt + S

Settings and shortcut presets: Super + Alt + S.
EOF
