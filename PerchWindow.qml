import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A small transparent layer window that carries Mochi and her speech bubble.
// It stays mapped and only moves, so Hyprland's layer open/close animations
// never replay; when there is nothing to sit on she just fades out.
//
// Only her body takes the pointer. When it touches her she scoots along the
// edge, out of the way, so whatever was under her can be clicked; she drifts
// back to her corner a few seconds after the pointer has gone.
//
// The window grows to the left while a bubble is showing, and downwards
// while she falls off a window that closed.
PanelWindow {
  id: win

  required property var perch

  readonly property bool onThisScreen: perch.monitorName === (screen ? screen.name : "")
  readonly property bool here: (perch.hasWindow && onThisScreen) || falling
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

  // `x` is where the pointer came in, in her coordinates: she moves away from
  // it, or the other way when the edge runs out.
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

  // Where she is sitting right now, and where she sat before the last focus
  // change: a window can close just after focus has already moved on.
  readonly property int liveLeft: Math.max(0, Math.min(Math.round(wantLeft + dodge), screenW - buddy.width))
  readonly property int liveTop: Math.max(0, wantTop)
  property var prevSeat: null

  property bool falling: false
  property int fallLeft: 0
  property int fallTop: 0

  readonly property real bubbleSpace: bubble.active ? bubble.width + 2 : 0
  readonly property real fallSpace: falling ? 100 * buddy.s : 0

  anchors.top: true
  anchors.left: true
  margins.left: here ? Math.max(0, (falling ? fallLeft : liveLeft) - bubbleSpace) : 0
  margins.top: here ? (falling ? fallTop : liveTop) : 0

  implicitWidth: Math.ceil(bubbleSpace + buddy.width)
  implicitHeight: Math.ceil(Math.max(buddy.height, bubble.active ? bubble.y + bubble.height : 0) + fallSpace)

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region { item: buddy.hitBox }
  WlrLayershell.namespace: "jebin2-perch"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Connections {
    target: win.perch

    function onLeaving() {
      win.prevSeat = win.here && !win.falling ? { left: win.liveLeft, top: win.liveTop, at: Date.now() } : null
    }

    function onFell(current) {
      var seat = current
        ? (win.perch.hasWindow && win.onThisScreen ? { left: win.liveLeft, top: win.liveTop } : null)
        : (win.prevSeat && Date.now() - win.prevSeat.at < 1500 ? win.prevSeat : null)
      if (!seat) return
      bubble.dismiss()
      win.fallLeft = seat.left
      win.fallTop = seat.top
      win.falling = true
      buddy.fall()
      fallEnd.restart()
    }

    function onArrived() {
      win.snapHome()
      if (win.perch.hasWindow && win.onThisScreen) buddy.arrive()
      else bubble.dismiss()
    }

    function onSay(line, topic, mood) {
      if (!(win.perch.hasWindow && win.onThisScreen && !win.falling)) return
      bubble.show(line)
      buddy.heard(topic, mood, line)
    }

    function onAct(what) {
      if (!(win.perch.hasWindow && win.onThisScreen)) return
      if (what === "wave") buddy.wave()
      else if (what === "yawn") buddy.yawn()
      else if (what === "stretch") buddy.stretch()
      else if (what === "think") buddy.think()
      else buddy.did(what)
    }
  }

  Timer {
    id: fallEnd
    interval: 650
    onTriggered: win.falling = false
  }

  Bubble {
    id: bubble
    x: win.bubbleSpace - width + 2
    y: Math.round((buddy.pad + 6) * buddy.s)
  }

  Buddy {
    id: buddy
    x: win.bubbleSpace
    s: win.perch.size
    shown: win.here
    sleeping: win.perch.sleeping
    thrifty: win.perch.onBattery
    talking: bubble.active
    app: win.perch.hasWindow && win.onThisScreen && win.perch.info && typeof win.perch.info.class === "string"
      ? win.perch.info.class : ""
    characterUrl: win.perch.characterUrl
    hanging: win.perch.hasWindow && win.onThisScreen && win.hanging
    onPoked: function(x) { win.flee(x) }
  }
}
