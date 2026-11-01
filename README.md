# Omarchy Switcher

A keyboard-first window switcher for [Omarchy](https://omarchy.org), built to
work directly with [Dropdown](https://github.com/ApachaiZ/omarchy-dropdown).

![Omarchy Switcher — Your windows. One shortcut.](preview.png)

- **Alt + Tab** (configurable) cycles mapped Hyprland windows that Dropdown
  does **not** manage.
- **Ctrl + Tab** cycles only windows managed by Dropdown.
- Binds are registered at runtime; no files outside the plugin folder.
- A central overlay with a translucent, blurred backdrop.
- One icon card per **application**, with a centered stylized title above it.
- Applications with several windows show a chevron and window count below the
  card; `↓` (or a click on the chevron) opens the list of their windows.
- Each card and each window row shows the monitor and workspace where the
  window lives (`HDMI-A-1 · 3`). Parked Dropdown windows are labelled
  `Dropdown`.
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

The all-windows shortcut can also be set to Alt + backtick (reverse
Alt + Shift + backtick) in Settings. `Super + Tab` is deliberately not offered:
Omarchy uses it for workspace switching.

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

When Node is available and `~/.config/omarchy/switcher.json` exists, the
helper generates the file from your current shortcuts; otherwise it copies the
shipped default. When `~/.config/hypr/switcher.lua` exists, the service detects
it and leaves the keyboard integration entirely to that file. From a checkout,
`scripts/static-binds.sh off` removes that file and its `require` line (with
backups) and goes back to runtime bindings.

### How runtime bindings behave

- Hyprland drops binds and layer rules registered with `hyprctl eval` on every
  config reload. The service re-applies them on Hyprland's `configreloaded`
  event, so for a few milliseconds after a reload the all-windows shortcut
  belongs to Omarchy's default binds again.
- After registering, the service compares `hyprctl binds -j` with the chords it
  expects and retries once if a bind did not land. Registration errors are
  reported in the settings panel and in `diagnose`.
- Changes are coalesced and deduplicated: one `hyprctl eval` at a time, and no
  process is spawned when the bind-relevant settings did not change.
- If `omarchy-shell` is not running, the runtime binds do nothing until the
  next reload. The static file above keeps the binds, but their IPC calls still
  need the service.
- Disabling the plugin unbinds its keys when the service is destroyed, so no
  dead shortcut is left behind. Hyprland's own defaults come back on the next
  reload (`hyprctl reload` or `omarchy restart shell`).
- Conflicts are reported, not resolved silently: if another tool (for example
  `vbrosseau.alttab`) owns one of the chords, the settings panel names it.

## Use

While the overlay is open:

- `Tab` / `Shift+Tab` or `←` / `→` move the selection between applications;
- `↓` opens the window list of an application that has several windows;
  `↑` / `↓` move inside it, and `↑` on the first row closes it again;
- `Ctrl+Tab` switches the current overlay to Dropdown windows;
- the all-windows shortcut switches it back to other windows;
- `Enter` or `Space` activates the selected window;
- `Escape` closes the window list first, then the switcher;
- releasing Alt (all mode) or Ctrl (Dropdown mode) activates the selection;
- clicking a card activates its most recent window, clicking a window row
  activates that window, and clicking outside cancels.

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
  monitors; the overlay is mirrored only on those screens. With **Active
  screen only** off it is intentionally not shown on the focused monitor
  unless that monitor is part of the selection, so a secondary-screen mirror
  stays a secondary-screen mirror. Keyboard control remains on the focused
  monitor in that case: a transparent input surface takes the keys there, so
  arrows and Tab never reach the window underneath.

Toggle rows with `Enter`/`Space` or the mouse. The screen names come from
Quickshell and are validated before being stored. `Ctrl+Tab` is only bound
when the **Dropdown plugin is enabled**; if Dropdown is absent or disabled,
the shortcut is left to the rest of the desktop and the hint omits it.

Choose the all-windows shortcut and the Dropdown shortcut from the keyboard
(`↑`/`↓`, `Enter`) or with the mouse:

- all windows: `Alt + Tab` (default) or Alt + backtick;
- Dropdown: `Ctrl + Tab` (default), `Super + Tab`, or `Ctrl + Space`.

Both choices are written to `~/.config/omarchy/switcher.json` and applied
immediately: runtime bindings are re-registered in place, with no Hyprland
reload. Static installs also regenerate `~/.config/hypr/switcher.lua` and
reload Hyprland. A shortcut cannot be used for both modes: choosing a
colliding value moves the Dropdown mode back to `Ctrl + Tab`.

The settings panel also reports the active binding mode (runtime or static
file), any registration error, and shortcuts that another tool already owns
on the same chords.

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
- The IPC `diagnose` method returns binding health, mode and shortcut names
  only. It never includes window titles, app ids, screen serials or the
  contents of the settings file.
- No history, screenshots or window contents are written to disk.
- `tests/qml-security.test.mjs` enforces plain text on every `Text`, forbids
  `ScreencopyView`, rejects shell command strings and checks that the generated
  bind expression is built only from the fixed preset table.

### Privacy and GDPR

The plugin has no network code, no telemetry, no analytics and no remote
endpoint. Everything it reads (window list, Dropdown state, settings, Hyprland
binds) stays on the machine and is processed in memory. The only persistent
data is `~/.config/omarchy/switcher.json` (shortcut and monitor choices), which
contains no personal data and is never transmitted. Removing the plugin and
that file removes everything the plugin wrote; the static file and its
`require` line, if used, are removed by `scripts/static-binds.sh off`. See
[PRIVACY.md](PRIVACY.md) for the short form.

## Performance

- The client list is read with **one `hyprctl clients -j` process per open**.
  There is no polling while the switcher is closed.
- The overlay and its cards are created by a `LazyLoader` only while open and
  destroyed on close.
- No screencopy and no thumbnail cache: only app icons at 96×96, decoded
  asynchronously and cached by Qt.
- Icon lookups are memoized per app id and capped at 128 entries, so reopening
  the overlay does not walk the desktop-entry database again.
- Bind registrations are deduplicated by a settings fingerprint, and run one
  at a time; no `hyprctl` process is spawned when nothing changed.
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

## Diagnostics

The plugin exposes two local IPC methods:

```bash
omarchy-shell -q apach.switcher status    # open state, counts, bind health
omarchy-shell -q apach.switcher diagnose  # mode, registration, conflicts
```

Neither returns window titles or app ids. Paste the output into a bug report
instead of screenshots of your windows.

## Development

```bash
node --test tests/*.test.mjs
node --check Model.js
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint Service.qml OverlayWindow.qml HyprBinds.qml

# Optional static bindings, from a checkout
scripts/static-binds.sh on
scripts/static-binds.sh off
scripts/static-binds.sh status
```

## License

MIT. See [LICENSE](LICENSE).
