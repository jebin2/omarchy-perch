import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A small transparent layer window that carries Mochi. It stays mapped and
// only moves, so Hyprland's layer open/close animations never replay; when
// there is nothing to sit on she just fades out. Only her body takes the
// pointer, and when it touches her she scoots along the edge, out of the way,
// so whatever was under her can be clicked. She drifts back to her corner a
// few seconds after the pointer has gone.
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

  // How far she has scooted left from her corner, px (0 or less).
  property real dodge: 0
  property int dodgeMs: 260
  Behavior on dodge { NumberAnimation { duration: Style.duration(win.dodgeMs); easing.type: Easing.OutCubic } }
  readonly property real minDodge: -Math.max(0, perch.winW - buddy.width - perch.inset - 8)

  // `x` is where the pointer came in, in her window: she moves away from it,
  // or the other way when the edge runs out.
  function flee(x) {
    var step = buddy.width + 24
    var dir = x < buddy.width / 2 ? 1 : -1
    var target = dodge + dir * step
    if (target > 0 || target < minDodge) target = dodge - dir * step
    target = Math.max(minDodge, Math.min(0, target))
    homeTimer.restart()
    if (Math.abs(target - dodge) < 4) return
    buddy.startle(target < dodge ? -1 : 1)
    dodgeMs = 260
    dodge = target
  }

  Timer {
    id: homeTimer
    interval: 6000
    onTriggered: {
      if (win.dodge === 0) return
      win.dodgeMs = 700
      win.dodge = 0
    }
  }

  function snapHome() {
    homeTimer.stop()
    dodgeMs = 0
    dodge = 0
  }

  anchors.top: true
  anchors.left: true
  margins.left: here ? Math.max(0, Math.min(Math.round(wantLeft + dodge), screenW - buddy.width)) : 0
  margins.top: here ? Math.max(0, wantTop) : 0

  implicitWidth: Math.ceil(buddy.width)
  implicitHeight: Math.ceil(buddy.height)

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region { item: buddy.hitBox }
  WlrLayershell.namespace: "jebin2-perch"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Connections {
    target: win.perch
    function onArrived() { win.snapHome(); if (win.here) buddy.arrive() }
  }

  Buddy {
    id: buddy
    s: win.perch.size
    shown: win.here
    sleeping: win.perch.sleeping
    hanging: win.here && win.hanging
    onPoked: function(x) { win.flee(x) }
  }
}
