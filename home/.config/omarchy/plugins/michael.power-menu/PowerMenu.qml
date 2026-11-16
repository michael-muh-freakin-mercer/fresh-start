pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var targetScreen: null
  // Visual state: eases toward 1 when opened, 0 when closed. The window stays
  // visible until it reaches 0 so the fade-out can finish.
  property real progress: root.opened ? 1 : 0

  Behavior on progress {
    NumberAnimation {
      duration: Style.duration(root.opened ? 140 : 100)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }

  function open() {
    const monitor = Hyprland.focusedMonitor
    root.targetScreen = Quickshell.screens.find(screen => monitor && screen.name === monitor.name) || Quickshell.screens[0]
    root.opened = true
    Qt.callLater(() => keyboard.forceActiveFocus())
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell)
      root.shell.hide(root.manifest ? root.manifest.id : "michael.power-menu")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open()
  }

  function activate(action) {
    if (!root.opened) return
    const commands = {
      suspend: ["systemctl", "suspend"],
      shutdown: ["omarchy", "system", "shutdown"],
      restart: ["omarchy", "system", "reboot"]
    }
    const command = commands[action]
    if (!command) return
    Quickshell.execDetached(command)
    root.dismiss()
  }

  component PowerAction: AbstractButton {
    id: control
    property bool primary: false
    property string powerAction: ""

    width: primary ? 176 : 144
    height: primary ? width : 64
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    onClicked: root.activate(powerAction)
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()

    background: Rectangle {
      radius: height / 2
      // Idle is the background colour at alpha 0, not "transparent" (black at
      // alpha 0), so the hover fade changes only alpha and has no dark tint.
      // Every button is a solid card so it stays readable over any wallpaper;
      // hover and focus lift it to full opacity with an accent border.
      color: control.hovered || control.activeFocus
        ? Commons.Color.menu.background
        : Util.alpha(Commons.Color.menu.background, 0.85)
      border.width: control.primary || control.activeFocus ? 2 : 1
      border.color: control.hovered || control.activeFocus
        ? Commons.Color.accent
        : Util.alpha(Commons.Color.foreground, control.primary ? 0.8 : 0.35)
      opacity: control.down ? 0.75 : 1

      Behavior on color {
        ColorAnimation { duration: Style.duration(100); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }
      Behavior on border.color {
        ColorAnimation { duration: Style.duration(100); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(60); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }
    }

    contentItem: Item {
      Text {
        anchors.centerIn: parent
        visible: !control.primary
        text: control.text
        color: control.hovered || control.activeFocus ? Commons.Color.accent : Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: 22
        font.weight: Font.Medium

        Behavior on color {
          ColorAnimation { duration: Style.duration(100); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }
      }

      Canvas {
        id: powerIcon
        anchors.centerIn: parent
        visible: control.primary
        width: 72
        height: 72
        property color strokeColor: control.hovered || control.activeFocus ? Commons.Color.accent : Commons.Color.foreground
        Behavior on strokeColor {
          ColorAnimation { duration: Style.duration(100); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }
        onStrokeColorChanged: requestPaint()
        onPaint: {
          const context = getContext("2d")
          context.reset()
          context.strokeStyle = strokeColor
          context.lineWidth = 5
          context.lineCap = "round"
          context.beginPath()
          context.arc(36, 39, 25, -Math.PI / 3, Math.PI * 4 / 3)
          context.stroke()
          context.beginPath()
          context.moveTo(36, 7)
          context.lineTo(36, 34)
          context.stroke()
        }
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened || root.progress > 0
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "michael-power-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    // Released as soon as the menu closes, so keys go to the window underneath
    // during the fade-out.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      // Off during the fade-out so clicks reach the window underneath.
      enabled: root.opened
      onClicked: root.dismiss()
    }

    // Dims the desktop so the buttons do not get lost in the wallpaper. It
    // fades with `progress` but is not scaled, and passes clicks through to
    // the MouseArea above.
    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.progress
    }

    Item {
      id: keyboard
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()
      Keys.onPressed: event => {
        if (event.key === Qt.Key_P && (event.modifiers & Qt.MetaModifier) && (event.modifiers & Qt.ShiftModifier)) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          if (restartButton.activeFocus) shutdownButton.forceActiveFocus()
          else suspendButton.forceActiveFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          if (suspendButton.activeFocus) shutdownButton.forceActiveFocus()
          else restartButton.forceActiveFocus()
          event.accepted = true
        }
      }

      // Entrance fade and scale live here, separate from the Row's own
      // fit-to-screen scale, so the two do not overwrite each other.
      Item {
        id: stage
        anchors.fill: parent
        opacity: root.progress
        scale: 0.96 + 0.04 * root.progress

        Row {
          anchors.centerIn: parent
          spacing: 48
          scale: Math.min(1, (panel.width - 32) / width)

          PowerAction {
            id: suspendButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Suspend"
            powerAction: "suspend"
            KeyNavigation.tab: shutdownButton
            KeyNavigation.backtab: restartButton
          }

          PowerAction {
            id: shutdownButton
            primary: true
            text: "Shut down"
            powerAction: "shutdown"
            KeyNavigation.tab: restartButton
            KeyNavigation.backtab: suspendButton
          }

          PowerAction {
            id: restartButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Restart"
            powerAction: "restart"
            KeyNavigation.tab: suspendButton
            KeyNavigation.backtab: shutdownButton
          }
        }
      }
    }
  }
}
