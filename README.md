# Omarchy Switcher

A keyboard-first window switcher for [Omarchy](https://omarchy.org), built to
work directly with [Dropdown](https://github.com/ApachaiZ/omarchy-dropdown).

![Omarchy Switcher — Your windows. One shortcut.](preview.png)

- **Alt + Tab** cycles mapped Hyprland windows that Dropdown does **not** manage.
- **Ctrl + Tab** cycles only windows managed by Dropdown.
- A central overlay with a translucent, blurred backdrop.
- One icon card per window, with a centered stylized title above it.
- The selected card zooms and takes the mode's accent colour.
- **Alt-Tab** mode uses cyan; **Dropdown** mode uses violet, so the two
  contexts are immediately distinguishable.
- **Settings**: `Alt+S` / `Ctrl+S` inside the overlay (the modifier follows the
  mode), or the ⚙ button. There is no global settings shortcut, so the
  switcher never takes a key from the rest of the desktop.
- No screen capture. Icons are local; titles are rendered as plain text.


## Screenshots

| Windows | Dropdown windows |
| --- | --- |
| ![Windows](docs/screenshots/switcher-all.png) | ![Dropdown windows](docs/screenshots/switcher-dropdown.png) |

![Settings](docs/screenshots/switcher-settings.png)

## Install

```bash
omarchy plugin add https://github.com/ApachaiZ/omarchy-switcher --enable --yes
```

That is the whole install. The service registers its Hyprland shortcuts and
layer rule itself when the shell loads it, and re-registers them after every
Hyprland config reload. The plugin needs no files outside
`~/.config/omarchy/plugins/apach.switcher/`; the settings panel only stores
your choices in `~/.config/omarchy/switcher.json`.

The default bindings are:

| Shortcut | Action |
| --- | --- |
| `Alt + Tab` | cycle other windows |
| `Alt + Shift + Tab` | cycle other windows backwards |
| `Ctrl + Tab` | cycle Dropdown windows |
| `Ctrl + Shift + Tab` | cycle Dropdown windows backwards |

### Static bindings (optional)

If you want the shortcuts to live in Hyprland's config — for example so they
survive a stopped `omarchy-shell` — install the plugin once, then generate the
static file:

```bash
install -Dm644 \
  ~/.config/omarchy/plugins/apach.switcher/hypr/switcher.lua \
  ~/.config/hypr/switcher.lua
```

Add this line to `~/.config/hypr/hyprland.lua` (`scripts/static-binds.sh on`
does both steps from a checkout):

```lua
require("hypr.switcher")
```

Then reload:

```bash
hyprctl reload
```

When `~/.config/hypr/switcher.lua` exists, the service detects it and leaves
the keyboard integration entirely to that file. From a checkout,
`scripts/static-binds.sh off` removes that file and its `require` line (with
backups) and goes back to runtime bindings.

### How runtime bindings behave

- Hyprland drops binds and layer rules registered with `hyprctl eval` on every
  config reload. The service re-applies them on Hyprland's `configreloaded`
  event, so for a few milliseconds after a reload `Alt+Tab` belongs to
  Omarchy's default binds again.
- If `omarchy-shell` is not running, the runtime binds do nothing until the
  next reload. The static file above keeps the binds, but their IPC calls still
  need the service.
- Disabling the plugin unbinds its keys when the service is destroyed, so no
  dead shortcut is left behind. Hyprland's own defaults come back on the next
  reload (`hyprctl reload` or `omarchy restart shell`).

## Use

While the overlay is open:

- `Tab` / `Shift+Tab` or `←` / `→` move the selection;
- `Ctrl+Tab` switches the current overlay to Dropdown windows;
- `Alt+Tab` switches it back to other windows;
- `Enter` or `Space` activates the selection;
- `Escape` cancels;
- releasing Alt (all mode) or Ctrl (Dropdown mode) activates the selection;
- clicking a card activates it; clicking outside cancels.

A quick tap works too: if the modifier is released before the overlay maps, the
service checks the live modifier state and commits the initial selection.

## Settings and screens

Open the settings with the **⚙** button in the overlay, with **Alt+S** in the
all-windows mode, or with **Ctrl+S** in Dropdown mode (or **Super+S** if you
chose the Super+Tab preset). With the switcher closed there is no global
settings shortcut: open the overlay first.

The display section lets you choose between:

- **Active screen only** (on by default): the overlay follows the focused
  monitor;
- a **list of detected screens with a toggle each**: pick one or several
  monitors; the overlay is mirrored on every selected screen, with keyboard
  focus on the focused monitor when it is part of the selection (otherwise on
  the first selected screen).

Toggle rows with `Enter`/`Space` or the mouse. The screen names come from
Quickshell and are validated before being stored. `Ctrl+Tab` is only bound
when the **Dropdown plugin is enabled**; if Dropdown is absent or disabled,
the shortcut is left to the rest of the desktop and the hint omits it.

Choose the Dropdown shortcut from the keyboard (`↑`/`↓`, `Enter`) or with the
mouse:

- `Ctrl + Tab` (default)
- `Super + Tab`
- `Ctrl + Space`

The choice is written to `~/.config/omarchy/switcher.json` and applied
immediately: runtime bindings are re-registered in place, with no Hyprland
reload. Static installs also regenerate `~/.config/hypr/switcher.lua` and
reload Hyprland. The all-windows shortcut stays `Alt+Tab` so it cannot collide
with the Dropdown shortcut.

## Dropdown integration

The service reads Dropdown's state file only:

```
~/.local/state/omarchy/dropdown-state.json
```

It validates every address and app id before using it. Dropdown windows are
displayed with their real window title and app icon. A parked Dropdown window
is restored through Dropdown's own IPC (`omarchy-shell -q apach.dropdown
showApp <id>`), so its workspace, geometry and `dropdown-hidden` tag lifecycle
stay consistent. Non-Dropdown windows are focused by validated hex address.

Dropdown is not required: with it absent, the plugin still switches all
windows, and the Dropdown mode simply shows an empty-state message.

## Compatibility with `vbrosseau.alttab`

Do not enable both switchers at once: they compete for the same `Alt+Tab`
binding and both grab the keyboard exclusively. Disable the old plugin before
enabling Switcher.

## Security and privacy

- No network access, no screen capture, no window thumbnails.
- Window titles are rendered with `Text.PlainText`; markup or image tags in a
  title are displayed literally and never fetched.
- Icons come only from `DesktopEntries` and `Quickshell.iconPath`; icon names
  are restricted to desktop-entry syntax and `Image.source` accepts only local
  paths, `file://` or `image://`. No title, class or path is used as a URL.
- Window addresses are validated as `0x` hex before any Hyprland dispatch.
- Dropdown app ids are validated before being passed as a separate argv
  element; no shell command is built from window data.
- The state file is read locally and is never uploaded or logged.
- The IPC `status` method exposes counts and the selected index, never window
  titles or app ids.
- No history, screenshots or window contents are written to disk.
- `tests/qml-security.test.mjs` enforces plain text on every `Text`, forbids
  `ScreencopyView` and rejects shell command strings.

## Performance

- The client list is read with **one `hyprctl clients -j` process per open**.
  There is no polling while the switcher is closed.
- The overlay and its cards are created by a `LazyLoader` only while open and
  destroyed on close.
- No screencopy and no thumbnail cache: only app icons at 96×96, decoded
  asynchronously and cached by Qt.
- Animations are short opacity/scale transitions (110–140 ms) with no infinite
  animation.
- The Dropdown state file is a small `FileView` watcher; it contains only app
  ids and window addresses.

## Backdrop blur

The overlay uses a translucent dark panel and this layer rule, registered by
the service at runtime (or read from `hypr/switcher.lua` in static mode):

```lua
hl.layer_rule({ match = { namespace = "apach-switcher" }, blur = true, ignore_alpha = 0.15, no_anim = true })
```

Hyprland's blur must be enabled globally for the layer rule to take effect. If
`decoration:blur:enabled` is `false`, the panel still renders as a clean
translucent card without backdrop blur. Enable it in your Hyprland decoration
settings if you want the full glass effect.

## Development

```bash
node --test tests/*.test.mjs
omarchy plugin validate .

# Optional static bindings, from a checkout
scripts/static-binds.sh on
scripts/static-binds.sh off
scripts/static-binds.sh status
```

## License

MIT. See [LICENSE](LICENSE).
