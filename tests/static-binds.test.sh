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

# A failing generator must not truncate an existing static file.
printf -- '-- old static\n' >"$TMP/.config/hypr/switcher.lua"
mkdir -p "$TMP/failbin"
printf '#!/bin/sh\nexit 1\n' >"$TMP/failbin/node"
chmod +x "$TMP/failbin/node"
if HOME="$TMP" XDG_CONFIG_HOME="$TMP/.config" PATH="$TMP/failbin:$TMP/bin:$PATH" \
  "$ROOT/scripts/static-binds.sh" on >/dev/null 2>&1; then
  echo "static-binds: expected generation failure" >&2
  exit 1
fi
[[ $(cat "$TMP/.config/hypr/switcher.lua") == "-- old static" ]]
! grep -qF 'require("hypr.switcher")' "$TMP/.config/hypr/hyprland.lua"

run on >/dev/null
[[ -f $TMP/.config/hypr/switcher.lua ]]
ls "$TMP/.config/hypr"/switcher.lua.bak.* >/dev/null
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

# A dotfiles-managed hyprland.lua stays a symlink through on/off.
mkdir -p "$TMP/dotfiles"
rm -f "$TMP/.config/hypr/hyprland.lua"
printf -- '-- dotfiles config\n' >"$TMP/dotfiles/hyprland.lua"
ln -s "$TMP/dotfiles/hyprland.lua" "$TMP/.config/hypr/hyprland.lua"

run on >/dev/null
[[ -L $TMP/.config/hypr/hyprland.lua ]]
grep -qF 'require("hypr.switcher")' "$TMP/dotfiles/hyprland.lua"
run off >/dev/null
[[ -L $TMP/.config/hypr/hyprland.lua ]]
[[ $(cat "$TMP/dotfiles/hyprland.lua") == "-- dotfiles config" ]]

echo "static-binds: ok"
