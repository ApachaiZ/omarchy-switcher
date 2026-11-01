import QtQuick
import Quickshell
import Quickshell.Wayland

// Keyboard-only surface for the focused monitor. When the overlay is rendered
// only on other selected screens, Hyprland does not give those layer surfaces
// keyboard focus, so arrows and Tab would reach the window underneath. This
// transparent surface sits on the focused monitor, takes exclusive keyboard
// focus, and forwards the same key events to the service.
PanelWindow {
  id: surface

  required property var service
  required property string screenName

  screen: service.screenForName(screenName)
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
    onClicked: surface.service.cancel()
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) { surface.service.handlePressed(event) }
    Keys.onReleased: function(event) { surface.service.handleReleased(event) }

    Component.onCompleted: forceActiveFocus()
  }
}
