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
  property int selected: -1
  property var dropdownWindows: ({})
  property var settings: Model.defaultSettings()
  property string pendingMode: "all"
  property bool pendingReverse: false
  property bool sawKeyEvent: false
  property var pendingEntry: null
  property bool dropdownEnabled: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string settingsPath: home + "/.config/omarchy/switcher.json"
  readonly property string bindsPath: home + "/.config/hypr/switcher.lua"
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

  readonly property var displayScreens: {
    if (settings.followActive)
      return activeScreenName ? [activeScreenName] : []
    var valid = []
    for (var i = 0; i < screenNames.length; i++)
      if (settings.screens.indexOf(screenNames[i]) !== -1) valid.push(screenNames[i])
    if (valid.length === 0 && activeScreenName) valid = [activeScreenName]
    return valid
  }

  readonly property string focusScreenName: {
    if (activeScreenName && displayScreens.indexOf(activeScreenName) !== -1) return activeScreenName
    return displayScreens.length > 0 ? displayScreens[0] : activeScreenName
  }

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
    path: root.bindsPath
    printErrors: false
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
    root.entries = list
    root.mode = root.pendingMode
    root.pendingMode = root.mode
    root.selected = Model.initialIndex(list.length, root.pendingReverse)
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
    if (!root.entries.length || root.selected < 0) return
    root.selected = (root.selected + delta + root.entries.length) % root.entries.length
  }

  function cancel() {
    if (!root.open) return
    root.open = false
    root.pendingEntry = null
    root.entries = []
    root.selected = -1
  }

  function commit() {
    var entry = root.entries[root.selected] || null
    root.open = false
    root.pendingEntry = entry
    root.entries = []
    root.selected = -1
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
      root.cancel()
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

  function iconFor(entry) {
    if (!entry) return ""
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
    root.open = true
    hyprBinds.refreshConflicts()
  }

  function applyShortcut(preset) {
    root.applyShortcuts(root.settings.allShortcut, preset.key)
  }

  function applyAllShortcut(preset) {
    root.applyShortcuts(preset.key, root.settings.dropdownShortcut)
  }

  function applyShortcuts(allShortcut, dropdownShortcut) {
    // parseSettings normalizes both values and resolves a collision between
    // the all-windows and Dropdown shortcuts.
    root.settings = Model.parseSettings(JSON.stringify({
      allShortcut: allShortcut,
      dropdownShortcut: dropdownShortcut,
      followActive: root.settings.followActive,
      screens: root.settings.screens
    }))
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
    root.settings = Model.parseSettings(JSON.stringify({
      allShortcut: root.settings.allShortcut,
      dropdownShortcut: root.settings.dropdownShortcut,
      followActive: followActive,
      screens: screens
    }))
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
        count: root.entries.length,
        selected: root.selected,
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
        focused: modelData === root.focusScreenName
      }
    }
  }

  LazyLoader {
    id: settingsLoader
    active: root.open && root.mode === "settings"

    PanelWindow {
      id: settingsWindow

      // One row for every shortcut preset; keeps the two shortcut sections
      // visually identical without duplicating the layout.
      component ShortcutRow: Rectangle {
        id: row

        required property string label
        required property bool current
        required property bool highlighted
        signal picked()

        width: parent ? parent.width : 0
        height: Style.space(38)
        radius: Math.max(8, Style.cornerRadius - 8)
        color: highlighted
          ? Util.alpha(Commons.Color.accent, 0.16)
          : Util.alpha(Commons.Color.popups.text, 0.04)
        border.width: highlighted ? 1 : 0
        border.color: Commons.Color.accent

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          text: row.label
          color: row.highlighted
            ? Commons.Color.accent
            : Util.alpha(Commons.Color.popups.text, 0.75)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: row.highlighted
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          visible: row.current
          text: "CURRENT"
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onClicked: row.picked()
        }
      }

      screen: root.targetScreen
      visible: true
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      WlrLayershell.namespace: "apach-switcher"
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.cancel()
      }

      Rectangle {
        id: settingsPanel
        anchors.centerIn: parent
        width: Style.space(500)
        height: Math.min(settingsWindow.screen ? settingsWindow.screen.height - Style.space(80) : Style.space(700),
          Math.max(Style.space(240), settingsColumn.implicitHeight + Style.space(40)))
        radius: Math.max(16, Style.cornerRadius)
        opacity: 0
        color: Qt.rgba(root.popupBackground.r, root.popupBackground.g,
          root.popupBackground.b, 0.98)
        border.width: 1
        border.color: Util.alpha(root.accent, 0.5)
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancel()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selected = Math.max(0, root.selected - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selected = Math.min(root.settingsItems.length - 1, root.selected + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSettingsItem(root.selected)
            event.accepted = true
          }
        }

        Component.onCompleted: {
          settingsIntro.start()
          forceActiveFocus()
        }

        NumberAnimation {
          id: settingsIntro
          target: settingsPanel
          property: "opacity"
          from: 0
          to: 1
          duration: 120
          easing.type: Easing.OutCubic
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Column {
          id: settingsColumn
          width: parent.width - Style.space(40)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Style.space(20)
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "SWITCHER — SETTINGS"
            color: root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "ALL WINDOWS SHORTCUT"
            color: Util.alpha(root.popupText, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }

          Repeater {
            model: root.allItems

            delegate: ShortcutRow {
              required property var modelData
              label: modelData.label
              current: root.settings.allShortcut === modelData.preset.key
              highlighted: root.selected === modelData.itemIndex
              onPicked: {
                root.selected = modelData.itemIndex
                root.applyAllShortcut(modelData.preset)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "DROPDOWN SHORTCUT"
            color: Util.alpha(root.popupText, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.dropdownEnabled
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Dropdown is disabled: Ctrl+Tab is not bound."
            color: Util.alpha(root.popupText, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.dropdownItems

            delegate: ShortcutRow {
              required property var modelData
              label: modelData.label
              current: root.settings.dropdownShortcut === modelData.preset.key
              highlighted: root.selected === modelData.itemIndex
              onPicked: {
                root.selected = modelData.itemIndex
                root.applyShortcut(modelData.preset)
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.popupText, 0.12)
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "DISPLAY"
            color: Util.alpha(root.popupText, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }

          Repeater {
            model: root.displayItems

            Rectangle {
              required property var modelData
              readonly property int itemIndex: modelData.itemIndex
              width: parent.width
              height: Style.space(38)
              radius: Math.max(8, Style.cornerRadius - 8)
              color: root.selected === itemIndex
                ? Util.alpha(root.accent, 0.16)
                : Util.alpha(root.popupText, 0.04)
              border.width: root.selected === itemIndex ? 1 : 0
              border.color: root.accent
              opacity: 1.0

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.selected === itemIndex ? root.accent : Util.alpha(root.popupText, 0.75)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: root.selected === itemIndex
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.kind === "active"
                  ? (root.settings.followActive ? "YES" : "NO")
                  : (modelData.selected ? "✓" : "")
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: {
                  root.selected = itemIndex
                  root.activateSettingsItem(itemIndex)
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "BINDINGS: " + (hyprBinds.mode === "static" ? "STATIC FILE" : "RUNTIME")
              + (hyprBinds.status === "error" ? " — ERROR" : "")
            color: Util.alpha(root.popupText, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }

          Text {
            textFormat: Text.PlainText
            visible: hyprBinds.status === "error"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: hyprBinds.lastError
            color: Util.alpha(root.popupText, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: hyprBinds.conflicts

            Text {
              required property var modelData
              textFormat: Text.PlainText
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: modelData.chord + " is also bound to \"" + modelData.description
                + "\" — the switcher replaces it while enabled"
              color: Util.alpha(root.popupText, 0.55)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Esc closes · Enter applies / toggles"
            color: Util.alpha(root.popupText, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
