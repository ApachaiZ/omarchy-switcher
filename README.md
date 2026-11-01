# Omarchy Switcher

A keyboard-first window switcher for [Omarchy](https://omarchy.org), built to
work directly with [Dropdown](https://github.com/ApachaiZ/omarchy-dropdown).

- **Alt + Tab** cycles every mapped Hyprland window.
- **Ctrl + Tab** cycles only windows managed by Dropdown.
- A central overlay with a translucent, blurred backdrop.
- One icon card per window, with a centered stylized title above it.
- The selected card zooms and takes the mode's accent colour.
- **Alt-Tab** mode uses cyan; **Dropdown** mode uses violet, so the two
  contexts are immediately distinguishable.
- No screen capture. Icons are local; titles are rendered as plain text.

## Install

```bash
omarchy plugin add https://github.com/ApachaiZ/omarchy-switcher --enable --yes
```

The plugin directory contains the Hyprland integration file. Install it once:

```bash
install -Dm644 \
  ~/.config/omarchy/plugins/apach.switcher/hypr/switcher.lua \
  ~/.config/hypr/switcher.lua
```

Add this line to `~/.config/hypr/hyprland.lua` (or run `./install.sh` from a
checkout, which does both steps):

```lua
require("hypr.switcher")
```

Then reload:

```bash
hyprctl reload
```

The default bindings are:

| Shortcut | Action |
| --- | --- |
| `Alt + Tab` | cycle all windows |
| `Alt + Shift + Tab` | cycle all windows backwards |
| `Ctrl + Tab` | cycle Dropdown windows |
| `Ctrl + Shift + Tab` | cycle Dropdown windows backwards |
| `Super + Alt + S` | open Switcher settings |

## Use

While the overlay is open:

- `Tab` / `Shift+Tab` or `←` / `→` move the selection;
- `Ctrl+Tab` switches the current overlay to Dropdown windows;
- `Alt+Tab` switches it back to all windows;
- `Enter` or `Space` activates the selection;
- `Escape` cancels;
- releasing Alt (all mode) or Ctrl (Dropdown mode) activates the selection;
- clicking a card activates it; clicking outside cancels.

A quick tap works too: if the modifier is released before the overlay maps, the
service checks the live modifier state and commits the initial selection.

## Settings

`Super + Alt + S` opens the Switcher settings overlay. Choose the Dropdown
shortcut from the keyboard (`↑`/`↓`, `Enter`) or with the mouse:

- `Ctrl + Tab` (default)
- `Super + Tab`
- `Ctrl + Space`

The choice is written to `~/.config/omarchy/switcher.json` and the generated
`~/.config/hypr/switcher.lua`, then Hyprland is reloaded. The all-windows
shortcut stays `Alt+Tab` so it cannot collide with the Dropdown shortcut.

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
- Icons come only from `DesktopEntries` and `Quickshell.iconPath`; no title,
  class or path is used as a URL.
- Window addresses are validated as `0x` hex before any Hyprland dispatch.
- Dropdown app ids are validated before being passed as a separate argv
  element; no shell command is built from window data.
- The state file is read locally and is never uploaded or logged.
- The IPC `status` method exposes counts and the selected index, never window
  titles or app ids.
- No history, screenshots or window contents are written to disk.

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

The overlay uses a translucent dark panel and the layer rule in
`hypr/switcher.lua`:

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
```

## License

MIT. See [LICENSE](LICENSE).
