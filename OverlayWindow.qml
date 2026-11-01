import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: window

  required property var service
  required property string screenName
  required property bool focused

  screen: service.screenForName(screenName)
  visible: true
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
    id: panel
    anchors.centerIn: parent
    width: Math.min(window.screen ? window.screen.width - 96 : 900,
      Math.max(560, cardRow.implicitWidth + Style.space(56)))
    height: Math.max(Style.space(220), contentColumn.implicitHeight + Style.space(32))
    radius: Math.max(16, Style.cornerRadius)
    color: Qt.rgba(service.popupBackground.r, service.popupBackground.g,
      service.popupBackground.b, 0.98)
    border.width: 1
    border.color: Util.alpha(service.accent, 0.55)
    opacity: 0
    focus: focused
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) { service.handlePressed(event) }
    Keys.onReleased: function(event) { service.handleReleased(event) }

    Component.onCompleted: {
      intro.start()
      if (focused) forceActiveFocus()
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

    Column {
      id: contentColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(16)
      spacing: Style.space(10)

      Item {
        width: parent.width
        height: Math.max(modeTitle.implicitHeight, settingsButton.height)

        Text {
          id: modeTitle
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          text: service.modeLabel
          color: service.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 1.2
        }

        Rectangle {
          id: settingsButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 24
          height: 24
          radius: 12
          color: Util.alpha(service.accent, 0.12)
          border.width: 1
          border.color: Util.alpha(service.accent, 0.35)

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "⚙"
            color: service.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: service.openSettings()
          }
        }
      }

      Flickable {
        id: strip
        visible: service.groups.length > 0
        width: Math.min(cardRow.implicitWidth, panel.width - Style.space(56))
        height: visible ? 198 : 0
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
            model: service.groups

            Item {
              id: cardItem
              required property var modelData
              required property int index
              readonly property var group: modelData
              readonly property var entry: group.entries.length > 0 ? group.entries[0] : null
              readonly property bool isSelected: service.selected === index

              width: 136
              height: 198

              onIsSelectedChanged: if (isSelected) strip.reveal(cardItem.x, cardItem.width)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                height: 36
                text: cardItem.group.entries.length > 1
                  ? service.appLabel(cardItem.entry)
                  : cardItem.entry.title
                color: cardItem.isSelected ? service.accent : Util.alpha(service.popupText, 0.78)
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

              Text {
                textFormat: Text.PlainText
                width: parent.width
                y: 38
                height: 12
                text: service.locationFor(cardItem.entry)
                color: Util.alpha(service.popupText, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
              }

              Rectangle {
                y: 58
                anchors.horizontalCenter: parent.horizontalCenter
                width: 112
                height: 112
                radius: Math.max(12, Style.cornerRadius)
                color: cardItem.isSelected
                  ? Util.alpha(service.accent, 0.16)
                  : Util.alpha(service.popupText, 0.04)
                border.width: cardItem.isSelected ? 2 : 1
                border.color: cardItem.isSelected
                  ? service.accent
                  : Util.alpha(service.popupText, 0.12)
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
                  width: 60
                  height: 60
                  source: service.iconFor(cardItem.entry)
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
                  color: Util.alpha(service.accent, 0.18)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: String(service.appLabel(cardItem.entry)).charAt(0).toUpperCase()
                    color: service.accent
                    font.family: Style.font.family
                    font.pixelSize: 26
                    font.bold: true
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    service.expanded = false
                    service.subIndex = 0
                    service.selected = cardItem.index
                    service.commit(cardItem.entry)
                  }
                }
              }

              // Multi-window applications show a chevron below the card. The
              // Down key expands the same submenu; clicking the chevron does
              // the same without activating a window.
              Text {
                textFormat: Text.PlainText
                visible: cardItem.group.entries.length > 1
                anchors.horizontalCenter: parent.horizontalCenter
                // The selected card scales to 1.08, so its bottom edge reaches
                // ~174 px. Keep the chevron clear of it.
                y: 178
                text: "▾ " + cardItem.group.entries.length
                color: cardItem.isSelected
                  ? service.accent
                  : Util.alpha(service.popupText, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: cardItem.isSelected

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  acceptedButtons: Qt.LeftButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    service.selected = cardItem.index
                    service.subIndex = 0
                    service.expanded = cardItem.group.entries.length > 1
                  }
                }
              }
            }
          }
        }
      }

      // Window list for the selected application. Opened with Down or the
      // chevron; it scrolls when a group has more windows than fit.
      Rectangle {
        visible: service.expanded && service.selectedGroup !== null
          && service.selectedGroup.entries.length > 1
        width: Math.min(panel.width - Style.space(56), Style.space(360))
        height: visible
          ? Math.min(service.selectedGroup.entries.length * Style.space(28) + Style.space(12),
              Style.space(208))
          : 0
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Math.max(10, Style.cornerRadius - 6)
        color: Qt.rgba(service.popupBackground.r, service.popupBackground.g,
          service.popupBackground.b, 0.98)
        border.width: 1
        border.color: Util.alpha(service.accent, 0.4)

        ListView {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          model: service.selectedGroup ? service.selectedGroup.entries : []
          currentIndex: service.subIndex
          boundsBehavior: Flickable.StopAtBounds
          clip: true
          interactive: false
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: Style.space(28)
            radius: Math.max(6, Style.cornerRadius - 10)
            color: index === service.subIndex
              ? Util.alpha(service.accent, 0.18)
              : "transparent"

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: subLocation.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title
              color: index === service.subIndex
                ? service.accent
                : Util.alpha(service.popupText, 0.8)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: subLocation
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: service.locationFor(modelData)
              color: Util.alpha(service.popupText, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                service.subIndex = index
                service.commit(modelData)
              }
            }
          }
          onCurrentIndexChanged: if (count > 0) positionViewAtIndex(currentIndex, ListView.Contain)
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: service.groups.length === 0
        width: parent.width
        height: visible ? 88 : 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: service.mode === "dropdown"
          ? "No Dropdown window open"
          : "No window open"
        color: Util.alpha(service.popupText, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        textFormat: Text.PlainText
        text: service.modeHint
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Util.alpha(service.popupText, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
