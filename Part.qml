import QtQuick
import QtQuick.Shapes

// One piece of Mochi, drawn in her 64 x 80 design grid.
Shape {
  id: part

  property string d: ""
  property color fill: "transparent"
  property color stroke: "#3a2c46"
  property real strokeWidth: 0.9

  width: 64
  height: 80
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    fillColor: part.fill
    strokeColor: part.strokeWidth > 0 ? part.stroke : "transparent"
    strokeWidth: part.strokeWidth
    capStyle: ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
    PathSvg { path: part.d }
  }
}
