import QtQuick
import Quickshell
import Quickshell.Io
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
  function hangsOn(y) { return y - buddy.sitHeight < screenY + perch.reservedTop }
  function seatTop(y, hang) { return Math.round(hang ? y + perch.borderSize - screenY : y - buddy.seatY - screenY) }
  readonly property bool hanging: pin ? pin.hanging : hangsOn(perch.winY)
  readonly property int wantLeft: pin ? pin.left : Math.round(perch.winX + perch.winW - perch.inset - buddy.width - screenX)
  readonly property int wantTop: pin ? pin.top : seatTop(perch.winY, hanging)

  // ---- Picked up and put down ---------------------------------------------
  // Drag her anywhere: she sits on the window you drop her on (at that
  // spot) for 3 minutes, whatever is focused, then goes back. Dropped where
  // there's no window, she just goes back.
  property var pin: null         // { left, top, hanging, ws }
  property real dragBaseLeft: 0
  property real dragBaseTop: 0
  property real settleDX: 0
  property real settleDY: 0
  NumberAnimation { id: settleX; target: win; property: "settleDX"; to: 0; duration: 380; easing.type: Easing.OutBack }
  NumberAnimation { id: settleY; target: win; property: "settleDY"; to: 0; duration: 380; easing.type: Easing.OutBounce }
  Timer {
    id: pinEnd
    interval: 180000
    onTriggered: win.unpin(true)
  }
  function unpin(walkBack) {
    if (!pin) return
    var from = { left: liveLeft, top: liveTop, hanging: hanging, at: Date.now() }
    pin = null
    pinEnd.stop()
    if (walkBack) Qt.callLater(function() { win.maybeWalk(from) })
  }
  function startDrag() {
    walkAnim.stop(); walkT = 0; buddy.walking = false; buddy.running = false; buddy.jumping = false
    homeTimer.stop(); dodgeMs = 0; dodge = 0
    settleX.stop(); settleY.stop(); settleDX = 0; settleDY = 0
    dragBaseLeft = curLeft
    dragBaseTop = curTop
    bubble.dismiss()
  }
  function drop() {
    dropLeft = dragBaseLeft + buddy.dragOffset.x
    dropTop = dragBaseTop + buddy.dragOffset.y
    landing = true
    clientsProc.running = true
  }
  property real dropLeft: 0
  property bool landing: false   // let go, waiting for the window list
  property real dropTop: 0
  function land(clients) {
    // Her seat line, in screen coordinates.
    var cx = screenX + dropLeft + buddy.width / 2
    var sy = screenY + dropTop + buddy.seatY
    var ws = win.perch.info && win.perch.info.workspace ? win.perch.info.workspace.id : null
    var best = null, bestD = 1e9
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      if (!c || !c.at || !c.size || c.hidden || c.mapped === false || !c.workspace || c.workspace.id !== ws) continue
      var x = c.at[0] - perch.borderSize, y = c.at[1] - perch.borderSize, wd = c.size[0] + 2 * perch.borderSize
      if (cx < x || cx > x + wd || x < screenX || x >= screenX + screenW) continue
      var d = Math.abs(y - sy)
      if (d < bestD) { bestD = d; best = { x: x, y: y, w: wd } }
    }
    var heldLeft = dropLeft, heldTop = dropTop
    landing = false
    if (best) {
      var hang = hangsOn(best.y)
      var left = Math.round(Math.max(best.x - screenX + 2, Math.min(heldLeft, best.x + best.w - screenX - buddy.width - 2)))
      pin = { left: clampLeft(left), top: seatTop(best.y, hang), hanging: hang, ws: ws }
      pinEnd.restart()
    } else pin = null
    // From where she was let go to her seat, with a little bounce.
    settleDX = heldLeft - clampLeft(wantLeft)
    settleDY = heldTop - Math.max(0, wantTop)
    settleX.restart(); settleY.restart()
  }
  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: { var c = []; try { c = JSON.parse(text) } catch (e) {} win.land(c) }
    }
  }

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
  readonly property real curLeft: buddy.dragging ? dragBaseLeft + buddy.dragOffset.x
    : landing ? dropLeft
    : clampLeft(wantLeft + dodge + walkT * walkDX) + settleDX
  readonly property real arcLift: buddy.jumping ? jumpHeight * Math.sin(Math.PI * walkT) : 0
  readonly property real curTop: buddy.dragging ? dragBaseTop + buddy.dragOffset.y
    : landing ? dropTop
    : Math.max(0, wantTop + walkT * walkDY) - arcLift + settleDY
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
      // Put down somewhere: she stays there, unless you've gone to another
      // workspace.
      if (win.pin) {
        Qt.callLater(function() {
          var info = win.perch.info
          if (!info || !info.workspace || info.workspace.id !== win.pin.ws) win.unpin(false)
        })
        return
      }
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
      win.unpin(false)
      bubble.dismiss()
      win.fallLeft = seat.left
      win.fallTop = seat.top
      win.falling = true
      buddy.fall()
      fallEnd.restart()
    }

    function onArrived() {
      if (buddy.walking || win.pin) return
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
      if (!(win.perch.hasWindow && win.onThisScreen)) return
      buddy.showSign(text)
      if (!buddy.packHasSign) win.perch.speakLine(text, true, "sign", "")
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
    meeting: win.perch.meeting
    music: win.perch.music
    movie: win.perch.movie
    windowTitle: win.onThisScreen ? win.perch.windowTitle : ""
    onDraggingChanged: if (dragging) win.startDrag()
    onDropped: win.drop()
  }
}
