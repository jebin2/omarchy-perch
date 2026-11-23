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
  readonly property bool here: (perch.hasWindow && onThisScreen) || onDesktop || falling
  readonly property real screenH: screen ? screen.height : 0

  // ---- On the desktop ------------------------------------------------------
  // An empty workspace: a character that can roam lives on the bottom of
  // the screen. Every 6-14 s she may walk (or run) somewhere; the pack
  // decides what she does in between. Opening a window, she jumps up on it.
  readonly property bool onDesktop: perch.desktop && buddy.packRoams && !!screen
    && perch.desktopMonitor === screen.name
  property real roamLeft: 0
  // Up on the bar (after climbing her ladder): she swings from it.
  property string deskSpot: "floor"    // "floor" or "bar"
  readonly property real floorTop: screenH - buddy.seatY
  readonly property real barTop: Math.round(perch.desktopReservedTop) + perch.borderSize
  property real climbT: 0              // 0 on the floor .. 1 up at the bar
  property real ladderX: 0             // the ladder's centre, screen px
  property bool ladderUp: false
  NumberAnimation {
    id: climbAnim
    target: win
    property: "climbT"
    easing.type: Easing.Linear
    onFinished: {
      buddy.climbing = false
      if (win.climbT >= 1) { win.deskSpot = "bar"; barTime.interval = 30000 + Math.random() * 40000; barTime.restart() }
      else { win.deskSpot = "floor"; win.ladderUp = false }
    }
  }
  function climb(up) {
    if (!onDesktop || buddy.walking || buddy.dragging) return
    if (up) { ladderX = curLeft + buddy.width / 2; ladderUp = true; deskSpot = "floor" }
    var h = Math.max(1, floorTop - barTop)
    climbAnim.stop()
    climbAnim.from = up ? 0 : 1
    climbAnim.to = up ? 1 : 0
    climbAnim.duration = Math.max(1500, h / (110 * buddy.s) * 1000)
    buddy.climbDir = up ? 1 : -1
    buddy.climbing = true
    if (!up) deskSpot = "floor"
    climbAnim.start()
  }
  Timer { id: barTime; onTriggered: if (win.onDesktop && win.deskSpot === "bar") win.climb(false) }
  function leaveLadder() {
    climbAnim.stop(); barTime.stop()
    buddy.climbing = false; climbT = 0; ladderUp = false; deskSpot = "floor"
  }
  // A joyride on her broom, along the desktop.
  function flyTo(x) {
    var from = curLeft
    roamLeft = clampLeft(x)
    var dx = from - roamLeft
    walkAnim.stop()
    walkDX = dx; walkDY = 0; walkT = 1
    jumpHeight = Math.min(screenH * 0.45, 140 + Math.abs(dx) * 0.3)
    flyWaves = Math.max(1, Math.round(Math.abs(dx) / 300))
    walkAnim.duration = Math.max(1400, Math.min(3400, 900 + Math.abs(dx) * 1.4))
    buddy.running = false; buddy.jumping = false; buddy.flying = true
    buddy.walkDir = dx < 0 ? 1 : -1
    buddy.walking = true
    walkAnim.start()
  }
  Connections {
    target: buddy
    function onWantsToGo(fraction) {
      if (!win.onDesktop || win.deskSpot !== "floor" || buddy.climbing || buddy.dragging) return
      win.roamTo(fraction * win.screenW - buddy.width / 2, false)
    }
  }
  function roamTo(x, run) {
    var from = curLeft
    roamLeft = clampLeft(x)
    var dx = from - roamLeft
    if (Math.abs(dx) < 4) return
    walkAnim.stop()
    walkDX = dx; walkDY = 0; walkT = 1
    var r = run || Math.abs(dx) >= runFrom
    walkAnim.duration = Math.max(400, Math.min(9000, Math.abs(dx) / (r ? runSpeed : walkSpeed) * 1000))
    buddy.running = r
    buddy.jumping = false
    buddy.walkDir = dx < 0 ? 1 : -1
    buddy.walking = true
    walkAnim.start()
  }
  Timer {
    id: roamTick
    interval: 8000
    repeat: true
    running: win.onDesktop
    onTriggered: {
      interval = 6000 + Math.random() * 8000
      if (buddy.walking || buddy.dragging || win.perch.sleeping || win.falling || bubble.active || buddy.meeting || buddy.climbing) return
      if (buddy.climbing || win.deskSpot === "bar") return
      var r = Math.random()
      var x = Math.random() * (win.screenW - buddy.width)
      if (r < 0.10 && buddy.packFlies && Math.abs(x - win.curLeft) > 300) win.flyTo(x)
      else if (r < 0.16 && buddy.packClimbs && win.floorTop - win.barTop > 200) win.climb(true)
      else if (r < 0.55 && Math.abs(x - win.curLeft) > 80) win.roamTo(x, false)
    }
  }
  property var floorSeat: null
  onLiveLeftChanged: if (onDesktop && !buddy.walking) floorSeat = { left: liveLeft, top: liveTop, hanging: win.hanging, at: Date.now() }
  onOnDesktopChanged: {
    if (onDesktop) {
      homeTimer.stop(); dodgeMs = 0; dodge = 0
      leaveLadder()
      if (falling) { roamLeft = clampLeft(fallLeft); return }
      // Running in from the nearer side.
      var x = screenW * (0.25 + Math.random() * 0.5)
      var fromLeft = Math.random() < 0.5
      roamLeft = clampLeft(x)
      walkAnim.stop()
      walkDX = (fromLeft ? 0 : screenW - buddy.width) - roamLeft; walkDY = 0; walkT = 1
      walkAnim.duration = Math.max(500, Math.abs(walkDX) / runSpeed * 1000)
      buddy.running = true; buddy.jumping = false
      buddy.walkDir = walkDX < 0 ? 1 : -1
      buddy.walking = true
      walkAnim.start()
    } else if (floorSeat && perch.hasWindow && onThisScreen) {
      var from = floorSeat
      leaveLadder()
      Qt.callLater(function() { win.maybeWalk(from) })
    }
  }
  readonly property real screenX: screen ? screen.x : 0
  readonly property real screenY: screen ? screen.y : 0
  readonly property real screenW: screen ? screen.width : 0

  // Her right edge goes `inset` from the window's right edge. With room above
  // the window she sits on its top border; a window right under the bar
  // leaves no room, so there she swings from the border, inside the window.
  function hangsOn(y) { return y - buddy.sitHeight < screenY + perch.reservedTop }
  function seatTop(y, hang) { return Math.round(hang ? y + perch.borderSize - screenY : y - buddy.seatY - screenY) }
  readonly property bool hanging: pin ? pin.hanging : onDesktop ? deskSpot === "bar" && !buddy.climbing : hangsOn(perch.winY)
  readonly property int wantLeft: pin ? pin.left : onDesktop ? Math.round(roamLeft) : Math.round(perch.winX + perch.winW - perch.inset - buddy.width - screenX)
  readonly property int wantTop: pin ? pin.top : onDesktop ? Math.round(buddy.climbing ? floorTop + (barTop - floorTop) * climbT : deskSpot === "bar" ? barTop : floorTop) : seatTop(perch.winY, hanging)

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
    leaveLadder()
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
    } else {
      pin = null
      if (onDesktop) roamLeft = clampLeft(heldLeft)   // on the floor where you let go
    }
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
    if (onDesktop && (deskSpot === "bar" || buddy.climbing)) { buddy.startle(x < buddy.width / 2 ? 1 : -1); return }
    if (onDesktop) {
      // Along the floor, away from the pointer.
      var away = x < buddy.width / 2 ? 1 : -1
      var to = curLeft + away * (buddy.width + 120)
      if (to < 0 || to > screenW - buddy.width) to = curLeft - away * (buddy.width + 120)
      buddy.startle(to < curLeft ? -1 : 1)
      roamTo(to, true)
      return
    }
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
  readonly property real arcLift: buddy.jumping || buddy.flying
    ? jumpHeight * Math.sin(Math.PI * walkT) + (buddy.flying ? 5 * buddy.s * Math.sin(walkT * flyWaves * Math.PI * 2) : 0) : 0
  property real flyWaves: 3
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
    onFinished: { var flew = buddy.flying; buddy.walking = false; buddy.running = false; buddy.jumping = false; buddy.flying = false; if (!win.onDesktop && !flew) buddy.wave() }
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
    } else if (buddy.packFlies && dist > 450) {
      // Far: on her broom, in a long gentle arc.
      jumpHeight = Math.min(240, 60 + 0.2 * dist)
      flyWaves = Math.max(1, Math.round(dist / 350))
      walkAnim.duration = Math.max(1000, Math.min(2800, 600 + 0.9 * dist))
      buddy.running = false
      buddy.jumping = false
      buddy.flying = true
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
      // From the desktop she jumps up once the new window is known (below).
      if (win.onDesktop) { win.floorSeat = { left: win.liveLeft, top: win.liveTop, hanging: win.hanging, at: Date.now() }; return }
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
      if (!((win.perch.hasWindow && win.onThisScreen) || win.onDesktop) || win.falling) return
      bubble.show(line)
      buddy.heard(topic, mood, line)
    }

    function onShowSign(text) {
      if (!(win.perch.hasWindow && win.onThisScreen) && !win.onDesktop) return
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

  // Things her pack puts on the desktop floor (a plant...).
  Repeater {
    model: win.onDesktop ? buddy.desktopProps : []
    Image {
      required property var modelData
      width: Number(modelData.w || 0) * buddy.s
      height: Number(modelData.h || 0) * buddy.s
      x: Math.round(Number(modelData.x || 0) * win.screenW - width / 2)
      y: Math.round(win.screenH - height)
      source: modelData.source || ""
      smooth: true; mipmap: true
      asynchronous: true
    }
  }

  // Her ladder: from the floor up to the bar.
  Item {
    id: ladder
    visible: opacity > 0
    opacity: win.ladderUp && win.onDesktop ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(250) } }
    readonly property real w: 30 * buddy.s
    x: Math.round(win.ladderX - w / 2)
    y: win.barTop - 2
    width: w
    height: win.screenH - y
    readonly property real step: 13 * buddy.s
    Repeater {
      model: Math.max(0, Math.floor(ladder.height / ladder.step))
      Rectangle {
        required property int index
        x: 2 * buddy.s; width: ladder.w - 4 * buddy.s
        y: ladder.height - (index + 1) * ladder.step + ladder.step / 2
        height: 2.6 * buddy.s; radius: height / 2
        color: "#b98552"; border.color: "#3a2818"; border.width: 0.8
      }
    }
    Repeater {
      model: 2
      Rectangle {
        required property int index
        x: index === 0 ? 0 : ladder.w - width
        width: 3.6 * buddy.s; height: ladder.height; radius: width / 2
        color: "#9c6b42"; border.color: "#3a2818"; border.width: 0.8
      }
    }
  }

  Bubble {
    id: bubble
    x: buddy.x - width + 2
    y: buddy.y + Math.round((buddy.pad + 6) * buddy.s)
  }

  // Perch needs to know whether this character can live on the desktop.
  Binding { target: win.perch; property: "canRoam"; value: buddy.packRoams }

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
    roaming: win.onDesktop
    deskX: win.screenW > 0 ? (win.curLeft + width / 2) / win.screenW : 0.5
    music: win.perch.music
    movie: win.perch.movie
    windowTitle: win.onThisScreen ? win.perch.windowTitle : ""
    onDraggingChanged: if (dragging) win.startDrag()
    onDropped: win.drop()
  }
}
