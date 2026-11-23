import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// A transparent layer window over the whole screen that carries Mochi and her
// speech bubble. It stays mapped and never moves or resizes: she moves inside
// it, so every move is smooth and Hyprland's layer animations never replay;
// when there is nothing to sit on she just fades out.
//
// Only her body takes the pointer. When it touches her she scoots along the
// edge, out of the way, so whatever was under her can be clicked; she drifts
// back to her corner a few seconds after the pointer has gone.
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

  function walkable() { return win.here && !win.falling && !win.perch.fallPending }

  function snapHome() {
    walkAnim.stop(); walkT = 0; buddy.walking = false; buddy.running = false; buddy.jumping = false
    homeTimer.stop()
    dodgeMs = 0
    dodge = 0
  }

  // Where she is right now, in screen coordinates. Her window covers the
  // whole screen and never moves or resizes: she moves inside it, so every
  // move is plain drawing and stays smooth (moving a layer window shows up a
  // frame late, which made her jump).
  function clampLeft(v) { return Math.max(0, Math.min(v, screenW - buddy.width)) }
  readonly property real curLeft: clampLeft(wantLeft + dodge + walkT * walkDX)
  readonly property real arcLift: buddy.jumping ? jumpHeight * Math.sin(Math.PI * walkT) : 0
  readonly property real curTop: Math.max(0, wantTop + walkT * walkDY) - arcLift
  readonly property int liveLeft: Math.round(curLeft)
  readonly property int liveTop: Math.round(curTop)
  property var prevSeat: null

  // Travelling to the next window instead of popping up there: on a level
  // edge she walks (runs if it's far; on her swing under the bar the swing
  // slides along), anywhere else on the screen she jumps there in an arc.
  // The offset from her new place shrinks from (walkDX, walkDY) to nothing.
  property real walkDX: 0
  property real walkDY: 0
  property real walkT: 0
  property real jumpHeight: 0
  // Speeds in px per second, scaled with her size so her feet don't skate.
  readonly property real walkSpeed: 120 * buddy.s
  readonly property real runSpeed: 300 * buddy.s
  readonly property real slideSpeed: 340  // the swing under the bar
  readonly property real runFrom: 600     // px
  NumberAnimation {
    id: walkAnim
    target: win
    property: "walkT"
    from: 1
    to: 0
    onFinished: { buddy.walking = false; buddy.running = false; buddy.jumping = false; buddy.wave() }
  }

  function maybeWalk(from) {
    if (!from || falling || !win.here || !buddy.motion || win.perch.sleeping) return false
    homeTimer.stop(); dodgeMs = 0; dodge = 0
    var newLeft = clampLeft(wantLeft)
    // Keep her seat where it was: the swing adds a little padding on top.
    var padFrom = from.hanging ? 7 : 0, padTo = hanging ? 7 : 0
    var dx = from.left - newLeft
    var dy = from.top - Math.max(0, wantTop) + (padFrom - padTo) * buddy.s
    if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return false
    var level = from.hanging === hanging && Math.abs(dy) <= 80
    var dist = Math.sqrt(dx * dx + dy * dy)
    walkAnim.stop()
    walkDX = dx
    walkDY = dy
    walkT = 1
    if (level) {
      var run = !hanging && Math.abs(dx) >= runFrom
      var speed = hanging ? slideSpeed : run ? runSpeed : walkSpeed
      walkAnim.duration = Math.max(400, Math.min(5000, Math.abs(dx) / speed * 1000))
      buddy.running = run
      buddy.jumping = false
    } else {
      jumpHeight = Math.min(160, 30 * buddy.s + 0.18 * dist)
      walkAnim.duration = Math.max(450, Math.min(1100, 350 + 0.45 * dist))
      buddy.running = false
      buddy.jumping = true
    }
    buddy.walkDir = dx < 0 ? 1 : -1
    buddy.walking = true
    walkAnim.start()
    return true
  }

  property bool falling: false
  property int fallLeft: 0
  property int fallTop: 0

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  // Only her body takes the pointer: the mask is her hit box, wherever she is.
  mask: Region {
    x: Math.round(buddy.x + buddy.hitBox.x)
    y: Math.round(buddy.y + buddy.hitBox.y)
    width: Math.round(buddy.hitBox.width)
    height: Math.round(buddy.hitBox.height)
  }
  WlrLayershell.namespace: "jebin2-perch"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Connections {
    target: win.perch

    function onLeaving() {
      win.prevSeat = win.here && !win.falling ? { left: win.liveLeft, top: win.liveTop, hanging: win.hanging, at: Date.now() } : null
      // The new window's place is known right after this signal.
      var from = win.walkable() ? win.prevSeat : null
      if (from) Qt.callLater(function() { win.maybeWalk(from) })
    }

    function onFell(current) {
      var seat = current
        ? (win.perch.hasWindow && win.onThisScreen ? { left: win.liveLeft, top: win.liveTop } : null)
        : (win.prevSeat && Date.now() - win.prevSeat.at < 1500 ? win.prevSeat : null)
      if (!seat) return
      walkAnim.stop(); win.walkT = 0; buddy.walking = false; buddy.running = false; buddy.jumping = false
      bubble.dismiss()
      win.fallLeft = seat.left
      win.fallTop = seat.top
      win.falling = true
      buddy.fall()
      fallEnd.restart()
    }

    function onArrived() {
      if (buddy.walking) return
      win.snapHome()
      if (win.perch.hasWindow && win.onThisScreen) buddy.arrive()
      else bubble.dismiss()
    }

    function onSay(line, topic, mood) {
      if (!(win.perch.hasWindow && win.onThisScreen && !win.falling)) return
      bubble.show(line)
      buddy.heard(topic, mood, line)
    }

    function onShowSign(text) {
      if (win.perch.hasWindow && win.onThisScreen) buddy.showSign(text)
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
    x: buddy.x - width + 2
    y: buddy.y + Math.round((buddy.pad + 6) * buddy.s)
  }

  Buddy {
    id: buddy
    x: win.falling ? win.fallLeft : win.curLeft
    y: win.falling ? win.fallTop : win.curTop
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
    onWantsToSay: function(line, topic) { win.perch.speakLine(line, true, topic, "") }
  }
}
