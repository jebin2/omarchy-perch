import QtQuick
import QtQuick.Shapes
import qs.Commons

// A cloud-shaped speech bubble: a puffy outline with two little puffs
// trailing off to the right, toward Mochi.
// `active` is true from the moment it starts showing until it has faded out.
Item {
  id: bubble

  property real maxWidth: 200
  property bool active: false
  property string text: ""

  readonly property real tail: 16      // room for the trailing puffs
  readonly property real padX: 9
  readonly property real padY: 5
  readonly property real textWidth: Math.min(maxWidth - 2 * edge - tail, metrics.advanceWidth + 1)
  readonly property real bodyWidth: textWidth + padX * 2
  readonly property real bodyHeight: label.implicitHeight + padY * 2
  // How far the puffs bulge out of the text box.
  readonly property real edge: 6

  // The cloud: arcs bulging out along each side of the box.
  function cloud(x, y, w, h) {
    var nx = Math.max(2, Math.round(w / 20)), ny = Math.max(1, Math.round(h / 20))
    var dx = w / nx, dy = h / ny
    var rx = dx * 0.62, ry = dy * 0.62
    function arc(r, px, py) { return " A " + r.toFixed(2) + " " + r.toFixed(2) + " 0 0 1 " + px.toFixed(2) + " " + py.toFixed(2) }
    var p = "M " + x + " " + y, k
    for (k = 1; k <= nx; k++) p += arc(rx, x + k * dx, y)
    for (k = 1; k <= ny; k++) p += arc(ry, x + w, y + k * dy)
    for (k = 1; k <= nx; k++) p += arc(rx, x + w - k * dx, y + h)
    for (k = 1; k <= ny; k++) p += arc(ry, x, y + h - k * dy)
    return p + " Z"
  }
  readonly property string outline: cloud(edge, edge, bodyWidth, bodyHeight)

  width: bodyWidth + 2 * edge + tail
  height: bodyHeight + 2 * edge
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

  // Two little puffs drifting from the cloud toward her.
  Repeater {
    model: [[5, 4], [3.2, 13.5]]
    Rectangle {
      required property var modelData
      width: modelData[0] * 2
      height: width
      radius: width / 2
      x: bubble.edge * 2 + bubble.bodyWidth - 1 + modelData[1] - width / 2
      y: bubble.edge + bubble.bodyHeight * 0.5 + modelData[1] * 0.3 - width / 2
      color: "#fffdf7"
      border.color: "#3a2c46"
      border.width: 1.3
      antialiasing: true
    }
  }

  Text {
    id: label
    x: bubble.edge + bubble.padX
    y: bubble.edge + bubble.padY
    width: bubble.textWidth
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    text: bubble.text
    color: "#2a2140"
    font.pixelSize: 12
    font.weight: Font.DemiBold
  }
}
