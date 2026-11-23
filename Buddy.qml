import QtQuick
import qs.Commons

// Mochi. Drawn in a 64 x 80 grid and scaled by `s`. Her seat line is y = 56:
// everything above it sits on the window's top edge, her legs hang below it.
//
// Every loop is driven by one clock, `t`, which runs 0 -> 12 s and wraps.
// All periods divide 12 so nothing jumps at the wrap.
Item {
  id: buddy

  property real s: 1
  property bool shown: false
  property bool sleeping: false
  // On a swing hanging from the window's top border, instead of on it.
  property bool hanging: false

  // Rope above her head while on the swing, in grid units.
  readonly property real pad: hanging ? 7 : 0
  readonly property real sitHeight: 56 * s
  readonly property real seatY: (56 + pad) * s
  readonly property bool motion: Style.duration(1000) > 0
  readonly property real tau: Math.PI * 2

  // Which character to draw: a pack folder holding Character.qml.
  readonly property string defaultCharacterUrl: Qt.resolvedUrl("characters/mochi/Character.qml")
  property string characterUrl: defaultCharacterUrl
  onCharacterUrlChanged: character.load()

  // A pack can draw some things itself: `ownSwing` (its own ropes while she
  // hangs) and `ownFall` (its own falling frames, so Perch only drops and
  // fades her instead of also tipping her over).
  readonly property bool packOwnsSwing: !!(character.item && character.item.ownSwing)
  readonly property bool packOwnsFall: !!(character.item && character.item.ownFall)
  // The pack draws signs itself: then the text isn't also said in a bubble.
  readonly property bool packHasSign: !!(character.item && character.item.hasSign)
  // The pack can stand and walk on the desktop (an empty workspace).
  readonly property bool packRoams: !!(character.item && character.item.roams)
  // She's on the desktop: the bottom of the screen is her floor.
  property bool roaming: false
  // Packs that can fly a broom (`flies: true`) take it on long trips and for
  // joyrides on the desktop; packs that can climb (`climbs: true`) take a
  // ladder from the desktop floor up to the bar and swing there a while.
  readonly property bool packFlies: !!(character.item && character.item.flies)
  readonly property bool packClimbs: !!(character.item && character.item.climbs)
  // A pack busy at something on the desktop (toasting marshmallows, a cat
  // in her lap) sets `stay: true`: she doesn't wander off by herself.
  readonly property bool packStays: !!(character.item && character.item.stay)
  property bool flying: false
  property bool climbing: false
  property int climbDir: 1             // 1 up, -1 down
  // On the desktop: where she is across the screen (0 left .. 1 right), and
  // a way for the pack to send her somewhere (`goTo(0.1)`).
  property real deskX: 0.5
  signal wantsToGo(real fraction)
  function goTo(fraction) { wantsToGo(Math.max(0, Math.min(1, Number(fraction) || 0))) }
  // Things the pack puts on the desktop floor: [{ source, x (0..1), w, h }]
  // in grid units; Perch draws them at that spot on the bottom of the screen.
  // Optional: `id`, `mirror` (flip), `lift` (grid units up from the floor),
  // `front` (in front of her), `speed` (glides to a new x at that many grid
  // units a second, for things that move: a pet), `tap` (clickable: Perch
  // calls `propTapped(id)`). Keep the list the same length while it's shown,
  // so moving things glide instead of jumping.
  readonly property var desktopProps: character.item && Array.isArray(character.item.desktopProps) ? character.item.desktopProps : []
  signal propTapped(string id)
  // Weather on the desktop: a pack that knows it sets `weather` to "rain" or
  // "snow" and Perch lets it fall across the empty workspace.
  readonly property string weather: character.item && /^(rain|snow)$/.test(String(character.item.weather || "")) ? character.item.weather : ""
  // Focus timer (bar panel or `omarchy-shell jebin2.perch focus 25`): while
  // `focusing` she stays put and keeps quiet; `focusLeft` is in seconds.
  // `focusStarted` / `focusDone` fire at the ends.
  property bool focusing: false
  property int focusLeft: 0
  signal focusStarted(int minutes)
  // She came in from off screen (login, waking the laptop, back after a long
  // time away) and just landed: "login", "resume" or "back".
  signal welcomed(string kind)
  // Things she notices: "loud", "mute", "bright", "notify" (with the app's
  // name). A pack with `senses: true` reacts itself; others get a line.
  signal sensed(string kind, string app)
  readonly property bool packSenses: !!(character.item && character.item.senses)
  signal focusDone(int minutes)
  // Room a pack draws above its 64 x 80 box (hats, standing up to walk), in
  // grid units: her window keeps that much space above her.
  readonly property real headroom: character.item && Number(character.item.headroom) > 0
    ? Math.min(40, Number(character.item.headroom)) : 0

  // Walking along an edge to the next window (Perch moves her; a pack can
  // show a walk). `walkDir`: -1 left, 1 right.
  property bool walking: false
  property int walkDir: 1
  // A long way: she runs (Perch moves her faster).
  property bool running: false
  // Not level with the last window: she jumps there in an arc.
  property bool jumping: false

  // A speech bubble is showing.
  property bool talking: false

  // The last line she said: its kind (a lines.json section such as
  // "battery_low" or "window_closed", a time of day such as "morning", "app",
  // or "say") and mood ("serious", "fun", "sassy" or ""). `lineCount` goes up
  // with every line, so a pack can react to each one.
  property string topic: ""
  property string mood: ""
  property string line: ""
  property int lineCount: 0
  function heard(t, m, l) { topic = t || ""; mood = m || ""; line = l || ""; lineCount++ }

  // The focused window's class (e.g. "kitty", "spotify"), or "" when she
  // isn't on a window here.
  property string app: ""

  // A move asked for with `omarchy-shell jebin2.perch act <name>` that Perch
  // doesn't do itself (e.g. "cheer"): a pack can play it. `actionCount` goes
  // up every time, so a pack can react in `onActionCountChanged`.
  property string action: ""
  property int actionCount: 0
  function did(what) { action = what || ""; actionCount++ }

  // A message to hold up on a sign: `signCount` goes up with each, so a pack
  // with a sign reacts in `onSignCountChanged`.
  // What's going on around her (Perch sets these; packs can use them):
  // `meeting` the mic or camera is in use (she keeps quiet), `music` a music
  // player is playing, `movie` a video is playing, `windowTitle` of the
  // focused window.
  property bool meeting: false
  property bool music: false
  property bool movie: false
  property string windowTitle: ""

  // Picked up with the pointer: `dragging` while held; `dragOffset` how far
  // the pointer has moved since (Perch moves her). A double click is a high
  // five: `highFives` goes up.
  property bool dragging: false
  property point dragOffset: Qt.point(0, 0)
  signal dropped()
  property int highFives: 0

  property string signText: ""
  property int signCount: 0
  function showSign(t) { signText = t || ""; signCount++ }

  // A pack can make her say something (and show it on a sign): the line
  // goes through Perch like any other, so the quiet gap and Talk apply.
  signal wantsToSay(string line, string topic)
  function say(line, topic) { if (line) wantsToSay(String(line).slice(0, 160), topic || "pack") }

  // Thinking: during some calm spells she rests her chin on her hand.
  // 0..1; a pack that has the pose uses it, others ignore it.
  property real thinkAmt: 0
  Behavior on thinkAmt { NumberAnimation { duration: Style.duration(600); easing.type: Easing.InOutSine } }
  function think() {
    if (!motion || !shown || sleeping) return
    thinkAmt = 1
    thinkEnd.restart()
  }
  Timer { id: thinkEnd; interval: 6000; onTriggered: buddy.thinkAmt = 0 }

  // Each body part is drawn once into its own texture (at 2.5x, so it stays
  // sharp after scaling) and then only moved: redrawing ~40 shapes on every
  // frame cost about three times as much.
  readonly property bool cache: true
  readonly property real tex: 2.5

  width: 64 * s
  height: (80 + pad) * s

  // She fidgets in bursts: a few seconds of leg swinging, then a few calm
  // seconds of just breathing. Each redraw costs the shell about a
  // millisecond, so she updates 25 times a second while swinging and 10 while
  // calm or asleep; a free-running animation would redraw her at the
  // screen's full rate.
  property bool calm: false
  // On battery she sits still for longer between bursts.
  property bool thrifty: false
  Timer {
    interval: 8000
    repeat: true
    running: buddy.shown && buddy.motion && !buddy.sleeping
    onTriggered: {
      buddy.calm = !buddy.calm
      if (buddy.calm && Math.random() < 0.5) buddy.think()
      else if (!buddy.calm) { thinkEnd.stop(); buddy.thinkAmt = 0 }
      interval = buddy.calm
        ? (buddy.thrifty ? 10000 + Math.random() * 8000 : 4000 + Math.random() * 6000)
        : (buddy.thrifty ? 3000 + Math.random() * 3000 : 5000 + Math.random() * 7000)
    }
  }
  property real legEnergy: calm || sleeping ? 0 : 1
  Behavior on legEnergy { NumberAnimation { duration: Style.duration(700); easing.type: Easing.InOutSine } }
  readonly property bool lively: legEnergy > 0.02

  property real t: 0
  Timer {
    interval: buddy.lively ? 40 : 100
    repeat: true
    running: buddy.shown && buddy.motion
    onTriggered: buddy.t = (buddy.t + interval / 1000) % 12
  }

  // 1 when lively, 0 when asleep; legs and hair settle as she dozes off.
  property real energy: sleeping ? 0 : 1
  Behavior on energy { NumberAnimation { duration: Style.duration(900); easing.type: Easing.InOutSine } }
  readonly property real sleepAmt: 1 - energy

  // 0 at rest, 1 with her right arm up.
  property real waveAmt: 0
  readonly property bool happy: (waveAmt > 0.4 || patted) && !startled

  // Clicks on her: a pat. `pats` counts the clicks in a quick burst (1.2 s
  // apart at most), `patCount` goes up with every click, so a pack can react
  // in `onPatCountChanged`.
  property bool patted: false
  property int pats: 0
  property int patCount: 0
  function pat() {
    pats = patBurst.running ? pats + 1 : 1
    patCount++
    patBurst.restart()
    patted = true
    patEnd.restart()
  }
  Timer { id: patBurst; interval: 1200 }
  Timer { id: patEnd; interval: 900; onTriggered: buddy.patted = false }

  // The pointer touched her: a surprised face and a lean the way she goes.
  property bool startled: false
  property real lean: 0
  // Which way she scoots when startled: -1 left, 1 right.
  property int startleDir: 1
  signal poked(real x)

  function startle(dir) {
    thinkEnd.stop(); thinkAmt = 0
    waveAnim.stop(); waveAmt = 0
    startleDir = dir < 0 ? -1 : 1
    startled = true
    leanAnim.stop()
    leanAnim.dir = dir
    leanAnim.start()
    startleEnd.restart()
  }
  Timer { id: startleEnd; interval: 700; onTriggered: buddy.startled = false }
  SequentialAnimation {
    id: leanAnim
    property real dir: 1
    NumberAnimation { target: buddy; property: "lean"; to: 9 * leanAnim.dir; duration: Style.duration(120); easing.type: Easing.OutCubic }
    NumberAnimation { target: buddy; property: "lean"; to: 0; duration: Style.duration(380); easing.type: Easing.InOutSine }
  }

  // Yawn (just before a nap), stretch (waking up), fall (her window closed).
  property real yawnAmt: 0
  property real stretchAmt: 0
  property real fallT: 0
  readonly property bool falling: fallT > 0

  function yawn() {
    if (!motion || !shown || sleeping) return
    yawnAnim.restart()
  }
  function stretch() {
    thinkEnd.stop(); thinkAmt = 0
    if (!motion || !shown) { wave(); return }
    waveAnim.stop(); waveAmt = 0
    stretchAnim.restart()
  }
  function fall() {
    waveAnim.stop(); waveAmt = 0
    stretchAnim.stop(); stretchAmt = 0
    yawnAnim.stop(); yawnAmt = 0
    opacity = 1
    fallAnim.restart()
  }
  SequentialAnimation {
    id: yawnAnim
    NumberAnimation { target: buddy; property: "yawnAmt"; to: 1; duration: 450; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 1100 }
    NumberAnimation { target: buddy; property: "yawnAmt"; to: 0; duration: 450; easing.type: Easing.InOutSine }
  }
  SequentialAnimation {
    id: stretchAnim
    NumberAnimation { target: buddy; property: "stretchAmt"; to: 1; duration: 500; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 700 }
    NumberAnimation { target: buddy; property: "stretchAmt"; to: 0; duration: 350; easing.type: Easing.InOutSine }
    ScriptAction { script: buddy.wave() }
  }
  SequentialAnimation {
    id: fallAnim
    NumberAnimation { target: buddy; property: "fallT"; from: 0; to: 1; duration: 600; easing.type: Easing.Linear }
    PropertyAction { target: buddy; property: "opacity"; value: 0 }
    PropertyAction { target: buddy; property: "fallT"; value: 0 }
  }

  // One expression at a time.
  readonly property string face: (startled || falling) ? "startled"
    : yawnAmt > 0.4 ? "yawn"
    : (stretchAmt > 0.4 || happy) ? "happy"
    : sleepAmt >= 0.5 ? "sleep"
    : "normal"

  // Only her body takes the pointer; everything else in her window passes
  // through to what's below.
  readonly property alias hitBox: hitBox
  Item {
    id: hitBox
    x: 12 * buddy.s
    y: buddy.pad * buddy.s
    width: buddy.shown && !buddy.falling ? 40 * buddy.s : 0
    height: buddy.shown && !buddy.falling ? 74 * buddy.s : 0
    // The pointer resting on her for a moment makes her scoot out of the
    // way; a click before that is a pat, and she stays.
    HoverHandler {
      id: hover
      onHoveredChanged: {
        if (hovered) { pokeDelay.x = point.position.x + hitBox.x; pokeDelay.restart() }
        else pokeDelay.stop()
      }
    }
    TapHandler {
      onTapped: { pokeDelay.stop(); buddy.pat() }
      onDoubleTapped: { pokeDelay.stop(); buddy.highFives++ }
    }
    DragHandler {
      id: drag
      target: null
      onActiveChanged: {
        pokeDelay.stop()
        if (active) { buddy.dragOffset = Qt.point(0, 0); buddy.dragging = true }
        else { buddy.dragging = false; buddy.dropped() }
      }
      onCentroidChanged: if (active) buddy.dragOffset = Qt.point(
        centroid.scenePosition.x - centroid.scenePressPosition.x,
        centroid.scenePosition.y - centroid.scenePressPosition.y)
    }
    Timer {
      id: pokeDelay
      property real x: 0
      interval: 600   // time to grab her first
      onTriggered: if (hover.hovered && !buddy.dragging) buddy.poked(x)
    }
  }

  function wave() {
    if (!motion || sleeping) return
    waveAnim.restart()
  }

  function arrive() {
    appear.restart()
  }

  onSleepingChanged: {
    if (sleeping) { thinkEnd.stop(); thinkAmt = 0 }
    else if (shown) stretch()
  }

  // Fade in where she lands, then wave.
  opacity: 0
  scale: 0.96
  transformOrigin: Item.Bottom
  onShownChanged: {
    if (shown) appear.restart()
    else { appear.stop(); waveAnim.stop(); waveAmt = 0; hide.restart() }
  }
  SequentialAnimation {
    id: appear
    PropertyAction { target: buddy; property: "opacity"; value: 0 }
    PropertyAction { target: buddy; property: "scale"; value: 0.96 }
    ParallelAnimation {
      NumberAnimation { target: buddy; property: "opacity"; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
      NumberAnimation { target: buddy; property: "scale"; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
    }
    ScriptAction { script: buddy.wave() }
  }
  NumberAnimation { id: hide; target: buddy; property: "opacity"; to: 0; duration: Style.duration(120); easing.type: Easing.OutCubic }

  SequentialAnimation {
    id: waveAnim
    NumberAnimation { target: buddy; property: "waveAmt"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 1300 }
    NumberAnimation { target: buddy; property: "waveAmt"; to: 0; duration: 280; easing.type: Easing.InOutSine }
  }

  // Blinks now and then.
  property real eyeOpen: 1
  Timer {
    interval: 2600 + Math.random() * 2600
    repeat: true
    running: buddy.shown && buddy.motion && !buddy.sleeping
    onTriggered: { interval = 2600 + Math.random() * 2600; if (buddy.face === "normal") blink.restart() }
  }
  SequentialAnimation {
    id: blink
    NumberAnimation { target: buddy; property: "eyeOpen"; to: 0.1; duration: 70 }
    NumberAnimation { target: buddy; property: "eyeOpen"; to: 1; duration: 90 }
  }

  function wav(period, shift) { return Math.sin(tau * (t - (shift || 0)) / period) }

  readonly property real legL: 17 * legEnergy * wav(0.75)
  readonly property real legR: 17 * legEnergy * wav(0.75, 0.375)
  readonly property real headTilt: 2.2 * energy * wav(3) + 9 * sleepAmt
  readonly property real tailSwing: (5 * wav(3, 0.35) + 1.6 * legEnergy * wav(0.75, 0.1)) * energy + 4 * sleepAmt
  readonly property real ahogeSwing: 10 * energy * wav(1.5, 0.2) + 28 * sleepAmt
  readonly property real breathe: 1 + (0.012 + 0.01 * sleepAmt) * wav(3)
  readonly property real armR: waveAmt * (-112 + 16 * wav(0.5)) - 112 * stretchAmt - 55 * yawnAmt
  readonly property real armL: 112 * stretchAmt + 25 * yawnAmt
  readonly property real swing: hanging ? 2.4 * (0.35 + 0.65 * energy) * wav(3, 0.5) : 0

  Item {
    id: swingRoot
    width: buddy.width
    height: buddy.height
    transform: [
      Rotation { origin.x: 32 * buddy.s; origin.y: 0; angle: buddy.swing },
      Rotation { origin.x: 32 * buddy.s; origin.y: buddy.seatY; angle: buddy.lean },
      Rotation { origin.x: 32 * buddy.s; origin.y: buddy.height / 2; angle: buddy.packOwnsFall ? 0 : 40 * buddy.fallT },
      Translate { y: 90 * buddy.s * buddy.fallT * buddy.fallT }
    ]
    opacity: 1 - buddy.fallT * buddy.fallT

  Item {
    id: rig
    y: buddy.pad * buddy.s
    width: 64
    height: 80
    scale: buddy.s
    transformOrigin: Item.TopLeft

    // ---- Swing ropes, behind everything ---------------------------------
    Part {
      visible: buddy.hanging && !buddy.packOwnsSwing && !buddy.jumping
      fill: "transparent"; stroke: "#c8a27a"; strokeWidth: 1.1
      d: "M 19.1 -7 L 19.1 56.6 M 44.9 -7 L 44.9 56.6"
    }

    // ---- The character itself ------------------------------------------
    Loader {
      id: character
      width: 64
      height: 80
      // Hand the pack its `buddy` as it is created, so its bindings never
      // see an empty value.
      function load() { setSource(buddy.characterUrl, { buddy: buddy }) }
      Component.onCompleted: load()
      onStatusChanged: {
        if (status === Loader.Error && buddy.characterUrl !== buddy.defaultCharacterUrl) {
          console.warn("perch: character pack failed to load, using Mochi: " + buddy.characterUrl)
          buddy.characterUrl = buddy.defaultCharacterUrl
        }
      }
    }

    // ---- Zzz ----------------------------------------------------------
    Repeater {
      model: 3
      delegate: Text {
        required property int index
        readonly property real p: ((buddy.t / 2.4) + index / 3) % 1
        visible: buddy.face === "sleep"
        textFormat: Text.PlainText
        text: "z"
        x: 46 + p * 9 + index
        y: 16 - p * 15
        opacity: Math.sin(Math.PI * p)
        font.pixelSize: 10
        scale: (5 + p * 3.5) / 10
        font.bold: true
        color: "#9d8ee0"
        style: Text.Outline
        styleColor: "#2a2140"
      }
    }
  }
  }
}
