import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
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
  // `topic` is the kind of line (a lines.json section such as "battery_low",
  // a time of day such as "morning", "app", or "say" for the IPC command)
  // and `mood` the mood it was picked from, so a character pack can react.
  signal say(string line, string topic, string mood)
  signal act(string what)
  // A message to hold up on a sign (a pack that has one shows it).
  signal showSign(string text)

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
    pendingMood = pickedMood
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
  readonly property real maxSize: 2.0
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
  property string pendingMood: ""
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

  // The mood of the line pickLine() returned last ("" for a plain list).
  property string pickedMood: ""
  function pickLine(entry) {
    var pool = [], from = []
    function add(list, mood) {
      if (!Array.isArray(list)) return
      for (var i = 0; i < list.length && i < 500; i++) {
        if (typeof list[i] === "string" && list[i].length > 0 && list[i].length <= 160) { pool.push(list[i]); from.push(mood) }
      }
    }
    if (Array.isArray(entry)) add(entry, "")
    else if (entry && typeof entry === "object") {
      for (var m = 0; m < moods.length; m++) add(entry[moods[m]], moods[m])
    }
    if (!pool.length) { pickedMood = ""; return "" }
    var k = Math.floor(Math.random() * pool.length)
    pickedMood = from[k]
    return pool[k]
  }

  function speakLine(line, force, topic, mood) {
    if (!talk || !line || sleeping || !hasWindow || fallPending || meeting) return false
    var now = Date.now()
    if (now - lastSaid < (force ? 5000 : quietGapSec * 1000)) return false
    lastSaid = now
    root.say(line, topic || "", mood || "")
    return true
  }

  function speak(entry, force, topic) {
    var line = pickLine(entry)
    return speakLine(line, force, topic, pickedMood)
  }

  function timeKey() {
    var h = new Date().getHours()
    return h < 2 ? "night" : h < 5 ? "latenight" : h < 11 ? "morning" : h < 14 ? "noon"
      : h < 18 ? "afternoon" : h < 22 ? "evening" : "night"
  }
  function timeEntry() { return lines.time ? lines.time[timeKey()] : null }

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
        root.speakLine(held, true, "window_closed", root.pendingMood)
      } else if (root.greetPending) {
        if (root.speak(root.timeEntry(), true, root.timeKey())) root.greetPending = false
      } else if (Math.random() < root.appChance) {
        root.speak(root.appEntry(), false, "app")
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
      if (Math.random() < 0.35) root.speak(root.timeEntry(), false, root.timeKey())
      else root.speak(root.lines.chatter, false, "chatter")
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
      if (Math.random() < 0.5) root.speak(root.lines.yawn, true, "yawn")
    }
  }

  // Waking up: she stretches (Buddy does that on her own), then says hi, or
  // greets by time of day after a long nap.
  property double sleptAt: 0
  onSleepingChanged: {
    if (sleeping) { sleptAt = Date.now(); return }
    var napped = sleptAt ? Date.now() - sleptAt : 0
    if (napped > 5 * 60 * 1000) activeMinutes = 0
    var longNap = napped > 20 * 60 * 1000
    wakeTalk.entry = longNap ? timeEntry() : lines.wake
    wakeTalk.topic = longNap ? timeKey() : "wake"
    wakeTalk.restart()
  }
  Timer {
    id: wakeTalk
    property var entry: null
    property string topic: ""
    interval: 1300
    onTriggered: root.speak(entry, true, topic)
  }

  // Break reminder after a stretch of active time.
  property int activeMinutes: 0
  Timer {
    interval: 60000
    repeat: true
    running: !root.sleeping
    onTriggered: {
      root.activeMinutes++
      if (root.activeMinutes < root.breakAfterMin || !root.talk || !root.hasWindow || root.meeting) return
      // She stretches, then holds the reminder up (or says it).
      root.activeMinutes = 0
      root.act("stretch")
      breakSign.restart()
    }
  }

  Timer {
    id: breakSign
    interval: 2400
    onTriggered: { var l = root.pickLine(root.lines["break"]); if (l) root.showSign(l) }
  }

  // ---- Reminders: `omarchy reminder 30 "Pickup Jack"` ------------------------
  // Omarchy keeps a reminder's text in a file until it goes off, then deletes
  // it. A file that disappears around its due time (its name holds the
  // minutes and when it was set) has just gone off: she holds it up.
  readonly property string reminderDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-reminders"
  property var reminders: ({})
  Process {
    id: reminderDirProc
    command: ["mkdir", "-p", root.reminderDir]
    running: true
    onExited: reminderFiles.folder = "file://" + root.reminderDir
  }
  FolderListModel {
    id: reminderFiles
    nameFilters: ["*.message"]
    showDirs: false
    onCountChanged: reminderRead.running = true
    onStatusChanged: if (status === FolderListModel.Ready) reminderRead.running = true
  }
  Process {
    id: reminderRead
    command: ["sh", "-c", "for f in \"$1\"/*.message; do [ -f \"$f\" ] && printf '%s\\t%s\\n' \"${f##*/}\" \"$(tr '\\n\\t' '  ' < \"$f\")\"; done", "sh", root.reminderDir]
    stdout: StdioCollector {
      onStreamFinished: {
        var now = {}, old = root.reminders
        text.split("\n").forEach(function(l) {
          var i = l.indexOf("\t")
          if (i > 0) now[l.slice(0, i)] = l.slice(i + 1).trim()
        })
        for (var name in old) {
          if (now[name] !== undefined) continue
          var m = /-(\d+)m-(\d+)\.message$/.exec(name)
          if (m && Math.abs(Date.now() / 1000 - (Number(m[2]) + Number(m[1]) * 60)) < 120 && old[name])
            root.showSign(old[name].slice(0, 80))
        }
        root.reminders = now
      }
    }
  }

  // ---- Meetings: the mic (not a level meter) or the camera in use ------------
  // She stays quiet (no lines, no songs) until it's free again. Two busy
  // checks in a row count, so a quick dictation doesn't.
  property bool meeting: false
  property int busyChecks: 0
  Process {
    id: busyProc
    command: ["sh", "-c", "m=\" $(pactl list short sources 2>/dev/null | awk '/\\.monitor/{print $1}' | tr '\\n' ' ') \"; pactl list short source-outputs 2>/dev/null | awk -v m=\"$m\" 'index(m, \" \" $2 \" \") == 0' | wc -l; fuser /dev/video* 2>/dev/null | wc -w"]
    stdout: StdioCollector {
      onStreamFinished: {
        var n = text.trim().split(/\s+/).map(Number)
        var busy = (n[0] || 0) + (n[1] || 0) > 0
        root.busyChecks = busy ? root.busyChecks + 1 : 0
        root.meeting = root.busyChecks >= 2
      }
    }
  }
  Timer { interval: 15000; repeat: true; running: true; triggeredOnStart: true; onTriggered: busyProc.running = true }

  // ---- Now playing ----------------------------------------------------------
  // A music player (not a browser or a video player): a new song goes on her
  // sign, at most every 2 minutes. A video player, or a browser on a video
  // site, is a movie: packs can grab some popcorn.
  readonly property var player: {
    var ps = Mpris.players.values
    for (var i = 0; i < ps.length; i++) if (ps[i] && ps[i].isPlaying) return ps[i]
    return null
  }
  function kindOf(p) {
    if (!p) return ""
    var id = String((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase()
    if (/mpv|vlc|celluloid|totem|haruna|kodi|jellyfin|stremio|plex|showtime/.test(id)) return "video"
    if (/firefox|chrom|brave|vivaldi|edge|zen|librewolf|opera|helium/.test(id)) return "browser"
    return "music"
  }
  readonly property string playing: kindOf(player)
  readonly property string windowTitle: info && typeof info.title === "string" ? info.title : ""
  readonly property bool music: playing === "music"
  readonly property bool movie: playing === "video"
    || playing === "browser" && /netflix|prime video|disney|hotstar|jiocinema|youtube|zee5|sonyliv|mubi|crunchyroll|hulu|max\b/i.test(windowTitle)
  readonly property string song: music && player.trackTitle
    ? "\u266a " + player.trackTitle + (player.trackArtist ? " \u2013 " + player.trackArtist : "") : ""
  property real lastSong: 0
  onSongChanged: {
    if (!song || !talk || meeting || !hasWindow || sleeping) return
    if (Date.now() - lastSong < 120000) return
    lastSong = Date.now()
    showSign(song.slice(0, 80))
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
      if (!lowWarned && speak(lines.battery_low, true, "battery_low")) lowWarned = true
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
      if (root.settled) root.speak(now ? root.lines.unplugged : root.lines.charging, true, now ? "unplugged" : "charging")
      root.checkBattery()
    }
  }

  // A new theme means a new hoodie color.
  Connections {
    target: Color
    function onAccentChanged() { if (root.settled) themeSettle.restart() }
  }
  Timer { id: themeSettle; interval: 1500; onTriggered: root.speak(root.lines.theme, true, "theme") }

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
  // `omarchy-shell jebin2.perch act wave|yawn|stretch|think|fall` plays a move;
  // other names (e.g. `act cheer`) go to the character pack.
  ShellIpc {
    target: "jebin2.perch"

    function say(text: string): void {
      var line = String(text || "").trim().slice(0, 160)
      if (line) root.speakLine(line, true, "say", "")
    }

    // `omarchy-shell jebin2.perch sign "text"`: she holds the text up on a
    // sign if her pack has one, otherwise she says it.
    function sign(text: string): void {
      var line = String(text || "").trim().slice(0, 80)
      if (!line) return
      root.showSign(line)
    }

    function act(what: string): void {
      var move = String(what || "")
      if (move === "fall") { root.fallPending = true; root.fell(true); arrivalDelay.interval = 700; arrivalDelay.restart() }
      else if (/^[a-z][a-z0-9_-]{0,31}$/.test(move)) root.act(move)
    }

    // character <name> | size <0.5..2.0> | shown true/false | talk true/false
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
