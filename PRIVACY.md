# Privacy

The Switcher runs entirely on the local machine.

## What it processes

- The Hyprland client list (`hyprctl clients -j`), in memory, only while the
  overlay is open: window titles, classes, addresses, monitor ids and
  workspace names.
- `~/.local/state/omarchy/dropdown-state.json`, read locally to identify
  windows managed by Dropdown.
- `~/.config/omarchy/switcher.json`: the shortcuts and monitor choices you
  select in the settings panel.
- `hyprctl binds -j`, to verify that its shortcuts are registered and to warn
  about conflicts.

## What it stores

Only `~/.config/omarchy/switcher.json`. It contains shortcut names and monitor
names. Window titles, app ids and Dropdown state are never written to disk by
this plugin.

## What it never does

- No network access, no telemetry, no analytics, no crash reporting.
- No screen capture, screenshots or window thumbnails.
- No logging of window titles or app ids.
- No data shared with third parties.

## GDPR

The plugin does not collect, transmit or sell personal data, and there is no
remote processing. The only local configuration file can be deleted at any
time; removing the plugin and that file removes everything it wrote. If you
used 0.1.x static bindings, remove `~/.config/hypr/switcher.lua` and its
`require` line too.

Questions or corrections: open an issue on the project repository.
