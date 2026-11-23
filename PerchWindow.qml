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
  readonly property bool onDesktop: perch.desktop && perch.deskShow && buddy.packRoams && !!screen
  // Flying (broom trips, the loop when she says hello) in the view she's in.
  readonly property bool mayFly: buddy.packFlies && (onDesktop ? perch.deskFly : perch.winMove === "fly")
  // How she gets to a new spot: on the desktop she strolls ("desk": walks,
  // runs far, flies very far if allowed); between windows "run", "jump" or
  // "fly", as picked in the panel.
  readonly property string moveMode: onDesktop ? "desk" : perch.winMove
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
    if (!onDesktop || buddy.walking || buddy.dragging || enterPhase !== "") return
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
    if (enterPhase !== "" || !mayFly) return
    var from = curLeft
    roamLeft = clampLeft(x)
    var dx = from - roamLeft
    walkAnim.stop()
    walkDX = dx; walkDY = 0; walkT = 1
    jumpHeight = Math.min(screenH * 0.45, 140 + Math.abs(dx) * 0.3, Math.max(0, curTop - barTop - 6 * buddy.s))
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
      if (!win.onDesktop || win.deskSpot !== "floor" || buddy.climbing || buddy.dragging || win.enterPhase !== "") return
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
      if (buddy.focusing || buddy.packStays || win.enterPhase !== "") return   // she stays put while you focus, or while she's busy
      if (buddy.climbing || win.deskSpot === "bar") return
      var r = Math.random()
      var x = Math.random() * (win.screenW - buddy.width)
      if (r < 0.13 && win.mayFly) win.skyTrip()
      else if (r < 0.18 && win.mayFly && Math.abs(x - win.curLeft) > 300) win.flyTo(x)
      else if (r < 0.23 && buddy.packClimbs && win.floorTop - win.barTop > 200) win.climb(true)
      else if (r < 0.55 && Math.abs(x - win.curLeft) > 80) win.roamTo(x, false)
    }
  }
  property var floorSeat: null
  onLiveLeftChanged: if (onDesktop && !buddy.walking) floorSeat = { left: liveLeft, top: liveTop, hanging: win.hanging, at: Date.now() }
  onOnDesktopChanged: {
    // A window came up mid sky trip: she heads there now.
    if (!onDesktop && enterKind === "sky" && enterPhase !== "") { enterAnim.stop(); endEntrance() }
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
    if (buddy.peekSide !== 0) return     // hiding: a click finds her, the pointer doesn't
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
  readonly property real curLeft: enterPhase !== "" ? enterLeft
    : buddy.dragging ? dragBaseLeft + buddy.dragOffset.x
    : landing ? dropLeft
    : entering ? wantLeft + walkT * walkDX
    : onDesktop && peeking ? wantLeft + walkT * walkDX
    : clampLeft(wantLeft + dodge + walkT * walkDX) + settleDX
  readonly property real arcLift: buddy.jumping || buddy.flying
    ? jumpHeight * Math.sin(Math.PI * walkT) + (buddy.flying ? 5 * buddy.s * Math.sin(walkT * flyWaves * Math.PI * 2) : 0) : 0
  property real flyWaves: 3
  // The jump or broom arc never takes her above the bar (off the screen):
  // near the top it flattens out.
  readonly property real pathTop: Math.max(0, wantTop + walkT * walkDY)
  readonly property real curTop: enterPhase !== "" ? enterTop
    : buddy.dragging ? dragBaseTop + buddy.dragOffset.y
    : landing ? dropTop
    : pathTop - Math.min(arcLift, Math.max(0, pathTop - barTop)) + settleDY
      + (tripRun && tripToSwing ? buddy.seatPad * buddy.s : 0)
  readonly property int liveLeft: Math.round(curLeft)
  readonly property int liveTop: Math.round(curTop)
  property var prevSeat: null

  // Travelling to the next window instead of popping up there: on a level
  // edge she walks (runs if it's far; on her swing under the bar the swing
  // slides along), anywhere else on the screen she jumps there in an arc.
  // The offset from her new place shrinks from (walkDX, walkDY) to nothing.
  property real walkDX: 0
  // A run that isn't along the swing: she's off it (run pose, no ropes)
  // until she gets there; the swing's padding is kept so nothing jumps.
  property bool tripRun: false
  property bool tripToSwing: false
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
    onFinished: {
      var flew = buddy.flying
      buddy.walking = false; buddy.running = false; buddy.jumping = false; buddy.flying = false
      if (win.entering) { win.entering = false; buddy.welcomed(win.enterKind); return }
      if (!win.onDesktop && !flew) buddy.wave()
    }
  }

  function maybeWalk(from) {
    if (!from || falling || !win.here || !buddy.motion || win.perch.sleeping || enterPhase !== "") return false
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
    var flyNow = mayFly && dist > (moveMode === "fly" ? 250 : 450)
    // Room above the higher end of the trip, below the bar: a jump needs
    // some, or it's a flat shuffle in a jumping pose.
    var room = Math.max(0, Math.min(from.top, Math.max(0, wantTop)) - barTop - 6 * buddy.s)
    var canArc = room >= 30 * buddy.s
    // Swing to swing under the bar: the swing slides along.
    var swingSlide = level && from.hanging && hanging
    // Run: she runs there in any direction. Jump: she jumps (where there's
    // room to). On the desktop she jumps only up to or down from it.
    var jumpNow = !flyNow && !swingSlide && canArc && (moveMode === "jump" || (moveMode === "desk" && !level))
    tripRun = false
    if (!flyNow && !jumpNow) {
      var run = !swingSlide && (moveMode !== "desk" || !level || Math.abs(dx) >= runFrom)
      var speed = swingSlide ? slideSpeed : run ? runSpeed : walkSpeed
      walkAnim.duration = Math.max(400, Math.min(5000, (swingSlide ? Math.abs(dx) : dist) / speed * 1000))
      buddy.running = run
      buddy.jumping = false
      tripToSwing = hanging
      tripRun = !swingSlide && (from.hanging || hanging)
    } else if (flyNow) {
      // Far: on her broom, in a long gentle arc.
      jumpHeight = Math.min(240, 60 + 0.2 * dist, room)
      flyWaves = Math.max(1, Math.round(dist / 350))
      walkAnim.duration = Math.max(1000, Math.min(2800, 600 + 0.9 * dist))
      buddy.running = false
      buddy.jumping = false
      buddy.flying = true
    } else {
      jumpHeight = Math.min(160, 30 * buddy.s + 0.18 * dist, Math.max(12 * buddy.s, room))
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
  // Stepped out of a screenshot (the `shot` command with "hide").
  visible: !perch.shotHidden
  mask: Region {
    x: Math.round(buddy.x + buddy.hitBox.x)
    y: Math.round(buddy.y + buddy.hitBox.y)
    width: Math.round(buddy.hitBox.width)
    height: Math.round(buddy.hitBox.height)
    // A prop you can click (her pet).
    Region {
      x: Math.round(win.tapRect.x); y: Math.round(win.tapRect.y)
      width: win.onDesktop ? Math.round(win.tapRect.width) : 0
      height: win.onDesktop ? Math.round(win.tapRect.height) : 0
    }
    // Sticky notes on the desktop.
    Region {
      x: Math.round(noteBoard.x); y: Math.round(noteBoard.y)
      width: noteBoard.visible ? Math.round(noteBoard.width) : 0
      height: noteBoard.visible ? Math.round(noteBoard.height + 8) : 0
    }
  }

  // Hide and seek: to an edge of the desktop, mostly off screen, and back.
  readonly property bool peeking: buddy.peekSide !== 0 || peekReturn
  property bool peekReturn: false
  Connections {
    target: buddy
    function onPeekSideChanged() { win.peekWalk() }
  }
  function peekWalk() {
    if (!onDesktop || enterPhase !== "" || buddy.climbing || deskSpot !== "floor") return
    var from = curLeft
    peekReturn = buddy.peekSide === 0
    roamLeft = buddy.peekSide < 0 ? -buddy.width * 0.45
      : buddy.peekSide > 0 ? screenW - buddy.width * 0.55
      : clampLeft(screenW * (0.2 + Math.random() * 0.6))
    var dx = from - roamLeft
    if (Math.abs(dx) < 4) { peekReturn = false; return }
    walkAnim.stop()
    walkDX = dx; walkDY = 0; walkT = 1
    walkAnim.duration = Math.max(500, Math.min(4000, Math.abs(dx) / runSpeed * 1000))
    buddy.running = true
    buddy.jumping = false
    buddy.walkDir = dx < 0 ? 1 : -1
    buddy.walking = true
    walkAnim.start()
  }
  Connections {
    target: buddy
    function onWalkingChanged() { if (!buddy.walking) { win.peekReturn = false; win.tripRun = false } }
  }
  property rect tapRect: Qt.rect(0, 0, 0, 0)

  // Her entrance: from off screen, high up, to where she belongs.
  property bool entering: false
  property string enterKind: ""
  function enter(kind) {
    if (!here || buddy.dragging || pin || falling || buddy.walking || enterPhase !== "") return
    if (!((perch.hasWindow && onThisScreen) || onDesktop)) return
    var right = Math.random() < 0.5
    enterKind = kind
    if (mayFly) {
      // On her broom: in from the side, a loop in the middle of the screen,
      // a hover there while she says hello, then off to her place.
      startFlight(right ? screenW + 30 : -buddy.width - 30, screenH * 0.18,
                  screenW / 2 - buddy.width / 2, screenH * 0.34 - buddy.height / 2,
                  Math.min(180, screenW * 0.11), right ? -1 : 1, 1, 6500, 1400)
      perch.entered()
      return
    }
    var from = { left: right ? screenW + 30 : -buddy.width - 30, top: screenH * 0.3, hanging: false }
    entering = true
    if (!maybeWalk(from)) { entering = false; return }
    perch.entered()
  }

  // A sky trip on the desktop: up from the floor, a loop or two somewhere
  // in the sky, a hover, then down somewhere else on the floor.
  function skyTrip(asked) {
    if (!onDesktop || !(asked ? buddy.packFlies : mayFly) || enterPhase !== "" || buddy.walking || buddy.dragging || buddy.climbing || deskSpot !== "floor") return
    var r = Math.min(200, screenW * 0.06 + Math.random() * screenW * 0.07)
    var cx = r + 20 + Math.random() * Math.max(1, screenW - buddy.width - 2 * r - 40)
    var top = Math.max(barTop + 20, 0) + 0.5 * r
    var cy = top + Math.random() * Math.max(1, screenH * 0.45 - top)
    enterKind = "sky"
    startFlight(curLeft, curTop, cx, cy, r, Math.random() < 0.5 ? -1 : 1, Math.random() < 0.35 ? 2 : 1,
                2500 + Math.random() * 4500, 1100 + Math.min(1200, Math.abs(cy - curTop) * 1.5))
  }

  // Asked to fly while on a window: a loop in the middle of the screen, a
  // hover, and back to her window.
  function windowFly() {
    if (!buddy.packFlies || !(perch.hasWindow && onThisScreen) || enterPhase !== "" || buddy.walking || buddy.dragging || falling || pin) return
    enterKind = "sky"
    startFlight(curLeft, curTop, screenW / 2 - buddy.width / 2, screenH * 0.34 - buddy.height / 2,
                Math.min(180, screenW * 0.11), Math.random() < 0.5 ? -1 : 1, 1, 2500, 1100)
  }

  // Sky trips with windows open, if you want them: now and then a loop
  // over the screen and back to her window.
  Timer {
    interval: 240000
    repeat: true
    running: win.perch.winSky && buddy.packFlies && win.perch.hasWindow && win.onThisScreen && !win.perch.sleeping
    onTriggered: {
      interval = 180000 + Math.random() * 300000
      if (win.perch.focusing || buddy.meeting || bubble.active || buddy.hanging && Math.random() < 0.5) return
      win.windowFly()
    }
  }

  // One broom flight: from (x, y) to the edge of a loop around (cx, cy),
  // `turns` times round (dir 1 or -1), to its middle, a hover for `hoverMs`,
  // then `endEntrance()`.
  function startFlight(x, y, cx, cy, r, dir, turns, hoverMs, inMs) {
    loopCX = cx; loopCY = cy; loopR = r; loopDir = dir; loopTurns = turns
    flightHoverMs = hoverMs; flightInMs = inMs
    // Join the loop on the side she comes from.
    loopStartA = x > cx ? 0 : Math.PI
    enterX = x; enterY = y
    circleA = loopStartA
    enterPhase = "in"
    buddy.flying = true
    buddy.walkDir = cx + (x > cx ? r : -r) > x ? 1 : -1
    enterAnim.restart()
  }
  // The flight: "in", "circle", "center", "hover", or "" when not flying one.
  property string enterPhase: ""
  property real enterX: 0
  property real enterY: 0
  property real circleA: 0
  property real bobT: 0
  property real loopCX: 0
  property real loopCY: 0
  property real loopR: 150
  property int loopDir: 1
  property int loopTurns: 1
  property real loopStartA: 0
  property int flightHoverMs: 6500
  property int flightInMs: 1400
  readonly property bool onCircle: enterPhase === "circle"
  readonly property real enterLeft: onCircle ? loopCX + loopR * Math.cos(circleA) : enterX
  readonly property real enterTop: (onCircle ? loopCY + 0.5 * loopR * Math.sin(circleA) : enterY)
    + (enterPhase === "hover" ? 7 * buddy.s * Math.sin(bobT) : 0)
  // Facing the way she's going round the loop.
  onCircleAChanged: if (onCircle) { var vx = -Math.sin(circleA) * loopDir; if (Math.abs(vx) > 0.05) buddy.walkDir = vx > 0 ? 1 : -1 }
  SequentialAnimation {
    id: enterAnim
    ParallelAnimation {
      NumberAnimation { target: win; property: "enterX"; to: win.loopCX + win.loopR * Math.cos(win.loopStartA); duration: win.flightInMs; easing.type: Easing.OutQuad }
      NumberAnimation { target: win; property: "enterY"; to: win.loopCY; duration: win.flightInMs; easing.type: Easing.InOutSine }
    }
    ScriptAction { script: win.enterPhase = "circle" }
    NumberAnimation {
      target: win; property: "circleA"; duration: 2300 * win.loopTurns; easing.type: Easing.InOutSine
      from: win.loopStartA
      to: win.loopStartA + win.loopDir * 2 * Math.PI * win.loopTurns
    }
    ScriptAction { script: { win.enterX = win.loopCX + win.loopR * Math.cos(win.loopStartA); win.enterY = win.loopCY; win.enterPhase = "center" } }
    ParallelAnimation {
      NumberAnimation { target: win; property: "enterX"; to: win.loopCX; duration: 700; easing.type: Easing.OutCubic }
      NumberAnimation { target: win; property: "enterY"; to: win.loopCY - 10; duration: 700; easing.type: Easing.OutCubic }
    }
    ScriptAction { script: { win.enterPhase = "hover"; if (win.enterKind === "sky") buddy.skyHover(); else buddy.welcomed(win.enterKind) } }
    PauseAnimation { duration: win.flightHoverMs }
    ScriptAction { script: win.endEntrance() }
  }
  NumberAnimation on bobT { from: 0; to: 2 * Math.PI; duration: 1600; loops: Animation.Infinite; running: win.enterPhase === "hover" }
  function endEntrance() {
    var from = { left: enterLeft, top: enterTop, hanging: false }
    enterPhase = ""
    buddy.flying = false
    // From a sky trip she lands somewhere new on the floor.
    if (enterKind === "sky" && onDesktop) roamLeft = clampLeft(Math.random() * (screenW - buddy.width))
    enterKind = ""
    if (!maybeWalk(from)) return
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

    function onFocusStarted(minutes) { buddy.focusStarted(minutes) }
    function onEntrance(kind) { win.enter(kind) }
    function onSense(kind, app) {
      if (!((win.perch.hasWindow && win.onThisScreen) || win.onDesktop)) return
      buddy.sensed(kind, app)
      if (buddy.packSenses) return
      var l = win.perch.pickLine(win.perch.lines[kind])
      if (l) win.perch.speakLine(l.replace("{app}", app), true, kind, "")
    }
    function onFocusDone(minutes) { buddy.focusDone(minutes) }

    function onShowSign(text) {
      if (!(win.perch.hasWindow && win.onThisScreen) && !win.onDesktop) return
      buddy.showSign(text)
      if (!buddy.packHasSign) win.perch.speakLine(text, true, "sign", "")
    }

    function onAct(what) {
      if (!(win.perch.hasWindow && win.onThisScreen) && !win.onDesktop) return
      if (what === "fly") { if (win.onDesktop) win.skyTrip(true); else win.windowFly() }
      else if (what === "wave") buddy.wave()
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

  // What the panel can ask her to do: the pack's own moves, and whether
  // she has a broom. The bar panel reads this file.
  FileView {
    id: movesFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/perch-moves.json"
    printErrors: false
  }
  Timer {
    id: movesWrite
    interval: 600
    running: true
    onTriggered: if (win.screen === Quickshell.screens[0]) movesFile.setText(JSON.stringify({ flies: buddy.packFlies, moves: buddy.packMoves }) + "\n")
  }
  Connections {
    target: buddy
    function onPackMovesChanged() { movesWrite.restart() }
    function onPackFliesChanged() { movesWrite.restart() }
  }

  // Rain or snow across the empty workspace, when her pack says it's
  // falling outside; leaves, petals or snowflakes drifting; fireflies by
  // the camp. Only on the desktop while you're here (Drift.qml: a few
  // images on one slow timer, not a 60 fps particle system).
  function ambientHas(kind) {
    var l = buddy.ambient
    for (var i = 0; i < l.length; i++) if (l[i] === kind || (l[i] && l[i].kind === kind)) return l[i]
    return null
  }
  readonly property bool airOn: onDesktop && perch.deskAir && !perch.sleeping
  Loader {
    anchors.fill: parent
    active: win.airOn && buddy.weather !== ""
    sourceComponent: Drift {
      kind: buddy.weather === "rain" ? "rain" : "snow"
      count: (buddy.weather === "rain" ? 70 : 55) * (win.perch.onBattery ? 0.5 : 1)
    }
  }
  readonly property string driftKind: ambientHas("leaves") ? "leaf" : ambientHas("petals") ? "petal"
    : ambientHas("snowflakes") && buddy.weather !== "snow" ? "snow" : ""
  Loader {
    anchors.fill: parent
    active: win.airOn && win.driftKind !== ""
    sourceComponent: Drift {
      kind: win.driftKind
      count: (win.driftKind === "snow" ? 40 : 14) * (win.perch.onBattery ? 0.5 : 1)
    }
  }
  readonly property var fireflies: ambientHas("fireflies")
  Loader {
    anchors.fill: parent
    active: win.airOn && win.fireflies !== null
    sourceComponent: Drift {
      kind: "firefly"
      count: 12
      originX: (win.fireflies ? Number(win.fireflies.x || 0.85) : 0.85) * win.screenW
      originY: win.screenH - 20
    }
  }

  // A shooting star across the night sky now and then ("stars").
  Timer {
    interval: 60000
    repeat: true
    running: win.airOn && win.ambientHas("stars") !== null
    onTriggered: {
      interval = 120000 + Math.random() * 240000
      shootingStar.go()
    }
  }
  Rectangle {
    id: shootingStar
    visible: starRun.running
    width: 150; height: 2.5; radius: 1.25
    rotation: 18
    transformOrigin: Item.Right
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "#00ffffff" }
      GradientStop { position: 1; color: "#ffffffee" }
    }
    function go() {
      x = win.screenW * (0.1 + Math.random() * 0.45)
      y = win.barTop + 30 + Math.random() * win.screenH * 0.18
      starX.from = x; starX.to = x + 520
      starY.from = y; starY.to = y + 170
      starRun.restart()
      buddy.shootingStar()
    }
    ParallelAnimation {
      id: starRun
      NumberAnimation { id: starX; target: shootingStar; property: "x"; duration: 950; easing.type: Easing.InQuad }
      NumberAnimation { id: starY; target: shootingStar; property: "y"; duration: 950; easing.type: Easing.InQuad }
      SequentialAnimation {
        NumberAnimation { target: shootingStar; property: "opacity"; from: 0; to: 1; duration: 200 }
        PauseAnimation { duration: 450 }
        NumberAnimation { target: shootingStar; property: "opacity"; to: 0; duration: 300 }
      }
    }
  }

  // Soap bubbles from her wand (the pack says where, while she blows).
  // The layer stays a few seconds after she lowers the wand, so the last
  // bubbles float away instead of vanishing.
  property bool bubbling: false
  property var bubbleFrom: null
  Connections {
    target: buddy
    function onBubbleAtChanged() {
      if (buddy.bubbleAt === null) { bubbleLinger.restart(); return }
      win.bubbleFrom = buddy.bubbleAt
      win.bubbling = true
      bubbleLinger.stop()
    }
  }
  Timer { id: bubbleLinger; interval: 5000; onTriggered: win.bubbling = false }
  Loader {
    anchors.fill: parent
    active: win.onDesktop && win.bubbling
    sourceComponent: Drift {
      kind: "bubble"
      count: 9
      emitting: buddy.bubbleAt !== null
      scaleBy: 0.6 + 0.4 * buddy.s
      originX: buddy.x + (win.bubbleFrom ? win.bubbleFrom[0] : 0) * buddy.s
      originY: buddy.y + (buddy.pad + (win.bubbleFrom ? win.bubbleFrom[1] : 0)) * buddy.s
    }
  }

  // Sticky notes (`omarchy-shell jebin2.perch note "call mom at 6"`), pinned
  // under the bar on the desktop. Click one to take it down.
  Row {
    id: noteBoard
    visible: win.perch.desktop && win.perch.deskNotes && !!win.screen && win.perch.notes.length > 0
    x: 18
    y: win.barTop + 14
    spacing: 12
    Repeater {
      model: win.perch.notes.slice(0, 8)
      Item {
        required property var modelData
        required property int index
        width: 132; height: 98
        rotation: index % 2 ? 2.2 : -1.8
        Rectangle { x: 3; y: 4; width: parent.width; height: parent.height; radius: 2; color: "#38000000" }
        Rectangle { anchors.fill: parent; radius: 2; color: "#fff1a6"; border.color: "#d9c15c"; border.width: 1 }
        Rectangle { width: 44; height: 13; x: parent.width / 2 - 22; y: -6; rotation: -4; color: "#a8ffffff"; border.color: "#30000000"; border.width: 0.5 }
        Text {
          x: 9; y: 10; width: parent.width - 18; height: parent.height - (dueText.visible ? 30 : 16)
          textFormat: Text.PlainText
          text: modelData.text
          color: "#3a3220"
          font.pixelSize: 14
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
        }
        Text {
          id: dueText
          visible: Number(modelData.due) > 0
          anchors.right: parent.right; anchors.bottom: parent.bottom
          anchors.rightMargin: 8; anchors.bottomMargin: 5
          textFormat: Text.PlainText
          text: visible ? "\u23F0 " + Qt.formatTime(new Date(Number(modelData.due)), "h:mm AP") : ""
          color: "#7a6a30"
          font.pixelSize: 11
        }
        TapHandler { onTapped: win.perch.removeNote(modelData.id) }
      }
    }
  }

  // Things her pack puts on the desktop floor (a plant, a pet...). The
  // delegates stay while the list keeps its length, so things glide.
  Repeater {
    model: win.onDesktop ? buddy.desktopProps.length : 0
    Image {
      id: prop
      required property int index
      readonly property var p: buddy.desktopProps[index] || ({})
      width: Number(p.w || 0) * buddy.s
      height: Number(p.h || 0) * buddy.s
      x: Math.round(Number(p.x || 0) * win.screenW - width / 2)
      y: Math.round(win.screenH - height - Number(p.lift || 0) * buddy.s)
      z: p.front ? 1 : 0
      Behavior on x { enabled: Number(prop.p.speed) > 0; SmoothedAnimation { velocity: Math.max(1, Number(prop.p.speed) || 1) * buddy.s } }
      mirror: !!p.mirror
      source: p.source || ""
      smooth: true; mipmap: true
      asynchronous: true
      Binding { when: !!prop.p.tap; target: win; property: "tapRect"; value: Qt.rect(prop.x, prop.y, prop.width, prop.height) }
      TapHandler {
        enabled: !!prop.p.tap
        onTapped: buddy.propTapped(String(prop.p.id || prop.index))
      }
    }
  }

  // The focus timer, small, near her.
  Rectangle {
    id: focusChip
    visible: buddy.focusing && buddy.visible && !bubble.active
    readonly property int secs: buddy.focusLeft
    width: focusText.implicitWidth + 12; height: focusText.implicitHeight + 4
    radius: height / 2
    color: Qt.rgba(0.08, 0.08, 0.1, 0.72)
    border.color: Qt.rgba(1, 1, 1, 0.25); border.width: 1
    x: Math.round(buddy.x + buddy.width / 2 - width / 2)
    y: win.hanging || buddy.y < 40 ? Math.round(buddy.y + buddy.height + 2) : Math.round(buddy.y - height - 2)
    Text {
      id: focusText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "◷ " + Math.floor(focusChip.secs / 60) + ":" + ("0" + focusChip.secs % 60).slice(-2)
      color: "white"
      font.pixelSize: 11
      font.bold: true
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
    hanging: win.perch.hasWindow && win.onThisScreen && win.hanging && win.enterPhase === "" && !win.tripRun
    onPoked: function(x) { win.flee(x) }
    onWantsToSay: function(line, topic) { win.perch.speakLine(line, true, topic, "") }
    meeting: win.perch.meeting
    roaming: win.onDesktop
    deskX: win.screenW > 0 ? (win.curLeft + width / 2) / win.screenW : 0.5
    music: win.perch.music
    movie: win.perch.movie
    focusing: win.perch.focusing
    games: win.perch.deskGames
    focusLeft: win.perch.focusLeft
    windowTitle: win.onThisScreen ? win.perch.windowTitle : ""
    onDraggingChanged: if (dragging) win.startDrag()
    onDropped: win.drop()
  }
}
