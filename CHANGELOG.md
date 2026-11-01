# Changelog

## 0.3.0

### Added

- Runtime Hyprland integration: the service registers its binds and layer rule
  with `hyprctl eval`, so `omarchy plugin add` is the whole install.
- Re-registration on Hyprland's `configreloaded` event, with a live bind check
  and one automatic retry when a bind did not land.
- Configurable all-windows shortcut (`Alt + Tab` or Alt + backtick).
- Conflict warnings when another tool already owns one of the shortcut
  chords.
- Settings panel footer showing the active binding mode (runtime or static
  file), registration errors and conflicts.
- `diagnose` IPC method for local support reports, without window titles or app
  ids.
- `scripts/static-binds.sh on|off|status` for the optional static bindings
  file, with backups. `on` generates the file from the current shortcut
  settings when Node is available.
- `PRIVACY.md` and a GDPR section in the README.

### Changed

- The global `Super + Alt + S` settings shortcut is removed. Settings are
  reachable with `Alt + S` / `Ctrl + S` inside the overlay, or the gear button.
  `Super + Alt + S` belongs to Omarchy's scratchpad again.
- Dropdown is detected from the bar layout or the enabled plugin list, so a
  service-only Dropdown also gets the Dropdown shortcut.
- Icon lookups are memoized (128 entries maximum) and bind registrations are
  deduplicated by settings fingerprint.
- Registration is serialized: one `hyprctl eval` at a time.

### Removed

- `install.sh` and `uninstall.sh` at the repository root. A plugin must not
  suggest an install step that `omarchy plugin add` cannot perform.
- The `safeScreenName` and internal `bindEntries` exports from `Model.js`.

### Fixed

- Changing the Dropdown shortcut no longer leaves the previous chord bound
  until a reload.
- Disabling the plugin no longer leaves dead shortcut binds behind.
- A static `switcher.lua` without its `require` line is no longer mistaken for
  an active static install.

## 0.2.0

- Multi-screen display selection, English UI and the compact overlay.
