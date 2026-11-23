import QtQuick
import Quickshell
import Quickshell.Wayland

// A small transparent layer window that carries Mochi. It stays mapped and
// only moves, so Hyprland's layer open/close animations never replay; when
// there is nothing to sit on she just fades out. Clicks pass straight through.
PanelWindow {
  id: win

  required property var perch

  readonly property bool here: perch.hasWindow && perch.monitorName === (screen ? screen.name : "")
  readonly property real screenX: screen ? screen.x : 0
  readonly property real screenY: screen ? screen.y : 0
  readonly property real screenW: screen ? screen.width : 0

  // Her right edge goes `inset` from the window's right edge. With room above
  // the window she sits on its top border; a window right under the bar
  // leaves no room, so there she swings from the border, inside the window.
  readonly property bool hanging: perch.winY - buddy.sitHeight < screenY + perch.reservedTop
  readonly property int wantLeft: Math.round(perch.winX + perch.winW - perch.inset - buddy.width - screenX)
  readonly property int wantTop: Math.round(hanging
    ? perch.winY + perch.borderSize - screenY
    : perch.winY - buddy.seatY - screenY)

  anchors.top: true
  anchors.left: true
  margins.left: here ? Math.max(0, Math.min(wantLeft, screenW - buddy.width)) : 0
  margins.top: here ? Math.max(0, wantTop) : 0

  implicitWidth: Math.ceil(buddy.width)
  implicitHeight: Math.ceil(buddy.height)

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: "jebin2-perch"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Connections {
    target: win.perch
    function onArrived() { if (win.here) buddy.arrive() }
  }

  Buddy {
    id: buddy
    s: win.perch.size
    shown: win.here
    sleeping: win.perch.sleeping
    hanging: win.here && win.hanging
  }
}
