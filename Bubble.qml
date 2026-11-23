import QtQuick
import QtQuick.Shapes
import qs.Commons

// A comic speech bubble with its tail on the right, pointing at Mochi.
// `active` is true from the moment it starts showing until it has faded out,
// so the window can make room for it only while it is there.
Item {
  id: bubble

  property real maxWidth: 180
  property bool active: false
  property string text: ""

  readonly property real tail: 7
  readonly property real padX: 9
  readonly property real padY: 6
  readonly property real bodyWidth: Math.min(maxWidth, metrics.advanceWidth + padX * 2 + 1)

  // Rounded box with the tail on its right side, near the top.
  readonly property string outline: {
    var w = bodyWidth, h = height, r = Math.min(9, h / 2), t = tail, e = 0.7
    var ty = Math.min(h - r - 4, 12)
    return "M " + r + " " + e + " L " + (w - r) + " " + e + " Q " + w + " " + e + " " + w + " " + r
      + " L " + w + " " + (ty - 3) + " L " + (w + t - e) + " " + (ty + 2.5) + " L " + w + " " + (ty + 5)
      + " L " + w + " " + (h - r) + " Q " + w + " " + (h - e) + " " + (w - r) + " " + (h - e)
      + " L " + r + " " + (h - e) + " Q " + e + " " + (h - e) + " " + e + " " + (h - r)
      + " L " + e + " " + r + " Q " + e + " " + e + " " + r + " " + e + " Z"
  }

  width: bodyWidth + tail
  height: label.implicitHeight + padY * 2
  opacity: 0
  scale: 0.96
  transformOrigin: Item.Right

  function show(line) {
    text = String(line).slice(0, 160)
    active = true
    hideAnim.stop()
    showAnim.restart()
    holdTimer.interval = Math.min(7000, 2600 + 55 * text.length)
    holdTimer.restart()
  }

  function dismiss() {
    if (!active) return
    holdTimer.stop()
    showAnim.stop()
    hideAnim.restart()
  }

  TextMetrics {
    id: metrics
    font: label.font
    text: bubble.text
  }

  Timer { id: holdTimer; onTriggered: bubble.dismiss() }

  ParallelAnimation {
    id: showAnim
    NumberAnimation { target: bubble; property: "opacity"; from: 0; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
    NumberAnimation { target: bubble; property: "scale"; from: 0.96; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
  }
  SequentialAnimation {
    id: hideAnim
    NumberAnimation { target: bubble; property: "opacity"; to: 0; duration: Style.duration(120); easing.type: Easing.OutCubic }
    ScriptAction { script: bubble.active = false }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "#fffdf7"
      strokeColor: "#3a2c46"
      strokeWidth: 1.3
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: bubble.outline }
    }
  }

  Text {
    id: label
    x: bubble.padX
    y: bubble.padY
    width: bubble.bodyWidth - bubble.padX * 2
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: bubble.text
    color: "#2a2140"
    font.pixelSize: 12
    font.weight: Font.DemiBold
  }
}
