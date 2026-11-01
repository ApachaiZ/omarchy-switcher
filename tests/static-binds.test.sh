#!/usr/bin/env bash
# Exercise the optional static bindings helper against a throwaway HOME and a
# stub hyprctl, so it never touches the caller's Hyprland configuration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/.config/hypr"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/hyprctl"
chmod +x "$TMP/bin/hyprctl"
printf -- '-- user config\n' >"$TMP/.config/hypr/hyprland.lua"
mkdir -p "$TMP/.config/omarchy"
printf '{"version":1,"allShortcut":"ALT + GRAVE","dropdownShortcut":"CTRL + SPACE"}\n' \
  >"$TMP/.config/omarchy/switcher.json"

run() {
  HOME="$TMP" XDG_CONFIG_HOME="$TMP/.config" PATH="$TMP/bin:$PATH" \
    "$ROOT/scripts/static-binds.sh" "$@"
}

[[ $(run status) == "runtime" ]]
run on >/dev/null
[[ -f $TMP/.config/hypr/switcher.lua ]]
grep -qF 'require("hypr.switcher")' "$TMP/.config/hypr/hyprland.lua"
grep -qF 'hl.layer_rule' "$TMP/.config/hypr/switcher.lua"
if command -v node >/dev/null 2>&1; then
  grep -qF 'o.bind("ALT + GRAVE"' "$TMP/.config/hypr/switcher.lua"
  grep -qF 'o.bind("CTRL + SPACE"' "$TMP/.config/hypr/switcher.lua"
fi
[[ $(run status) == "static" ]]
ls "$TMP/.config/hypr"/hyprland.lua.bak.* >/dev/null

run off >/dev/null
[[ ! -f $TMP/.config/hypr/switcher.lua ]]
! grep -qF 'require("hypr.switcher")' "$TMP/.config/hypr/hyprland.lua"
[[ $(run status) == "runtime" ]]
[[ $(cat "$TMP/.config/hypr/hyprland.lua") == "-- user config" ]]

# Running off twice is a no-op, not an error.
run off >/dev/null

echo "static-binds: ok"
