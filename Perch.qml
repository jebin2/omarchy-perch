import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons

// Perch: Mochi sits on the top-right corner of the focused window.
//
// One small click-through layer window per screen; only the screen that holds
// the focused window shows her. Hyprland sends no events while a window is
// dragged or resized, so while she is awake the focused window's geometry is
// asked for a few times a second, straight from Hyprland's socket
// (`j/activewindow`, one small reply). Re-reading the whole window list would
// make every other part of the shell that watches it redo its work too.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // Tunables.
  // Size, visibility, talking and the character are settings: they live in
  // ~/.config/perch/config.json (see "Settings" below) and the bar icon's
  // panel changes them.
  property real size: 0.9                   // 1.0 = a 64 x 80 px box
  readonly property int inset: 26           // gap between her and the window's right edge, px
  readonly property int sleepAfter: 90      // seconds without input before she naps
  readonly property int pollMs: 150

  property int borderSize: 2

  // Focus changes come from Quickshell; the focused window itself (geometry,
  // monitor, address) always comes from our own query, which also works
  // right after the shell starts, before Quickshell knows the active window.
  readonly property var active: Hyprland.activeToplevel
  readonly property var monitor: {
    var id = info ? Number(info.monitor) : -1
    var list = Hyprland.monitors.values
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }
  readonly property string monitorName: monitor ? monitor.name : ""

  // The focused window, as Hyprland last reported it.
  property var info: null
  readonly property bool hasWindow: shown && !!info && !!info.at && info.at.length === 2
    && !!info.size && info.size.length === 2 && info.size[0] > 0
    && info.mapped !== false && info.hidden !== true && !(Number(info.fullscreen) >= 2)

  readonly property real winX: hasWindow ? info.at[0] - borderSize : 0
  readonly property real winY: hasWindow ? info.at[1] - borderSize : 0
  readonly property real winW: hasWindow ? info.size[0] + 2 * borderSize : 0

  // Space kept clear at the top of the focused window's screen (the bar).
  readonly property var monitorInfo: monitor ? monitor.lastIpcObject : null
  readonly property real reservedTop: monitorInfo && monitorInfo.reserved && monitorInfo.reserved.length === 4
    ? Number(monitorInfo.reserved[1]) : 0

  readonly property bool sleeping: idle.isIdle

  // Each window arrival (focus moved to another window) makes her wave.
  // `leaving` fires just before she moves, `fell` when the window she was
  // on closed (current: the one she is on now; otherwise the one before).
  signal arrived()
  signal leaving()
  signal fell(bool current)
  signal say(string line)
  signal act(string what)

  property string lastAddress: ""
  property string prevAddress: ""
  property double prevAddressAt: 0
  property bool fallPending: false

  function normAddress(a) { return String(a || "").replace(/^0x/, "").toLowerCase() }

  onActiveChanged: root.query()

  // A reply about a different window than before: she moves there.
  function noteWindow(obj) {
    var address = obj ? normAddress(obj.address) : ""
    if (address && address !== lastAddress) {
      root.leaving()
      prevAddress = lastAddress
      prevAddressAt = Date.now()
      lastAddress = address
      arrivalDelay.interval = fallPending ? 700 : 60
      arrivalDelay.restart()
    }
    root.info = obj
  }

  // Let the new window's geometry land before she reappears.
  Timer {
    id: arrivalDelay
    interval: 60
    onTriggered: { root.fallPending = false; root.arrived() }
  }

  function windowClosed(address) {
    var a = normAddress(address)
    if (!a) return
    var current = a === lastAddress
    var previous = a === prevAddress && Date.now() - prevAddressAt < 1500
    if (!current && !previous) return
    fallPending = true
    pendingLine = pickLine(lines.window_closed)
    root.fell(current)
    arrivalDelay.interval = 700
    arrivalDelay.restart()
  }

  // ---- Character --------------------------------------------------------
  //
  // ~/.config/perch/config.json: { "character": "<name>" }. A name shipped
  // with the plugin (characters/<name>/) wins; otherwise the pack is read from
  // ~/.config/perch/characters/<name>/Character.qml, so private characters
  // never live inside the plugin folder. Switching takes effect on save.

  readonly property var builtInCharacters: ["mochi"]
  property string characterName: "mochi"
  readonly property string characterUrl: {
    var name = characterName
    if (builtInCharacters.indexOf(name) >= 0) return Qt.resolvedUrl("characters/" + name + "/Character.qml")
    return "file://" + home + "/.config/perch/characters/" + name + "/Character.qml"
  }

  // ---- Settings --------------------------------------------------------
  //
  // ~/.config/perch/config.json, all optional:
  //   { "character": "mochi", "size": 0.9, "shown": true, "talk": true }
  // Read on every save; the bar panel writes it through the `set` command.

  readonly property real minSize: 0.5
  readonly property real maxSize: 1.6
  property bool shown: true
  onShownChanged: if (shown) query()
  property var config: ({})

  FileView {
    id: configFile
    path: root.home + "/.config/perch/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig()
    onLoadFailed: { root.config = {}; root.applyConfig() }
    onFileChanged: reload()
  }

  function loadConfig() {
    var parsed = {}
    try { parsed = JSON.parse(configFile.text()) } catch (e) {}
    config = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    applyConfig()
  }

  function validName(v) { return typeof v === "string" && /^[A-Za-z0-9_-]{1,40}$/.test(v) }

  function applyConfig() {
    var c = config
    characterName = validName(c.character) ? c.character : "mochi"
    var z = Number(c.size)
    size = isFinite(z) && z > 0 ? Math.max(minSize, Math.min(maxSize, z)) : 0.9
    shown = c.shown !== false
    talk = c.talk !== false
  }

  function setOption(key, value) {
    var c = {}
    for (var k in config) c[k] = config[k]
    if (key === "character" && validName(value)) c.character = value
    else if (key === "size" && isFinite(Number(value))) c.size = Math.round(Math.max(minSize, Math.min(maxSize, Number(value))) * 100) / 100
    else if (key === "shown" || key === "talk") c[key] = value === true || value === "true"
    else return
    config = c
    applyConfig()
    configFile.setText(JSON.stringify(c, null, 2) + "\n")
  }

  // ---- Talk -----------------------------------------------------------
  //
  // Lines come from lines.json next to this file; ~/.config/perch/lines.json
  // can replace any of its sections. Each entry is a list, or lists keyed by
  // mood. Ordinary lines keep a quiet gap between them; event lines (battery,
  // a closed window, a break reminder, waking up) skip it.

  property bool talk: true
  readonly property var moods: ["serious", "fun", "sassy"]
  readonly property int quietGapSec: 45       // at least this long between ordinary lines
  readonly property int chatterEverySec: 360  // a random line roughly this often (+-30%)
  readonly property real appChance: 0.35      // chance of an app line on a focus change
  readonly property int breakAfterMin: 60     // break reminder after this much active time

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")

  property var lines: ({})
  property double lastSaid: 0
  property string pendingLine: ""
  property bool greetPending: true
  property bool settled: false   // a few seconds after start, so startup changes stay quiet

  Timer { interval: 8000; running: true; onTriggered: root.settled = true }

  function parseLines(view) {
    try {
      var parsed = JSON.parse(view.text())
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    } catch (e) {
      return {}
    }
  }

  function loadLines() {
    var base = parseLines(defaultLines)
    var mine = parseLines(userLines)
    var merged = Object.assign({}, base, mine)
    if (base.app && mine.app && typeof mine.app === "object") merged.app = Object.assign({}, base.app, mine.app)
    lines = merged
  }

  FileView {
    id: defaultLines
    path: root.pluginDir + "/lines.json"
    watchChanges: true
    onLoaded: root.loadLines()
    onFileChanged: reload()
  }

  FileView {
    id: userLines
    path: root.home + "/.config/perch/lines.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadLines()
    onLoadFailed: root.loadLines()
    onFileChanged: reload()
  }

  function pickLine(entry) {
    var pool = []
    function add(list) {
      if (!Array.isArray(list)) return
      for (var i = 0; i < list.length && i < 500; i++) {
        if (typeof list[i] === "string" && list[i].length > 0 && list[i].length <= 160) pool.push(list[i])
      }
    }
    if (Array.isArray(entry)) add(entry)
    else if (entry && typeof entry === "object") {
      for (var m = 0; m < moods.length; m++) add(entry[moods[m]])
    }
    return pool.length ? pool[Math.floor(Math.random() * pool.length)] : ""
  }

  function speakLine(line, force) {
    if (!talk || !line || sleeping || !hasWindow || fallPending) return false
    var now = Date.now()
    if (now - lastSaid < (force ? 5000 : quietGapSec * 1000)) return false
    lastSaid = now
    root.say(line)
    return true
  }

  function speak(entry, force) { return speakLine(pickLine(entry), force) }

  function timeEntry() {
    var h = new Date().getHours()
    var key = h < 2 ? "night" : h < 5 ? "latenight" : h < 11 ? "morning" : h < 14 ? "noon"
      : h < 18 ? "afternoon" : h < 22 ? "evening" : "night"
    return lines.time ? lines.time[key] : null
  }

  function appEntry() {
    var cls = info && typeof info.class === "string" ? info.class : ""
    if (!cls || !lines.app) return null
    for (var key in lines.app) {
      if (key.length > 200) continue
      try {
        if (new RegExp(key, "i").test(cls)) return lines.app[key]
      } catch (e) {}
    }
    return null
  }

  // After she lands on a window: a line she was holding (she just fell), a
  // greeting the first time, or now and then something about the app.
  onArrived: talkAfterArrival.restart()
  Timer {
    id: talkAfterArrival
    interval: 450
    onTriggered: {
      if (root.pendingLine) {
        var held = root.pendingLine
        root.pendingLine = ""
        root.speakLine(held, true)
      } else if (root.greetPending) {
        if (root.speak(root.timeEntry(), true)) root.greetPending = false
      } else if (Math.random() < root.appChance) {
        root.speak(root.appEntry(), false)
      }
    }
  }

  Timer {
    id: chatter
    interval: root.chatterEverySec * 1000
    repeat: true
    running: root.talk && root.hasWindow && !root.sleeping
    onTriggered: {
      interval = root.chatterEverySec * 1000 * (0.7 + Math.random() * 0.6)
      root.speak(Math.random() < 0.35 ? root.timeEntry() : root.lines.chatter, false)
    }
  }

  // A yawn a few seconds before she nods off.
  IdleMonitor {
    id: drowsy
    timeout: Math.max(5, root.sleepAfter - 6)
    respectInhibitors: true
    onIsIdleChanged: {
      if (!isIdle || root.sleeping) return
      root.act("yawn")
      if (Math.random() < 0.5) root.speak(root.lines.yawn, true)
    }
  }

  // Waking up: she stretches (Buddy does that on her own), then says hi, or
  // greets by time of day after a long nap.
  property double sleptAt: 0
  onSleepingChanged: {
    if (sleeping) { sleptAt = Date.now(); return }
    var napped = sleptAt ? Date.now() - sleptAt : 0
    if (napped > 5 * 60 * 1000) activeMinutes = 0
    wakeTalk.entry = napped > 20 * 60 * 1000 ? timeEntry() : lines.wake
    wakeTalk.restart()
  }
  Timer {
    id: wakeTalk
    property var entry: null
    interval: 1300
    onTriggered: root.speak(entry, true)
  }

  // Break reminder after a stretch of active time.
  property int activeMinutes: 0
  Timer {
    interval: 60000
    repeat: true
    running: !root.sleeping
    onTriggered: {
      root.activeMinutes++
      if (root.activeMinutes >= root.breakAfterMin && root.speak(root.lines["break"], true)) root.activeMinutes = 0
    }
  }

  // Battery and charger. This laptop's charger state can flicker, so a change
  // only counts once it has held for 5 s.
  readonly property var battery: UPower.displayDevice
  readonly property bool onBattery: UPower.onBattery
  property bool lowWarned: false
  property bool lastOnBattery: false

  function checkBattery() {
    if (!battery || !battery.isLaptopBattery) return
    var p = battery.percentage
    if (UPower.onBattery && p > 0 && p <= 0.15) {
      if (!lowWarned && speak(lines.battery_low, true)) lowWarned = true
    } else if (p > 0.2 || !UPower.onBattery) {
      lowWarned = false
    }
  }

  Connections {
    target: root.battery
    function onPercentageChanged() { root.checkBattery() }
  }
  Connections {
    target: UPower
    function onOnBatteryChanged() { powerSettle.restart() }
  }
  Timer {
    id: powerSettle
    interval: 5000
    onTriggered: {
      var now = UPower.onBattery
      if (now === root.lastOnBattery) return
      root.lastOnBattery = now
      if (root.settled) root.speak(now ? root.lines.unplugged : root.lines.charging, true)
      root.checkBattery()
    }
  }

  // A new theme means a new hoodie color.
  Connections {
    target: Color
    function onAccentChanged() { if (root.settled) themeSettle.restart() }
  }
  Timer { id: themeSettle; interval: 1500; onTriggered: root.speak(root.lines.theme, true) }

  Timer {
    interval: root.pollMs
    repeat: true
    running: !root.sleeping && root.shown
    onTriggered: root.query()
  }

  property bool queryAgain: false
  function query() {
    if (hyprSocket.connected) { queryAgain = true; return }
    hyprSocket.connected = true
  }

  Socket {
    id: hyprSocket
    property string reply: ""
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"
    parser: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        if (hyprSocket.reply.length < 65536) hyprSocket.reply += data
        // Hang up as soon as the whole answer is in, before Hyprland does:
        // a peer hang-up is logged as a socket error every time.
        if (root.takeReply(hyprSocket.reply)) {
          hyprSocket.reply = ""
          hyprSocket.connected = false
        }
      }
    }
    onConnectedChanged: {
      if (connected) {
        reply = ""
        write("j/activewindow")
        flush()
        return
      }
      if (reply) root.takeReply(reply)
      reply = ""
      if (root.queryAgain) { root.queryAgain = false; Qt.callLater(root.query) }
    }
  }

  // True once `text` is a complete JSON answer; stores it.
  function takeReply(text) {
    try {
      var parsed = JSON.parse(text)
      root.noteWindow(parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null)
      return true
    } catch (e) {
      return false
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") { borderProc.running = true; Hyprland.refreshMonitors() }
      if (name === "monitoradded" || name === "monitorremoved") Hyprland.refreshMonitors()
      if (name === "closewindow") root.windowClosed(String(event.data || "").split(",")[0])
      if (name === "fullscreen" || name === "changefloatingmode" || name === "movewindowv2"
          || name === "openwindow" || name === "closewindow" || name === "workspacev2")
        root.query()
    }
  }

  Component.onCompleted: { Hyprland.refreshMonitors(); lastOnBattery = UPower.onBattery; query() }

  IdleMonitor {
    id: idle
    timeout: root.sleepAfter
    // A playing video holds an idle inhibitor: she stays up and watches too.
    respectInhibitors: true
  }

  // The border sits outside the window's reported geometry; she sits on it.
  Process {
    id: borderProc
    command: ["hyprctl", "getoption", "general:border_size", "-j"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var value = Number(JSON.parse(text).int)
          if (value >= 0 && value <= 50) root.borderSize = value
        } catch (e) {}
      }
    }
  }

  // `omarchy-shell jebin2.perch say "text"` makes her say something;
  // `omarchy-shell jebin2.perch act wave|yawn|stretch|think|fall` plays a move.
  ShellIpc {
    target: "jebin2.perch"

    function say(text: string): void {
      var line = String(text || "").trim().slice(0, 160)
      if (line) root.speakLine(line, true)
    }

    function act(what: string): void {
      var move = String(what || "")
      if (move === "fall") { root.fallPending = true; root.fell(true); arrivalDelay.interval = 700; arrivalDelay.restart() }
      else if (["wave", "yawn", "stretch", "think"].indexOf(move) >= 0) root.act(move)
    }

    // character <name> | size <0.5..1.6> | shown true/false | talk true/false
    function set(key: string, value: string): void {
      root.setOption(String(key || ""), String(value || ""))
    }

    function toggle(): void { root.setOption("shown", root.shown ? "false" : "true") }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PerchWindow {
        required property var modelData
        screen: modelData
        perch: root
      }
    }
  }
}
