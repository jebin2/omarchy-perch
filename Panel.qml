import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Perch's bar icon. Click for a panel to pick her character, change her
// size, hide her or keep her quiet, and make her do a move; right-click hides
// or shows her.
//
// The panel only reads ~/.config/perch/config.json; every change goes to the
// Perch service with `omarchy-shell jebin2.perch set …`, which writes it.
Panel {
  id: root
  moduleName: "jebin2.perch"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string home: Quickshell.env("HOME")
  readonly property var builtIn: ["mochi"]

  // Settings as saved (the service fills in the same defaults).
  property var config: ({})
  readonly property string character: validName(config.character) ? config.character : "mochi"
  readonly property real size: isFinite(Number(config.size)) && Number(config.size) > 0 ? Number(config.size) : 0.9
  readonly property bool shown: config.shown !== false
  readonly property bool talk: config.talk !== false

  // Built-in packs, then the user's own from ~/.config/perch/characters.
  property var userPacks: []
  readonly property var characters: {
    var list = builtIn.slice()
    for (var i = 0; i < userPacks.length; i++) if (list.indexOf(userPacks[i]) < 0) list.push(userPacks[i])
    if (list.indexOf(character) < 0) list.push(character)
    return list
  }

  function validName(v) { return typeof v === "string" && /^[A-Za-z0-9_-]{1,40}$/.test(v) }

  // "my-cat_pack" -> "My cat pack"
  function label(name) {
    var s = String(name).replace(/[-_]+/g, " ")
    return s.charAt(0).toUpperCase() + s.slice(1)
  }

  function set(key, value) {
    Quickshell.execDetached(["omarchy-shell", "jebin2.perch", "set", key, String(value)])
  }
  // Focus timer: the service keeps its end time in this file.
  property real focusEnd: 0
  property real clock: Date.now()
  readonly property int focusLeft: focusEnd > clock ? Math.ceil((focusEnd - clock) / 1000) : 0
  function runFocus(minutes) {
    Quickshell.execDetached(["omarchy-shell", "jebin2.perch", "focus", String(minutes)])
  }
  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/perch-focus"
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.focusEnd = Number(JSON.parse(text()).end) || 0 } catch (e) { root.focusEnd = 0 }; root.clock = Date.now() }
    onLoadFailed: root.focusEnd = 0
    onFileChanged: reload()
  }
  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.focusEnd > 0
    onTriggered: root.clock = Date.now()
  }

  function act(move) {
    Quickshell.execDetached(["omarchy-shell", "jebin2.perch", "act", move])
  }

  FileView {
    id: configFile
    path: root.home + "/.config/perch/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var c = {}
      try { c = JSON.parse(text()) } catch (e) {}
      root.config = c && typeof c === "object" && !Array.isArray(c) ? c : {}
    }
    onLoadFailed: root.config = {}
    onFileChanged: reload()
  }

  // List the user's packs: folders holding a Character.qml.
  Process {
    id: scan
    command: ["find", root.home + "/.config/perch/characters", "-mindepth", "2", "-maxdepth", "2", "-name", "Character.qml"]
    stdout: StdioCollector {
      onStreamFinished: {
        var names = []
        var lines = text.split("\n")
        for (var i = 0; i < lines.length && names.length < 50; i++) {
          var parts = lines[i].split("/")
          var name = parts.length >= 2 ? parts[parts.length - 2] : ""
          if (root.validName(name) && names.indexOf(name) < 0) names.push(name)
        }
        names.sort()
        root.userPacks = names
      }
    }
  }

  Component.onCompleted: scan.running = true
  onOpenedChanged: if (opened && !scan.running) scan.running = true

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    opacity: root.shown ? 1.0 : 0.45
    onPressed: function(b) {
      if (b === Qt.RightButton) root.set("shown", !root.shown)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          title: strings.t("title")
          meta: root.shown ? root.label(root.character) : strings.t("status.hidden")
          iconComponent: Text {
            textFormat: Text.PlainText
            text: ""
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        Toggle {
          width: parent.width
          label: strings.t("show.label")
          description: strings.t("show.description")
          checked: root.shown
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.set("shown", !root.shown)
        }

        Toggle {
          width: parent.width
          label: strings.t("talk.label")
          description: strings.t("talk.description")
          checked: root.talk
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.set("talk", !root.talk)
        }

        Dropdown {
          width: parent.width
          label: strings.t("character")
          fontFamily: root.bar.fontFamily
          options: root.characters.map(function(n) { return { value: n, label: root.label(n) } })
          value: root.character
          onChanged: function(v) { root.set("character", v) }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: strings.t("size").arg(Math.round(sizeSlider.liveValue * 100))
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          PanelSlider {
            id: sizeSlider
            width: parent.width
            bar: root.bar
            minimum: 0.5
            maximum: 2.0
            step: 0.05
            value: root.size
            onReleased: function(v) { root.set("size", v.toFixed(2)) }
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: root.focusLeft > 0
            ? strings.t("focus.left").arg(Math.floor(root.focusLeft / 60) + ":" + ("0" + root.focusLeft % 60).slice(-2))
            : strings.t("focus")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: root.focusLeft > 0 ? [0] : [25, 50, 90]
            delegate: Button {
              required property var modelData
              text: modelData > 0 ? strings.t("focus.minutes").arg(modelData) : strings.t("focus.stop")
              enabled: root.shown
              opacity: enabled ? 1.0 : 0.5
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.runFocus(modelData)
            }
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: strings.t("moves")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: [
              { move: "wave" },
              { move: "think" },
              { move: "yawn" },
              { move: "stretch" },
              { move: "fall" }
            ]
            delegate: Button {
              required property var modelData
              text: strings.t("move." + modelData.move)
              enabled: root.shown
              opacity: enabled ? 1.0 : 0.5
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.act(modelData.move)
            }
          }
        }
      }
    }
  }
}
