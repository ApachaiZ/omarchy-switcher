#!/usr/bin/env bash
# Local install for a checkout. Marketplace installs use `omarchy plugin add`
# alone: the service registers its own Hyprland binds and layer rule at
# runtime, so nothing is written outside the plugin directory.
#
#   --static-binds   generate ~/.config/hypr/switcher.lua and require it
#   --runtime-binds  remove those files and go back to runtime bindings
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DEST="$CONFIG_HOME/omarchy/plugins/apach.switcher"
HYPR_DIR="$CONFIG_HOME/hypr"
STAMP="$(date +%Y%m%d%H%M%S)"

MODE="install"
for arg in "$@"; do
  case "$arg" in
  --static-binds)
    MODE="static"
    ;;
  --runtime-binds)
    MODE="runtime"
    ;;
  -h | --help)
    cat <<USAGE
Usage: ./install.sh [--static-binds | --runtime-binds]

Installs this checkout into $CONFIG_HOME/omarchy/plugins/apach.switcher.
By default the plugin owns its shortcuts at runtime and writes nothing outside
that directory.

--static-binds   also writes ~/.config/hypr/switcher.lua and requires it from
                 hyprland.lua. Only needed if the binds must live in Hyprland's
                 config, for example to survive a stopped shell.
--runtime-binds  removes that generated file and its require line (with a
                 backup) so the plugin owns the shortcuts again.
USAGE
    exit 0
    ;;
  *)
    echo "install.sh: unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

mkdir -p "$(dirname "$DEST")" "$HYPR_DIR"
rsync -a --exclude='.git' "$REPO/" "$DEST/"

if [[ $MODE == static ]]; then
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
elif [[ $MODE == runtime ]]; then
  if [[ -f $HYPR_DIR/hyprland.lua ]] && grep -q 'require("hypr.switcher")' "$HYPR_DIR/hyprland.lua"; then
    cp "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.lua.bak.$STAMP"
    sed -i '/require("hypr.switcher")/d' "$HYPR_DIR/hyprland.lua"
    echo "Removed require(\"hypr.switcher\") from $HYPR_DIR/hyprland.lua"
  fi
  if [[ -f $HYPR_DIR/switcher.lua ]]; then
    mv "$HYPR_DIR/switcher.lua" "$HYPR_DIR/switcher.lua.bak.$STAMP"
    echo "Moved $HYPR_DIR/switcher.lua to switcher.lua.bak.$STAMP"
  fi
elif [[ -f $HYPR_DIR/switcher.lua ]]; then
  echo "Static bindings found: $HYPR_DIR/switcher.lua takes precedence."
  echo "Run ./install.sh --runtime-binds to let the plugin own the shortcuts."
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable apach.switcher >/dev/null 2>&1 || true
if [[ $MODE != install ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi

cat <<EOF

Installed apach.switcher.

  All windows       Alt + Tab
  Dropdown only     Ctrl + Tab
  Settings          Alt + S inside the switcher

Settings and shortcut presets: Alt + S inside the switcher
(Ctrl + S when it is showing Dropdown windows).
If the plugin was already enabled, load the updated service with:
  omarchy restart shell
EOF
