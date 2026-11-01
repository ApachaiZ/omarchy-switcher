#!/usr/bin/env bash
# Remove the plugin and its keyboard integration. User settings are kept.
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST="$CONFIG_HOME/omarchy/plugins/apach.switcher"
HYPR_DIR="$CONFIG_HOME/hypr"

omarchy plugin disable apach.switcher >/dev/null 2>&1 || true

if [[ -f $HYPR_DIR/hyprland.lua ]]; then
  cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.bak.$(date +%Y%m%d%H%M%S)"
  sed -i '/require("hypr.switcher")/d' "$HYPR_DIR/hyprland.lua"
fi

rm -f "$HYPR_DIR/switcher.lua"
rm -rf "$DEST"

hyprctl reload >/dev/null 2>&1 || true

cat <<EOF
Removed apach.switcher.
Kept:
  $CONFIG_HOME/omarchy/switcher.json
EOF
