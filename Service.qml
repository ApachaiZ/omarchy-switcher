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
  property bool modsHeld: false
  property var heldKeys: ({})
  property var pendingEntry: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string settingsPath: home + "/.config/omarchy/switcher.json"
  readonly property string bindsPath: home + "/.config/hypr/switcher.lua"
  readonly property string dropdownStatePath: home + "/.local/state/omarchy/dropdown-state.json"
  readonly property color themeAccent: Commons.Color.accent
  readonly property color popupText: Commons.Color.popups.text
  readonly property color popupBackground: Commons.Color.popups.background
  readonly property color popupBorder: Commons.Color.popups.border
  // Keep the Dropdown mode clearly distinct without leaving the active theme:
  // rotate the theme accent's hue toward violet and reuse its saturation.
  readonly property color accent: mode === "dropdown"
    ? Qt.hsla((themeAccent.hslHue + 0.25) % 1.0,
        Math.max(0.5, themeAccent.hslSaturation),
        Math.min(0.72, themeAccent.hslLightness + 0.06), 1.0)
    : themeAccent
  readonly property string modeLabel: mode === "dropdown" ? "FENÊTRES DROPDOWN" : "AUTRES FENÊTRES"
  readonly property var presets: Model.shortcutPresets()
  readonly property var dropdownPreset: Model.presetForKey(settings.dropdownShortcut)
  readonly property bool dropdownUsesSuper: dropdownPreset.key.indexOf("SUPER") === 0
  readonly property int dropdownModifier: dropdownUsesSuper ? Qt.MetaModifier : Qt.ControlModifier
  readonly property string settingsHint: mode === "dropdown"
    ? (dropdownUsesSuper ? "Super+S" : "Ctrl+S") : "Alt+S"
  readonly property string modeHint: mode === "dropdown"
    ? dropdownPreset.label + " · Tab/Shift+Tab · Entrée · Échap · " + settingsHint + " réglages"
    : "Alt+Tab · " + dropdownPreset.label + " pour Dropdown · Tab/Shift+Tab · Entrée · Échap · " + settingsHint + " réglages"

  readonly property var targetScreen: {
    var monitor = Hyprland.focusedMonitor
    if (monitor) {
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === monitor.name) return Quickshell.screens[i]
    }
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  Component.onCompleted: {
    settingsFile.reload()
    dropdownFile.reload()
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.settings = Model.parseSettings(text())
    onLoadFailed: root.settings = Model.defaultSettings()
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
    root.modsHeld = false
    root.heldKeys = ({})
    root.open = true
    modTimer.restart()
  }

  function openMode(nextMode, reverse) {
    if (nextMode === "settings") {
      openSettings()
      return
    }
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
    root.modsHeld = (event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== 0
    if (event.key === Qt.Key_Escape) {
      root.cancel()
      event.accepted = true
      return
    }
    var reverse = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) !== 0
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      if ((event.modifiers & root.dropdownModifier) && root.mode !== "dropdown") {
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
  }

  function applyShortcut(preset) {
    root.settings = { version: 1, dropdownShortcut: preset.key }
    settingsFile.setText(Model.serializeSettings(root.settings))
    bindsFile.setText(Model.luaForSettings(root.settings))
    root.cancel()
    reloadTimer.restart()
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
        preset: root.settings.dropdownShortcut
      })
    }
  }

  LazyLoader {
    id: switcherLoader
    active: root.open && root.mode !== "settings"

    PanelWindow {
      id: panelWindow
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
        id: panel
        anchors.centerIn: parent
        width: Math.min(panelWindow.screen ? panelWindow.screen.width - 96 : 900,
          Math.max(560, cardRow.implicitWidth + Style.space(56)))
        height: Math.max(Style.space(300), contentColumn.implicitHeight + Style.space(40))
        radius: Math.max(16, Style.cornerRadius)
        color: Qt.rgba(root.popupBackground.r, root.popupBackground.g,
          root.popupBackground.b, 0.98)
        border.width: 1
        border.color: Util.alpha(root.accent, 0.55)
        opacity: 0
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handlePressed(event) }
        Keys.onReleased: function(event) { root.handleReleased(event) }

        Component.onCompleted: {
          intro.start()
          forceActiveFocus()
        }

        NumberAnimation {
          id: intro
          target: panel
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

        Rectangle {
          anchors.fill: parent
          radius: parent.radius
          color: "transparent"
          border.width: 1
          border.color: Util.alpha(root.accent, 0.12)
        }

        Column {
          id: contentColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(20)
          spacing: Style.space(12)

          Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, modePill.height, settingsButton.height)

            Text {
              id: titleText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "SWITCHER"
              color: root.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              font.letterSpacing: 1.2
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8

              Rectangle {
                id: settingsButton
                width: 24
                height: 24
                radius: 12
                color: Util.alpha(root.accent, 0.12)
                border.width: 1
                border.color: Util.alpha(root.accent, 0.35)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: "⚙"
                  color: root.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openSettings()
                }
              }

              Rectangle {
                id: modePill
                width: modeText.implicitWidth + 18
                height: 24
                radius: 12
                color: Util.alpha(root.accent, 0.12)
                border.width: 1
                border.color: Util.alpha(root.accent, 0.35)

                Text {
                  id: modeText
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.modeLabel
                  color: root.accent
                  font.family: Style.font.family
                  font.pixelSize: 10
                  font.bold: true
                  font.letterSpacing: 0.8
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            text: root.modeHint
            color: Util.alpha(root.popupText, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Flickable {
            id: strip
            width: Math.min(cardRow.implicitWidth, panel.width - 72)
            height: 244
            contentWidth: cardRow.implicitWidth
            contentHeight: height
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            anchors.horizontalCenter: parent.horizontalCenter

            function reveal(x, w) {
              if (contentWidth <= width) return
              var margin = 36
              if (x - margin < contentX)
                contentX = Math.max(0, x - margin)
              else if (x + w + margin > contentX + width)
                contentX = Math.min(contentWidth - width, x + w + margin - width)
            }

            Behavior on contentX {
              NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }

            Row {
              id: cardRow
              spacing: Style.space(12)

              Repeater {
                model: root.entries

                Item {
                  id: cardItem
                  required property var modelData
                  required property int index
                  readonly property var entry: modelData
                  readonly property bool isSelected: root.selected === index

                  width: 136
                  height: 166

                  onIsSelectedChanged: if (isSelected) strip.reveal(cardItem.x, cardItem.width)

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    height: 36
                    text: cardItem.entry.title
                    color: cardItem.isSelected ? root.accent : Util.alpha(root.popupText, 0.78)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: cardItem.isSelected
                    font.letterSpacing: 0.4
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignBottom
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    id: card
                    y: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 112
                    height: 112
                    radius: Math.max(12, Style.cornerRadius)
                    color: cardItem.isSelected
                      ? Util.alpha(root.accent, 0.16)
                      : Util.alpha(root.popupText, 0.04)
                    border.width: cardItem.isSelected ? 2 : 1
                    border.color: cardItem.isSelected
                      ? root.accent
                      : Util.alpha(root.popupText, 0.12)
                    scale: cardItem.isSelected ? 1.08 : 1.0
                    z: cardItem.isSelected ? 2 : 0

                    Behavior on scale {
                      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on border.color {
                      ColorAnimation { duration: 120 }
                    }
                    Behavior on color {
                      ColorAnimation { duration: 120 }
                    }

                    Image {
                      id: icon
                      anchors.centerIn: parent
                      anchors.verticalCenterOffset: -8
                      width: 60
                      height: 60
                      source: root.iconFor(cardItem.entry)
                      sourceSize.width: 96
                      sourceSize.height: 96
                      asynchronous: true
                      cache: true
                      fillMode: Image.PreserveAspectFit
                      visible: status === Image.Ready
                    }

                    Rectangle {
                      anchors.centerIn: icon
                      width: 52
                      height: 52
                      radius: 14
                      visible: !icon.visible
                      color: Util.alpha(root.accent, 0.18)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: String(root.appLabel(cardItem.entry)).charAt(0).toUpperCase()
                        color: root.accent
                        font.family: Style.font.family
                        font.pixelSize: 26
                        font.bold: true
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: 9
                      width: parent.width - 14
                      text: root.appLabel(cardItem.entry)
                      color: cardItem.isSelected ? root.accent : Util.alpha(root.popupText, 0.48)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      acceptedButtons: Qt.LeftButton
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selected = cardItem.index
                        root.commit()
                      }
                    }
                  }

                  Rectangle {
                    visible: cardItem.isSelected
                    width: 24
                    height: 2
                    radius: 1
                    color: root.accent
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 36
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.entries.length === 0
            width: parent.width
            height: 120
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.mode === "dropdown"
              ? "Aucune fenêtre Dropdown ouverte"
              : "Aucune fenêtre ouverte"
            color: Util.alpha(root.popupText, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  LazyLoader {
    id: settingsLoader
    active: root.open && root.mode === "settings"

    PanelWindow {
      id: settingsWindow
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
        width: Style.space(460)
        height: Style.space(320)
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
            root.selected = Math.min(root.presets.length - 1, root.selected + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applyShortcut(root.presets[root.selected])
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
          anchors.fill: parent
          anchors.margins: Style.space(20)
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "SWITCHER — RÉGLAGES"
            color: root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            text: "Toutes les fenêtres : Alt + Tab. Choisis le raccourci Dropdown :"
            color: Util.alpha(root.popupText, 0.6)
            font.family: Style.font.family
            font.pixelSize: 11
          }

          Repeater {
            model: root.presets

            Rectangle {
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(38)
              radius: Math.max(8, Style.cornerRadius - 8)
              color: root.selected === index
                ? Util.alpha(root.accent, 0.16)
                : Util.alpha(root.popupText, 0.04)
              border.width: root.selected === index ? 1 : 0
              border.color: root.accent

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.selected === index ? root.accent : Util.alpha(root.popupText, 0.75)
                font.family: Style.font.family
                font.pixelSize: 12
                font.bold: root.selected === index
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: root.settings.dropdownShortcut === modelData.key
                text: "ACTUEL"
                color: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: root.applyShortcut(modelData)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "Échap ferme · Entrée applique"
            color: Util.alpha(root.popupText, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
