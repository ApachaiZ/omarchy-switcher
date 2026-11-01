#!/usr/bin/env bash
# Optional static install for the Switcher's Hyprland integration.
#
# A normal install needs none of this: the service registers its binds at
# runtime. Use this helper only when the binds must live in Hyprland's config,
# for example to keep them working while omarchy-shell is stopped.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_DIR="$CONFIG_HOME/hypr"
BINDS="$HYPR_DIR/switcher.lua"
HYPRLAND="$HYPR_DIR/hyprland.lua"
REQUIRE='require("hypr.switcher")'
STAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<USAGE
Usage: scripts/static-binds.sh on|off|status

on      Write $BINDS from this checkout, require it from hyprland.lua,
        and reload Hyprland.
off     Remove the require line (with a backup), move the generated file
        aside, and reload Hyprland so the plugin owns the shortcuts again.
status  Print whether static bindings are active.
USAGE
}

require_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || {
    echo "static-binds.sh: hyprctl is not available; is Hyprland installed?" >&2
    exit 1
  }
}

case "${1:-}" in
on)
  require_hyprland
  mkdir -p "$HYPR_DIR"
  cp "$REPO/hypr/switcher.lua" "$BINDS"
  echo "Wrote $BINDS"

  if [[ -f $HYPRLAND ]] && ! grep -qF "$REQUIRE" "$HYPRLAND"; then
    cp "$HYPRLAND" "$HYPRLAND.bak.$STAMP"
    printf '\n%s\n' "$REQUIRE" >> "$HYPRLAND"
    echo "Added $REQUIRE to $HYPRLAND"
    echo "Backup: $HYPRLAND.bak.$STAMP"
  elif [[ ! -f $HYPRLAND ]]; then
    echo "$HYPRLAND not found; add this line to your Hyprland config:" >&2
    echo "  $REQUIRE" >&2
  fi

  hyprctl reload >/dev/null
  echo "Static bindings active. The service now leaves the keys to this file."
  ;;
off)
  require_hyprland
  if [[ -f $HYPRLAND ]] && grep -qF "$REQUIRE" "$HYPRLAND"; then
    cp "$HYPRLAND" "$HYPRLAND.bak.$STAMP"
    # Keep the original inode and permissions: writing through cat back into
    # the file avoids `sed -i` replacing it and avoids regex metacharacters in
    # the require line.
    tmp="$(mktemp)"
    grep -vF "$REQUIRE" "$HYPRLAND" >"$tmp" || true
    cat "$tmp" >"$HYPRLAND"
    rm -f "$tmp"
    echo "Removed $REQUIRE from $HYPRLAND"
    echo "Backup: $HYPRLAND.bak.$STAMP"
  fi
  if [[ -f $BINDS ]]; then
    mv "$BINDS" "$BINDS.bak.$STAMP"
    echo "Moved $BINDS to $BINDS.bak.$STAMP"
  fi
  hyprctl reload >/dev/null
  echo "Runtime bindings active."
  ;;
status)
  if [[ -f $BINDS ]] && [[ -f $HYPRLAND ]] && grep -qF "$REQUIRE" "$HYPRLAND"; then
    echo "static"
  elif [[ -f $BINDS ]]; then
    echo "static file present but not required by hyprland.lua"
  else
    echo "runtime"
  fi
  ;;
-h | --help | help)
  usage
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
