import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

PanelWindow {
  id: settingsWindow

  required property var service
  property var windowScreen


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

  screen: windowScreen
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
    onClicked: service.cancel()
  }

  Rectangle {
    id: settingsPanel
    anchors.centerIn: parent
    width: Style.space(500)
    height: Math.min(settingsWindow.screen ? settingsWindow.screen.height - Style.space(80) : Style.space(700),
      Math.max(Style.space(240), settingsColumn.implicitHeight + Style.space(40)))
    radius: Math.max(16, Style.cornerRadius)
    opacity: 0
    color: Qt.rgba(service.popupBackground.r, service.popupBackground.g,
      service.popupBackground.b, 0.98)
    border.width: 1
    border.color: Util.alpha(service.accent, 0.5)
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        service.cancel()
        event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        service.selected = Math.max(0, service.selected - 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        service.selected = Math.min(service.settingsItems.length - 1, service.selected + 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        service.activateSettingsItem(service.selected)
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
        color: service.accent
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
        color: Util.alpha(service.popupText, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }

      Repeater {
        model: service.allItems

        delegate: ShortcutRow {
          required property var modelData
          label: modelData.label
          current: service.settings.allShortcut === modelData.preset.key
          highlighted: service.selected === modelData.itemIndex
          onPicked: {
            service.selected = modelData.itemIndex
            service.applyAllShortcut(modelData.preset)
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "DROPDOWN SHORTCUT"
        color: Util.alpha(service.popupText, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }

      Text {
        textFormat: Text.PlainText
        visible: !service.dropdownEnabled
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Dropdown is disabled: Ctrl+Tab is not bound."
        color: Util.alpha(service.popupText, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: service.dropdownItems

        delegate: ShortcutRow {
          required property var modelData
          label: modelData.label
          current: service.settings.dropdownShortcut === modelData.preset.key
          highlighted: service.selected === modelData.itemIndex
          onPicked: {
            service.selected = modelData.itemIndex
            service.applyShortcut(modelData.preset)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(service.popupText, 0.12)
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "DISPLAY"
        color: Util.alpha(service.popupText, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "The focused screen is always included."
        color: Util.alpha(service.popupText, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: service.displayItems

        Rectangle {
          required property var modelData
          readonly property int itemIndex: modelData.itemIndex
          width: parent.width
          height: Style.space(38)
          radius: Math.max(8, Style.cornerRadius - 8)
          color: service.selected === itemIndex
            ? Util.alpha(service.accent, 0.16)
            : Util.alpha(service.popupText, 0.04)
          border.width: service.selected === itemIndex ? 1 : 0
          border.color: service.accent
          opacity: 1.0

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: service.selected === itemIndex ? service.accent : Util.alpha(service.popupText, 0.75)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: service.selected === itemIndex
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.kind === "active"
              ? (service.settings.followActive ? "YES" : "NO")
              : (modelData.selected ? "✓" : "")
            color: service.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: {
              service.selected = itemIndex
              service.activateSettingsItem(itemIndex)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "BINDINGS: " + (service.bindsMode === "static" ? "STATIC FILE" : "RUNTIME")
          + (service.bindsStatus === "error" ? " — ERROR" : "")
        color: Util.alpha(service.popupText, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }

      Text {
        textFormat: Text.PlainText
        visible: service.bindsStatus === "error"
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: service.bindsError
        color: Util.alpha(service.popupText, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: service.bindsConflicts

        Text {
          required property var modelData
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: modelData.chord + " is also bound to \"" + modelData.description
            + "\" — the switcher replaces it while enabled"
          color: Util.alpha(service.popupText, 0.55)
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
        color: Util.alpha(service.popupText, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
