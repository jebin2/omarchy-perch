import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Perch's bar icon. Click for a panel to pick her character, change her
// size, hide her or keep her quiet, choose what she does with windows open
// and on an empty workspace, start a focus timer, pin or take down sticky
// notes, and make her do a move; right-click hides or shows her.
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

  // Per-view switches (same defaults as the service).
  readonly property var views: ({
    "winSky": false, "winSenses": true, "winBreaks": true,
    "deskShow": true, "deskFly": true, "deskAir": true, "deskGames": true, "deskNotes": true, "deskSenses": true, "deskClouds": true
  })
  function opt(key) { return config[key] === undefined ? views[key] : config[key] === true }
  readonly property string shots: config.shots === "hide" ? "hide" : "pose"
  readonly property string attitude: /^(sweet|some|lots|diva|loop)$/.test(config.attitude) ? config.attitude : "some"
  // In "loop", which one is on now (the same clock rule as the plugin).
  property real nowClock: Date.now()
  Timer { interval: 30000; running: root.attitude === "loop"; repeat: true; triggeredOnStart: true; onTriggered: root.nowClock = Date.now() }
  readonly property string attitudeNow: ["sweet", "some", "lots", "diva"][Math.floor(nowClock / 900000) % 4]
  property string view: "win"
  readonly property string winMove: /^(run|jump|fly)$/.test(String(config.winMove)) ? config.winMove : config.winFly === true ? "fly" : "run"
  readonly property var viewKeys: view === "win"
    ? ["winSky"]
    : ["deskShow", "deskClouds", "deskFly", "deskAir", "deskGames", "deskNotes"]

  // Sticky notes: the service keeps them in ~/.config/perch/notes.json.
  property var notes: []
  FileView {
    path: root.home + "/.config/perch/notes.json"
    watchChanges: true
    printErrors: false
    onLoaded: { try { var l = JSON.parse(text()); root.notes = Array.isArray(l) ? l : [] } catch (e) { root.notes = [] } }
    onLoadFailed: root.notes = []
    onFileChanged: reload()
  }
  // Moves her character adds (the service writes them when it loads her).
  property var packMoves: []
  property bool packFlies: false
  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/perch-moves.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var o = JSON.parse(text())
        root.packMoves = Array.isArray(o.moves) ? o.moves : []
        root.packFlies = o.flies === true
      } catch (e) { root.packMoves = []; root.packFlies = false }
    }
    onLoadFailed: { root.packMoves = []; root.packFlies = false }
    onFileChanged: reload()
  }
  readonly property var moves: {
    var l = ["wave", "think", "yawn", "stretch", "fall"].map(function(m) { return { id: m, label: strings.t("move." + m) } })
    if (packFlies) l.push({ id: "fly", label: strings.t("move.fly") })
    for (var i = 0; i < packMoves.length; i++) {
      var m = packMoves[i]
      if (m && /^[a-z][a-z0-9_-]{0,31}$/.test(String(m.id)) && !l.some(function(x) { return x.id === m.id }))
        l.push({ id: String(m.id), label: String(m.label || m.id).slice(0, 24) })
    }
    return l
  }
  function shell(args) { Quickshell.execDetached(["omarchy-shell", "jebin2.perch"].concat(args)) }

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
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(820))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Scrolls when the screen is too short for all of it.
      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

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

        // How sassy she is.
        Column {
          width: parent.width
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: strings.t("attitude") + (root.attitude === "loop" ? " · " + strings.t("attitude.now") + " " + strings.t("attitude." + root.attitudeNow) : "")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          ButtonGroup {
            width: parent.width
            options: [{ value: "sweet", label: strings.t("attitude.sweet") }, { value: "some", label: strings.t("attitude.some") },
                      { value: "lots", label: strings.t("attitude.lots") }, { value: "diva", label: strings.t("attitude.diva") },
                      { value: "loop", label: strings.t("attitude.loop") }]
            value: root.attitude
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onChanged: function(v) { root.set("attitude", v) }
          }
        }

        // Screenshots taken with a key bound to the `shot` command.
        Column {
          width: parent.width
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: strings.t("shots")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          ButtonGroup {
            width: parent.width
            options: [{ value: "pose", label: strings.t("shots.pose") }, { value: "hide", label: strings.t("shots.hide") }]
            value: root.shots
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onChanged: function(v) { root.set("shots", v) }
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: strings.t("views")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        ButtonGroup {
          width: parent.width
          options: [{ value: "win", label: strings.t("view.win") }, { value: "desk", label: strings.t("view.desk") }]
          value: root.view
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onChanged: function(v) { root.view = v }
        }

        // With windows: how she gets to the next one.
        Column {
          visible: root.view === "win"
          width: parent.width
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: strings.t("winMove")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          ButtonGroup {
            width: parent.width
            options: [{ value: "run", label: strings.t("winMove.run") }, { value: "jump", label: strings.t("winMove.jump") }, { value: "fly", label: strings.t("winMove.fly") }]
            value: root.winMove
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onChanged: function(v) { root.set("winMove", v) }
          }
        }

        Repeater {
          model: root.viewKeys
          delegate: Toggle {
            required property string modelData
            width: column.width
            label: strings.t("opt." + modelData)
            description: strings.t("opt." + modelData + ".description")
            checked: root.opt(modelData)
            enabled: root.shown && (modelData === "deskShow" || modelData.indexOf("desk") !== 0 || root.opt("deskShow") || modelData === "deskNotes")
            opacity: enabled ? 1.0 : 0.5
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.set(modelData, !root.opt(modelData))
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
          text: root.notes.length > 0 ? strings.t("notes.count").arg(root.notes.length) : strings.t("notes")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Repeater {
          model: root.notes.slice(0, 8)
          delegate: Item {
            required property var modelData
            required property int index
            width: column.width
            height: Math.max(noteText.implicitHeight, noteDone.implicitHeight)
            Text {
              id: noteText
              anchors.left: parent.left
              anchors.right: noteDone.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "\uD83D\uDCDD " + modelData.text + (Number(modelData.due) > 0 ? "  \u00B7 " + Qt.formatTime(new Date(Number(modelData.due)), "h:mm AP") : "")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Button {
              id: noteDone
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "\u2715"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.shell(["unnote", String(index + 1)])
            }
          }
        }

        TextField {
          id: noteInput
          width: parent.width
          placeholderText: strings.t("notes.placeholder")
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily
          maximumLength: 140
          onAccepted: {
            var t = text.trim()
            if (t) root.shell(["note", t])
            text = ""
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
            model: root.moves
            delegate: Button {
              required property var modelData
              text: modelData.label
              enabled: root.shown
              opacity: enabled ? 1.0 : 0.5
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.act(modelData.id)
            }
          }
        }
      }
      }
    }
  }
}
