import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
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
  readonly property real size: 0.9          // 1.0 = a 64 x 80 px box
  readonly property int inset: 26           // gap between her and the window's right edge, px
  readonly property int sleepAfter: 90      // seconds without input before she naps
  readonly property int pollMs: 150

  property int borderSize: 2

  readonly property var active: Hyprland.activeToplevel
  readonly property string monitorName: active && active.monitor ? active.monitor.name : ""

  // The focused window, as Hyprland last reported it.
  property var info: null
  readonly property bool hasWindow: !!active && !!info && !!info.at && info.at.length === 2
    && !!info.size && info.size.length === 2 && info.size[0] > 0
    && info.mapped !== false && info.hidden !== true && !(Number(info.fullscreen) >= 2)

  readonly property real winX: hasWindow ? info.at[0] - borderSize : 0
  readonly property real winY: hasWindow ? info.at[1] - borderSize : 0
  readonly property real winW: hasWindow ? info.size[0] + 2 * borderSize : 0

  // Space kept clear at the top of the focused window's screen (the bar).
  readonly property var monitorInfo: active && active.monitor ? active.monitor.lastIpcObject : null
  readonly property real reservedTop: monitorInfo && monitorInfo.reserved && monitorInfo.reserved.length === 4
    ? Number(monitorInfo.reserved[1]) : 0

  readonly property bool sleeping: idle.isIdle

  // Each window arrival (focus moved to another window) makes her wave.
  property string lastAddress: ""
  signal arrived()

  onActiveChanged: {
    root.query()
    var address = active ? String(active.address) : ""
    if (address && address !== lastAddress) {
      lastAddress = address
      arrivalDelay.restart()
    }
  }

  // Let the new window's geometry land before she reappears.
  Timer {
    id: arrivalDelay
    interval: 60
    onTriggered: root.arrived()
  }

  Timer {
    interval: root.pollMs
    repeat: true
    running: !!root.active && !root.sleeping
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
      }
    }
    onConnectedChanged: {
      if (connected) {
        reply = ""
        write("j/activewindow")
        flush()
        return
      }
      // Hyprland closes the connection once it has answered.
      try {
        var parsed = JSON.parse(reply)
        root.info = parsed && typeof parsed === "object" ? parsed : null
      } catch (e) {}
      reply = ""
      if (root.queryAgain) { root.queryAgain = false; Qt.callLater(root.query) }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") { borderProc.running = true; Hyprland.refreshMonitors() }
      if (name === "monitoradded" || name === "monitorremoved") Hyprland.refreshMonitors()
      if (name === "fullscreen" || name === "changefloatingmode" || name === "movewindowv2"
          || name === "openwindow" || name === "closewindow" || name === "workspacev2")
        root.query()
    }
  }

  Component.onCompleted: Hyprland.refreshMonitors()

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
