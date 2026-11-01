import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  // all | dropdown | settings
  property string mode: "all"
  property bool open: false
  property var entries: []
  // One card per application; selected indexes groups, not windows.
  readonly property var groups: Model.groupEntries(entries)
  readonly property var selectedGroup: groups[selected] || null
  property int selected: -1
  property bool expanded: false
  property int subIndex: 0
  property var dropdownWindows: ({})
  property var settings: Model.defaultSettings()
  property string pendingMode: "all"
  property bool pendingReverse: false
  property bool sawKeyEvent: false
  property var pendingEntry: null
  property bool dropdownEnabled: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string settingsPath: home + "/.config/omarchy/switcher.json"
  readonly property string dropdownStatePath: home + "/.local/state/omarchy/dropdown-state.json"

  property bool settingsLoaded: false
  readonly property color themeAccent: Commons.Color.accent
  readonly property color popupText: Commons.Color.popups.text
  readonly property color popupBackground: Commons.Color.popups.background
  // Keep the Dropdown mode clearly distinct without leaving the active theme:
  // rotate the theme accent's hue toward violet and reuse its saturation.
  readonly property color accent: mode === "dropdown"
    ? Qt.hsla((themeAccent.hslHue + 0.25) % 1.0,
        Math.max(0.5, themeAccent.hslSaturation),
        Math.min(0.72, themeAccent.hslLightness + 0.06), 1.0)
    : themeAccent
  readonly property string modeLabel: mode === "dropdown" ? "DROPDOWN WINDOWS" : "WINDOWS"
  readonly property var allPresets: Model.allShortcutPresets()
  readonly property var allPreset: Model.allPresetForKey(settings.allShortcut)
  readonly property var presets: Model.shortcutPresets()
  readonly property var dropdownPreset: Model.presetForKey(settings.dropdownShortcut)
  readonly property bool dropdownUsesSuper: dropdownPreset.key.indexOf("SUPER") === 0
  readonly property int dropdownModifier: dropdownUsesSuper ? Qt.MetaModifier : Qt.ControlModifier
  readonly property string settingsHint: mode === "dropdown"
    ? (dropdownUsesSuper ? "Super+S" : "Ctrl+S") : "Alt+S"
  readonly property string modeHint: {
    var parts = []
    if (mode === "dropdown") parts.push(dropdownPreset.label)
    else {
      parts.push(allPreset.label)
      if (dropdownEnabled) parts.push(dropdownPreset.label + " for Dropdown")
    }
    parts.push("Tab/Shift+Tab")
    if (selectedGroup && selectedGroup.entries.length > 1)
      parts.push(expanded ? "↑/↓ windows" : "↓ windows")
    parts.push("Enter")
    parts.push("Esc")
    parts.push(settingsHint + " settings")
    return parts.join(" · ")
  }

  readonly property var targetScreen: {
    var monitor = Hyprland.focusedMonitor
    if (monitor) {
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === monitor.name) return Quickshell.screens[i]
    }
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  readonly property var screenNames: {
    var out = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var name = String(Quickshell.screens[i].name || "")
      if (name && out.indexOf(name) === -1) out.push(name)
    }
    return out
  }

  readonly property string activeScreenName: targetScreen ? String(targetScreen.name || "") : ""

  function screenForName(name) {
    var wanted = String(name || "")
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (String(Quickshell.screens[i].name || "") === wanted) return Quickshell.screens[i]
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  // "Active screen only" renders on the focused monitor; otherwise only the
  // selected screens, with the focused one as a fallback when the selection is
  // not connected.
  readonly property var displayScreens: Model.displayScreensFor(settings, screenNames, activeScreenName)

  // When the overlay is mirrored only on other screens, the focused monitor
  // still needs a surface to own the keyboard; otherwise arrows and Tab reach
  // the window underneath. InputSurface provides that without drawing there.
  readonly property bool needsInputSurface: root.open && root.mode !== "settings"
    && root.activeScreenName !== "" && root.displayScreens.indexOf(root.activeScreenName) === -1

  readonly property var settingsItems: {
    var items = []
    for (var a = 0; a < allPresets.length; a++)
      items.push({ kind: "allPreset", preset: allPresets[a], label: allPresets[a].label, itemIndex: items.length })
    for (var p = 0; p < presets.length; p++)
      items.push({ kind: "preset", preset: presets[p], label: presets[p].label, itemIndex: items.length })
    items.push({ kind: "active", label: "Active screen only", selected: settings.followActive, itemIndex: items.length })
    for (var i = 0; i < screenNames.length; i++)
      items.push({ kind: "screen", name: screenNames[i], label: screenNames[i],
        selected: settings.screens.indexOf(screenNames[i]) !== -1, itemIndex: items.length })
    return items
  }

  readonly property var allItems: settingsItems.filter(function(item) { return item.kind === "allPreset" })
  readonly property var dropdownItems: settingsItems.filter(function(item) { return item.kind === "preset" })
  readonly property var displayItems: settingsItems.filter(function(item) {
    return item.kind === "active" || item.kind === "screen"
  })

  // Read-only projection of HyprBinds for the settings panel, which is a
  // separate component and cannot reference this file's ids.
  readonly property string bindsMode: hyprBinds.mode
  readonly property string bindsStatus: hyprBinds.status
  readonly property string bindsError: hyprBinds.lastError
  readonly property var bindsConflicts: hyprBinds.conflicts

  Component.onCompleted: {
    settingsFile.reload()
    dropdownFile.reload()
    shellConfigFile.reload()
  }

  HyprBinds {
    id: hyprBinds
    settings: root.settings
    dropdownEnabled: root.dropdownEnabled
    settingsLoaded: root.settingsLoaded
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.settings = Model.parseSettings(text())
      root.settingsLoaded = true
    }
    onLoadFailed: {
      root.settings = Model.defaultSettings()
      root.settingsLoaded = true
    }
    onFileChanged: reload()
  }

  FileView {
    id: dropdownFile
    path: root.dropdownStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.dropdownWindows = Model.parseDropdownState(text())
    onLoadFailed: root.dropdownWindows = ({})
    onFileChanged: reload()
  }

  FileView {
    id: shellConfigFile
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var enabled = Model.dropdownEnabledFromShellConfig(text())
      root.dropdownEnabled = enabled
      if (!enabled && root.open && root.mode === "dropdown") root.cancel()
    }
    onLoadFailed: root.dropdownEnabled = false
    onFileChanged: reload()
  }

  // Writable only: HyprBinds owns detection and registration. This view keeps
  // the optional static file in sync with the chosen shortcuts.
  FileView {
    id: bindsFile
    path: hyprBinds.staticPath
    printErrors: false
  }

  // Theme switches can change the icon theme without restarting the shell.
  FileView {
    path: root.home + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      root.clearIconCache()
      reload()
    }
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onClients(text)
    }
  }

  Process {
    id: modCheck
    command: ["hyprctl", "eval", "error(tostring(" + root.modifierExpr + "))"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.open || root.sawKeyEvent) return
        if (!text.trim().endsWith("true")) root.commit()
      }
    }
  }

  Process {
    id: hyprReload
    command: ["hyprctl", "reload"]
    running: false
  }

  readonly property string modifierExpr: mode === "dropdown"
    ? (dropdownUsesSuper
      ? 'hl.is_key_down("Super_L") or hl.is_key_down("Super_R")'
      : 'hl.is_key_down("Control_L") or hl.is_key_down("Control_R")')
    : 'hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")'

  Timer {
    id: modTimer
    interval: 140
    repeat: false
    onTriggered: if (root.open && !root.sawKeyEvent) modCheck.running = true
  }

  Timer {
    id: activationTimer
    interval: 80
    repeat: false
    onTriggered: {
      var entry = root.pendingEntry
      root.pendingEntry = null
      root.activate(entry)
    }
  }

  Timer {
    id: reloadTimer
    interval: 120
    repeat: false
    onTriggered: hyprReload.running = true
  }

  function onClients(raw) {
    if (!root.pendingMode) return
    var list = Model.parseClients(raw, root.dropdownWindows, root.pendingMode)
    var grouped = Model.groupEntries(list)
    root.entries = list
    root.mode = root.pendingMode
    root.pendingMode = root.mode
    root.selected = Model.initialIndex(grouped.length, root.pendingReverse)
    root.expanded = false
    root.subIndex = 0
    root.pendingReverse = false
    root.sawKeyEvent = false
    root.open = true
    modTimer.restart()
  }

  function openMode(nextMode, reverse) {
    if (nextMode === "settings") {
      openSettings()
      return
    }
    if (nextMode === "dropdown" && !root.dropdownEnabled) return
    if (root.open && root.mode === nextMode) {
      cycle(reverse ? -1 : 1)
      return
    }
    if (root.open) {
      root.switchMode(nextMode, reverse)
      return
    }
    if (clientsProc.running) return
    root.pendingMode = nextMode
    root.pendingReverse = !!reverse
    clientsProc.running = true
  }

  function switchMode(nextMode, reverse) {
    if (nextMode === "dropdown" && !root.dropdownEnabled) return
    if (root.pendingMode === nextMode && clientsProc.running) return
    root.pendingMode = nextMode
    root.pendingReverse = !!reverse
    clientsProc.running = true
  }

  function cycle(delta) {
    if (!root.groups.length || root.selected < 0) return
    root.expanded = false
    root.subIndex = 0
    root.selected = (root.selected + delta + root.groups.length) % root.groups.length
  }

  // GNOME-style submenu for applications with several windows: Down opens it
  // on the selected card, Up/Down move inside it, Up at the first row closes
  // it, and committing uses the highlighted window.
  function expandSelected() {
    var group = root.selectedGroup
    if (!group || group.entries.length < 2) return
    root.expanded = true
    root.subIndex = 0
  }

  function cycleSub(delta) {
    var group = root.selectedGroup
    if (!group || group.entries.length === 0) return
    root.subIndex = (root.subIndex + delta + group.entries.length) % group.entries.length
  }

  function collapseSub() {
    if (root.subIndex > 0) root.subIndex--
    else root.expanded = false
  }

  function selectedWindow() {
    var group = root.selectedGroup
    if (!group || group.entries.length === 0) return null
    if (root.expanded) return group.entries[root.subIndex] || group.entries[0]
    return group.entries[0]
  }

  function cancel() {
    if (!root.open) return
    root.open = false
    root.pendingEntry = null
    root.entries = []
    root.selected = -1
    root.expanded = false
    root.subIndex = 0
  }

  function commit(target) {
    var entry = target !== undefined ? target : root.selectedWindow()
    root.open = false
    root.pendingEntry = entry
    root.entries = []
    root.selected = -1
    root.expanded = false
    root.subIndex = 0
    if (entry) activationTimer.restart()
  }

  function activate(entry) {
    if (!entry) return
    // A parked Dropdown window must be brought back through Dropdown so its
    // workspace, geometry and tag lifecycle stay consistent. Only the app id
    // is passed, as an argv element, and only after validation.
    if (entry.hidden && Model.validAppId(entry.appId)) {
      Quickshell.execDetached(["omarchy-shell", "-q", "apach.dropdown", "showApp", entry.appId])
      return
    }
    var address = Model.validAddress(entry.addr)
    if (!address) return
    Quickshell.execDetached(["hyprctl", "dispatch",
      "hl.dsp.focus({ window = \"address:" + address + "\" })"])
    Quickshell.execDetached(["hyprctl", "dispatch",
      "hl.dsp.window.bring_to_top({ window = \"address:" + address + "\" })"])
  }

  function handlePressed(event) {
    root.sawKeyEvent = true
    if (event.key === Qt.Key_Escape) {
      if (root.expanded) {
        root.expanded = false
        root.subIndex = 0
      } else {
        root.cancel()
      }
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down) {
      if (root.expanded) root.cycleSub(1)
      else root.expandSelected()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up) {
      if (root.expanded) root.collapseSub()
      event.accepted = true
      return
    }
    var reverse = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) !== 0
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      if (root.dropdownEnabled && (event.modifiers & root.dropdownModifier) && root.mode !== "dropdown") {
        root.switchMode("dropdown", reverse)
      } else if ((event.modifiers & Qt.AltModifier) && root.mode !== "all") {
        root.switchMode("all", reverse)
      } else {
        root.cycle(reverse ? -1 : 1)
      }
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right) {
      root.cycle(1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left) {
      root.cycle(-1)
      event.accepted = true
      return
    }
    var settingsModifier = root.mode === "dropdown" ? root.dropdownModifier : Qt.AltModifier
    if (event.key === Qt.Key_S && !event.isAutoRepeat &&
        ((event.modifiers & settingsModifier) !== 0 ||
         (event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) === 0)) {
      root.openSettings()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.commit()
      event.accepted = true
    }
  }

  function handleReleased(event) {
    root.sawKeyEvent = true
    var isSuper = root.mode === "dropdown" && root.dropdownUsesSuper
    var target = root.mode === "dropdown"
      ? (isSuper ? [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R] : [Qt.Key_Control])
      : [Qt.Key_Alt]
    for (var i = 0; i < target.length; i++) {
      if (event.key === target[i]) {
        root.commit()
        return
      }
    }
    var modifier = root.mode === "dropdown"
      ? (isSuper ? Qt.MetaModifier : Qt.ControlModifier)
      : Qt.AltModifier
    if ((event.modifiers & modifier) === 0) root.commit()
  }

  // Icon lookup walks desktop entries and the icon theme; the overlay is
  // rebuilt on every open, so memoize by app id. Bounded to keep RAM flat in
  // long sessions, and cleared when the theme changes so a new icon theme is
  // picked up without a shell restart.
  property var iconCache: ({})
  property var iconCacheOrder: []

  function clearIconCache() {
    root.iconCache = ({})
    root.iconCacheOrder = []
  }

  function iconFor(entry) {
    if (!entry) return ""
    var cacheKey = String(entry.appId || entry.cls || "")
    if (cacheKey && root.iconCache[cacheKey] !== undefined)
      return root.iconCache[cacheKey]

    var found = resolveIcon(entry)
    if (cacheKey) {
      if (root.iconCacheOrder.length >= 128)
        delete root.iconCache[root.iconCacheOrder.shift()]
      root.iconCache[cacheKey] = found
      root.iconCacheOrder.push(cacheKey)
    }
    return found
  }

  function resolveIcon(entry) {
    var candidates = [entry.appId, entry.cls]
    for (var i = 0; i < candidates.length; i++) {
      var name = Model.safeIconName(candidates[i])
      if (!name) continue
      try {
        var desktop = DesktopEntries.byId(name)
        if (desktop && desktop.icon) {
          var iconName = Model.safeIconName(desktop.icon)
          var found = iconName ? Model.safeIconSource(Quickshell.iconPath(iconName, true)) : ""
          if (found) return found
        }
      } catch (e) {
      }
      var direct = Model.safeIconSource(Quickshell.iconPath(name, true))
      if (direct) return direct
    }
    return Model.safeIconSource(Quickshell.iconPath("application-x-executable", true))
  }

  function appLabel(entry) {
    if (!entry) return ""
    return entry.appId || entry.cls || "Application"
  }

  function openSettings() {
    root.mode = "settings"
    root.selected = 0
    root.sawKeyEvent = false
    root.entries = []
    root.expanded = false
    root.subIndex = 0
    root.open = true
    hyprBinds.refreshConflicts()
  }

  function applyShortcut(preset) {
    root.applyShortcuts(root.settings.allShortcut, preset.key)
  }

  function applyAllShortcut(preset) {
    root.applyShortcuts(preset.key, root.settings.dropdownShortcut)
  }

  // parseSettings normalizes the shortcut values, resolves a collision between
  // the all-windows and Dropdown shortcuts, and validates screen names.
  function normalizedSettings(allShortcut, dropdownShortcut, followActive, screens) {
    return Model.parseSettings(JSON.stringify({
      allShortcut: allShortcut,
      dropdownShortcut: dropdownShortcut,
      followActive: followActive,
      screens: screens
    }))
  }

  function applyShortcuts(allShortcut, dropdownShortcut) {
    root.settings = root.normalizedSettings(allShortcut, dropdownShortcut,
      root.settings.followActive, root.settings.screens)
    settingsFile.setText(Model.serializeSettings(root.settings))
    if (hyprBinds.legacy) {
      // Static installs keep the generated file in sync, then reload Hyprland.
      bindsFile.setText(Model.luaForSettings(root.settings))
      reloadTimer.restart()
    }
    // Runtime binds re-register when the settings object changes.
    root.cancel()
  }

  function saveDisplaySettings(followActive, screens) {
    root.settings = root.normalizedSettings(root.settings.allShortcut,
      root.settings.dropdownShortcut, followActive, screens)
    settingsFile.setText(Model.serializeSettings(root.settings))
  }

  function activateSettingsItem(index) {
    var item = root.settingsItems[index]
    if (!item) return
    if (item.kind === "allPreset") {
      root.applyAllShortcut(item.preset)
      return
    }
    if (item.kind === "preset") {
      root.applyShortcut(item.preset)
      return
    }
    if (item.kind === "active") {
      var next = !root.settings.followActive
      var screens = root.settings.screens.slice()
      if (!next && screens.length === 0 && root.activeScreenName)
        screens = [root.activeScreenName]
      root.saveDisplaySettings(next, screens)
      return
    }
    if (item.kind === "screen") {
      var list = root.settings.screens.slice()
      var at = list.indexOf(item.name)
      if (at === -1) list.push(item.name)
      else list.splice(at, 1)
      if (list.length === 0) list = [root.activeScreenName || item.name]
      root.saveDisplaySettings(false, list)
    }
  }

  IpcHandler {
    target: "apach.switcher"

    function next(): void { root.openMode("all", false) }
    function prev(): void { root.openMode("all", true) }
    function nextDropdown(): void { root.openMode("dropdown", false) }
    function prevDropdown(): void { root.openMode("dropdown", true) }
    function settings(): void { root.openSettings() }
    function close(): void { root.cancel() }

    // Deliberately excludes window titles and app ids: IPC is same-user, but
    // no title or notification content needs to cross that boundary.
    function status(): string {
      return JSON.stringify({
        open: root.open,
        mode: root.mode,
        count: root.groups.length,
        windows: root.entries.length,
        selected: root.selected,
        expanded: root.expanded,
        sub: root.subIndex,
        preset: root.settings.dropdownShortcut,
        allShortcut: root.settings.allShortcut,
        binds: hyprBinds.status
      })
    }

    // Local support payload: binding health, mode and counts only. No window
    // title, app id, screen serial or settings file content.
    function diagnose(): string {
      var report = hyprBinds.diagnostics()
      report.dropdown = root.dropdownEnabled
      report.preset = root.settings.dropdownShortcut
      report.allShortcut = root.settings.allShortcut
      return JSON.stringify(report)
    }
  }

  Variants {
    model: root.open && root.mode !== "settings" ? root.displayScreens : []
    delegate: Component {
      OverlayWindow {
        required property string modelData
        service: root
        screenName: modelData
        focused: modelData === root.activeScreenName
      }
    }
  }

  Variants {
    model: root.needsInputSurface ? [root.activeScreenName] : []
    delegate: Component {
      InputSurface {
        required property string modelData
        service: root
        screenName: modelData
      }
    }
  }

  LazyLoader {
    active: root.open && root.mode === "settings"

    SettingsPanel {
      service: root
      windowScreen: root.targetScreen
    }
  }
}
