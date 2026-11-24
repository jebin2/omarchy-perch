import QtQuick
import QtQuick.Shapes
import qs.Commons

// A puffy comic cloud to her left, little puffs trailing to her.
// Three moods, picked from the line: "say", "shout" (warm yellow, thicker
// ink, shakes) and "think". It pops in with a springy
// overshoot, types its text out, bobs while it's up and floats off.
// `active` is true from the moment it starts showing until it has gone.
Item {
  id: bubble

  property real maxWidth: 210
  property bool active: false
  property string text: ""
  property string tone: "say"
  // Bigger with a bigger her (drawn at this scale; the shapes stay sharp).
  property real zoom: 1

  FontLoader { id: comic; source: "fonts/ComicNeue-Bold.ttf" }

  readonly property bool shout: tone === "shout"
  readonly property bool think: tone === "think"
  readonly property real tail: 17     // room on the right for the tail or puffs
  // The text box, then the oval around it (its corners just inside).
  // A rounder block of text: longer lines wrap into a few short ones.
  readonly property real textWidth: Math.min((maxWidth - tail - 2 * margin - 12) / 1.3, metrics.advanceWidth + 1,
    Math.max(64, Math.sqrt(metrics.advanceWidth * metrics.height * 2.6)))
  readonly property real textHeight: sizer.implicitHeight
  readonly property real ra: textWidth / 2 * (shout ? 1.24 : 1.18) + 4
  readonly property real rb: textHeight / 2 * (shout ? 1.42 : 1.32) + 4
  readonly property real margin: 10   // room for the cloud's puffs
  readonly property real cx: margin + ra
  readonly property real cy: margin + rb

  readonly property real baseWidth: 2 * (margin + ra) + tail
  readonly property real baseHeight: 2 * (margin + rb) + 6
  width: baseWidth * zoom
  height: baseHeight * zoom

  // ---- Which look ---------------------------------------------------------
  function toneOf(line, topic) {
    var t = String(topic || "")
    if (/^(hmm|\.\.\.|…)/i.test(line) || t === "think") return "think"
    if (t === "loud" || /!{2,}/.test(line) || /\b[A-Z]{3,}\b/.test(line)) return "shout"
    return "say"
  }

  // ---- Shapes (SVG paths, in the balloon's own coordinates) ----------------
  function n(v) { return v.toFixed(1) }
  function pt(th, k) { return n(cx + ra * (k || 1) * Math.cos(th)) + " " + n(cy + rb * (k || 1) * Math.sin(th)) }
  // An oval with a curved, pointed tail flowing out of its lower right.
  function balloon() {
    var t1 = 0.22, t2 = 0.78, tip = n(cx + ra + tail - 3) + " " + n(cy + rb * 0.82)
    return "M " + pt(t2) + " A " + n(ra) + " " + n(rb) + " 0 1 1 " + pt(t1)
      + " Q " + n(cx + ra + tail * 0.2) + " " + n(cy + rb * 0.38) + " " + tip
      + " Q " + n(cx + ra * 0.86) + " " + n(cy + rb * 0.86) + " " + pt(t2) + " Z"
  }
  // A burst: spikes all round the oval, one long one toward her.
  function burst() {
    var k = Math.max(14, Math.round((ra + rb) / 7)), p = ""
    for (var i = 0; i < 2 * k; i++) {
      var ang = Math.PI * i / k, out = i % 2 === 0
      var f = out ? 1.2 + 0.06 * Math.sin(i * 2.3) : 0.97
      var px = cx + ra * f * Math.cos(ang), py = cy + rb * f * Math.sin(ang)
      if (out && ang > 0.2 && ang < 0.75 && Math.abs(ang - 0.45) < Math.PI / k) px += tail
      p += (i === 0 ? "M " : " L ") + n(px) + " " + n(py)
    }
    return p + " Z"
  }
  // A round, puffy cloud: big and small puffs all round the oval.
  function cloud() {
    var k = Math.max(8, Math.round(Math.PI * (ra + rb) / 26))
    var w = [], sum = 0, i
    for (i = 0; i < k; i++) { w.push(i % 2 ? 0.8 : 1.2); sum += w[i] }
    var a0 = -Math.PI / 2, p = "M " + pt(a0)
    for (i = 0; i < k; i++) {
      var a1 = a0 + 2 * Math.PI * w[i] / sum
      var dx = ra * (Math.cos(a1) - Math.cos(a0)), dy = rb * (Math.sin(a1) - Math.sin(a0))
      var r = Math.sqrt(dx * dx + dy * dy) * 0.53
      p += " A " + n(r) + " " + n(r) + " 0 0 1 " + pt(a1)
      a0 = a1
    }
    return p + " Z"
  }
  readonly property string outline: cloud()

  // ---- Showing --------------------------------------------------------------
  property var chars: []          // the line as characters (emoji stay whole)
  property real typed: 0          // how many are showing

  function show(line, topic) {
    text = String(line).slice(0, 160)
    tone = toneOf(text, topic)
    chars = Array.from(text)
    typed = 0
    active = true
    hideAnim.stop()
    body.opacity = 0; body.scale = 0.25; body.rotation = -9; body.lift = 0; body.shakeX = 0
    showAnim.restart()
    holdTimer.interval = Math.min(7500, 3000 + 55 * text.length)
    holdTimer.restart()
  }

  function dismiss() {
    if (!active) return
    holdTimer.stop()
    showAnim.stop()
    hideAnim.restart()
  }

  Timer { id: holdTimer; onTriggered: bubble.dismiss() }

  TextMetrics { id: metrics; font: label.font; text: bubble.text }

  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
  // The typed part in ink, the rest laid out but invisible, so nothing reflows.
  readonly property string shownText: {
    var k = Math.min(chars.length, Math.floor(typed))
    return esc(chars.slice(0, k).join("")) + "<font color=\"#00000000\">" + esc(chars.slice(k).join("")) + "</font>"
  }

  SequentialAnimation {
    id: showAnim
    ParallelAnimation {
      NumberAnimation { target: body; property: "opacity"; to: 1; duration: Style.duration(110) }
      NumberAnimation { target: body; property: "scale"; to: 1; duration: Style.duration(380); easing.type: Easing.OutBack; easing.overshoot: 2.4 }
      NumberAnimation { target: body; property: "rotation"; to: 0; duration: Style.duration(460); easing.type: Easing.OutBack; easing.overshoot: 3 }
      SequentialAnimation {
        PauseAnimation { duration: Style.duration(90) }
        NumberAnimation { target: bubble; property: "typed"; to: bubble.chars.length; duration: Math.min(1300, 26 * bubble.chars.length) }
      }
    }
    // A shout rattles a little.
    SequentialAnimation {
      loops: bubble.shout ? 1 : 0
      NumberAnimation { target: body; property: "shakeX"; to: 3; duration: 40 }
      NumberAnimation { target: body; property: "shakeX"; to: -3; duration: 60 }
      NumberAnimation { target: body; property: "shakeX"; to: 2; duration: 50 }
      NumberAnimation { target: body; property: "shakeX"; to: 0; duration: 50 }
    }
  }
  SequentialAnimation {
    id: hideAnim
    ParallelAnimation {
      NumberAnimation { target: body; property: "opacity"; to: 0; duration: Style.duration(200); easing.type: Easing.InCubic }
      NumberAnimation { target: body; property: "scale"; to: 0.82; duration: Style.duration(200); easing.type: Easing.InBack }
      NumberAnimation { target: body; property: "lift"; to: 10; duration: Style.duration(200); easing.type: Easing.OutCubic }
    }
    ScriptAction { script: bubble.active = false }
  }

  // A gentle bob while it's up.
  property real bobT: 0
  NumberAnimation on bobT { running: bubble.active; from: 0; to: Math.PI * 2; duration: 2600; loops: Animation.Infinite }

  Item {
   width: bubble.baseWidth; height: bubble.baseHeight
   scale: bubble.zoom
   transformOrigin: Item.TopLeft
   Item {
    id: body
    width: bubble.baseWidth; height: bubble.baseHeight
    property real lift: 0
    property real shakeX: 0
    x: shakeX
    y: -lift + 1.6 * Math.sin(bubble.bobT)
    opacity: 0
    // Grows out of the tail, at her.
    transformOrigin: Item.Right
    Item {
      anchors.fill: parent
      rotation: 0.8 * Math.sin(bubble.bobT + 1)

      // A flat comic shadow, then the balloon.
      Shape {
        x: 2.5; y: 3
        width: bubble.baseWidth; height: bubble.baseHeight
        preferredRendererType: Shape.CurveRenderer
        ShapePath { fillColor: "#38000000"; strokeColor: "transparent"; PathSvg { path: bubble.outline } }
      }
      Shape {
        width: bubble.baseWidth; height: bubble.baseHeight
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: bubble.shout ? "#fff7d6" : "#fffdf5"
          strokeColor: "#1f1830"
          strokeWidth: bubble.shout ? 2.4 : 2
          joinStyle: ShapePath.RoundJoin
          capStyle: ShapePath.RoundCap
          PathSvg { path: bubble.outline }
        }
      }
      // The thought cloud's little puffs, trailing off toward her.
      Repeater {
        model: [[4.5, 5], [2.8, 12.5]]
        Rectangle {
          required property var modelData
          width: modelData[0] * 2; height: width; radius: width / 2
          x: bubble.cx + bubble.ra * 0.97 + 4 + modelData[1] - width / 2
          y: bubble.cy + bubble.rb * 0.62 + modelData[1] * 0.5 - width / 2
          color: bubble.shout ? "#fff7d6" : "#fffdf5"
          border.color: "#1f1830"; border.width: bubble.shout ? 2.4 : 2
          antialiasing: true
        }
      }

      // Sizes the balloon from the whole line.
      Text {
        id: sizer
        visible: false
        width: bubble.textWidth
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: bubble.text
        font: label.font
        lineHeight: label.lineHeight
      }
      Text {
        id: label
        x: bubble.cx - bubble.textWidth / 2
        y: bubble.cy - bubble.textHeight / 2
        width: bubble.textWidth
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        text: bubble.shownText
        color: "#1f1830"
        lineHeight: 0.92
        font.family: comic.status === FontLoader.Ready ? comic.font.family : "sans-serif"
        font.bold: true
        font.pixelSize: bubble.shout ? 14 : 13
        font.letterSpacing: bubble.shout ? 0.4 : 0.1
      }
    }
  }
}
}
