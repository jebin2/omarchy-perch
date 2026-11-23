import QtQuick
import qs.Commons
import "../.."

// Mochi, the default character. A character pack draws one character in
// Perch's 64 x 80 grid, moving its pieces with the values on `buddy` (see
// CHARACTERS.md): seat line y = 56, hips at x 28 and 36, shoulders at
// (24, 44) and (40, 44), head pivot (32, 42).
Item {
  id: mochi

  property var buddy

  width: 64
  height: 80

  // Palette. The hoodie follows the theme's accent color.
  readonly property color line: "#3a2c46"
  readonly property color skin: "#ffe6d6"
  readonly property color hair: "#5d4c8f"
  readonly property color hairLight: "#7f6dc2"
  readonly property color hoodie: Color.accent
  readonly property color hoodieShade: Qt.darker(Color.accent, 1.3)
  readonly property color blush: "#ff9db4"
  readonly property color tie: "#ff7aa2"

  // ---- Legs, behind the hoodie -------------------------------------
  Repeater {
    model: [{ x: 0, angle: "legL" }, { x: 8, angle: "legR" }]
    delegate: Item {
      required property var modelData
      width: 64; height: 80
      transform: Rotation { origin.x: 28 + modelData.x; origin.y: 56; angle: buddy[modelData.angle] }
      Item {
        layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
        x: modelData.x
        width: 64; height: 80
        Part { fill: mochi.skin; d: "M 25.8 55 L 30.2 55 L 30 69 Q 28 70 26 69 Z" }
        Part { fill: "#f6f3fb"; d: "M 25.9 64.2 L 30.1 64.2 L 30 69.6 L 26 69.6 Z" }
        Part { fill: mochi.tie; strokeWidth: 0; d: "M 25.95 65.4 L 30.05 65.4 L 30.05 66.4 L 25.95 66.4 Z" }
        Part { fill: "#4a3552"; d: "M 23.8 71.6 C 23.8 68.6 32.2 68.6 32.2 71.6 C 32.2 74.2 23.8 74.2 23.8 71.6 Z" }
        Part { fill: "#ffffff"; strokeWidth: 0; opacity: 0.35; d: "M 25.4 70.6 C 26.5 69.6 29 69.6 30 70.2 C 28.5 70.4 26.8 70.6 25.4 70.9 Z" }
      }
    }
  }

  // ---- Swing seat ----------------------------------------------------
  Part {
    visible: buddy.hanging
    fill: "#b07a4f"; strokeWidth: 0.8
    d: "M 15.2 56.4 L 48.8 56.4 L 48.8 59 L 15.2 59 Z"
  }

  // ---- Body ---------------------------------------------------------
  Item {
    layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
    width: 64; height: 80
    transform: Scale { origin.x: 32; origin.y: 57; yScale: buddy.breathe }

    // Hood lying behind her neck.
    Part { fill: mochi.hoodieShade; d: "M 20.6 42.8 C 21.8 37.2 42.2 37.2 43.4 42.8 C 38 45.4 26 45.4 20.6 42.8 Z" }
    Part { fill: mochi.hoodie; d: "M 23.5 40.5 C 21.8 45 20.6 51 20.4 57.4 L 43.6 57.4 C 43.4 51 42.2 45 40.5 40.5 C 36.5 42.6 27.5 42.6 23.5 40.5 Z" }
    Part { fill: mochi.hoodieShade; strokeWidth: 0.6; d: "M 25.6 50.8 L 38.4 50.8 L 37.4 56.2 L 26.6 56.2 Z" }
    Part { fill: "transparent"; stroke: "#fbf7ff"; strokeWidth: 0.8; d: "M 29.4 42.6 L 28.9 47.6 M 34.6 42.6 L 35.1 47.6" }
    Part { fill: "#fbf7ff"; strokeWidth: 0; d: "M 28.1 47.6 A 0.8 0.8 0 1 0 29.7 47.6 A 0.8 0.8 0 1 0 28.1 47.6 Z M 34.3 47.6 A 0.8 0.8 0 1 0 35.9 47.6 A 0.8 0.8 0 1 0 34.3 47.6 Z" }

  }

  // ---- Head ---------------------------------------------------------
  Item {
    width: 64; height: 80
    transform: Rotation { origin.x: 32; origin.y: 42; angle: buddy.headTilt }

    // Side ponytail.
    Item {
      layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
      width: 64; height: 80
      transform: Rotation { origin.x: 17.5; origin.y: 14; angle: buddy.tailSwing }
      Part { fill: mochi.hair; d: "M 18 13 C 9 14 4 24 5.5 37 C 6 41 8 44 10 46 C 9.5 42 10 39 11.5 36 C 11 40 12 43 14.5 45 C 14 38 15 30 17.5 24 C 18.5 20 19.5 16 18 13 Z" }
      Part { fill: "transparent"; stroke: mochi.hairLight; strokeWidth: 0.9; d: "M 13 20 C 9.5 25 8.5 31 9 37" }
    }
    // Hair, face and bangs: drawn once into a texture, redrawn only
    // when her expression changes.
    Item {
      width: 64; height: 80
      layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
      Part { fill: mochi.tie; d: "M 15.3 14.2 A 2.2 2.2 0 1 0 19.7 14.2 A 2.2 2.2 0 1 0 15.3 14.2 Z" }

      Part { fill: mochi.hair; d: "M 13.5 29 C 12 15 21 6.5 32 6.5 C 43 6.5 52 15 50.5 29 C 50.5 34 51 38 50 41 C 48 42.5 46 42 45 39.5 C 44.5 35 44.5 31 44 28 L 20 28 C 19.5 31 19.5 35 19 39.5 C 18 42 16 42.5 14 41 C 13 38 13.5 34 13.5 29 Z" }
      Part { fill: mochi.skin; d: "M 16 27 C 16 17 23 11 32 11 C 41 11 48 17 48 27 C 48 35 41 41 32 41 C 23 41 16 35 16 27 Z" }

      // Cheeks.
      Rectangle { x: 19.4; y: 32; width: 5.2; height: 2.6; radius: 1.3; color: mochi.blush; opacity: 0.65 }
      Rectangle { x: 39.4; y: 32; width: 5.2; height: 2.6; radius: 1.3; color: mochi.blush; opacity: 0.65 }

      // Eyes: open, ^ ^ when waving, closed when asleep.
      Repeater {
        model: [23.6, 35.6]
        delegate: Item {
          required property real modelData
          x: modelData; y: 25.6
          width: 4.8; height: 6.6
          visible: buddy.face === "normal" || buddy.face === "startled"
          transform: Scale { origin.y: 4.2; yScale: buddy.eyeOpen }
          Rectangle { anchors.fill: parent; radius: 2.4; color: "#2d2347" }
          Rectangle { x: 0.8; y: 3.4; width: 3.2; height: 2.6; radius: 1.3; color: "#7a68c8" }
          Rectangle { x: 2.4; y: 0.9; width: 1.7; height: 1.7; radius: 0.85; color: "#ffffff" }
        }
      }
      Part {
        visible: buddy.face === "happy"
        fill: "transparent"; strokeWidth: 1.2
        d: "M 23.4 30.2 Q 26 26.8 28.6 30.2 M 35.4 30.2 Q 38 26.8 40.6 30.2"
      }
      Part {
        visible: buddy.face === "sleep" || buddy.face === "yawn"
        fill: "transparent"; strokeWidth: 1.1
        d: "M 23.4 29.4 Q 26 31.6 28.6 29.4 M 35.4 29.4 Q 38 31.6 40.6 29.4"
      }

      // Mouth.
      Part {
        visible: buddy.face === "normal"
        fill: "transparent"; strokeWidth: 0.8
        d: "M 30 34.2 Q 31 35.6 32 34.2 Q 33 35.6 34 34.2"
      }
      Part {
        visible: buddy.face === "happy"
        fill: "#d4566e"; strokeWidth: 0.8
        d: "M 29.6 33.6 Q 32 38.2 34.4 33.6 Z"
      }
      Part {
        visible: buddy.face === "startled"
        fill: "#d4566e"; strokeWidth: 0.8
        d: "M 30.6 35 A 1.4 1.7 0 1 0 33.4 35 A 1.4 1.7 0 1 0 30.6 35 Z"
      }
      Part {
        visible: buddy.face === "sleep"
        fill: "#d4566e"; strokeWidth: 0.7
        d: "M 31.1 34.8 A 0.9 0.8 0 1 0 32.9 34.8 A 0.9 0.8 0 1 0 31.1 34.8 Z"
      }
      Part {
        visible: buddy.face === "yawn"
        fill: "#b8405a"; strokeWidth: 0.8
        d: "M 29.8 35.4 A 2.2 2.8 0 1 0 34.2 35.4 A 2.2 2.8 0 1 0 29.8 35.4 Z"
      }

      // Bangs.
      Part { fill: mochi.hair; d: "M 15.5 27 C 15.5 15 23 9 32 9 C 41 9 48.5 15 48.5 27 C 46.5 24 45 21 43.5 18.5 C 42.5 22 40 24 36.5 24.5 C 37 22 36.5 19.5 35.5 17.5 C 34 21 30.5 23.5 26.5 23.5 C 27.5 21.5 28 19.5 28 17.5 C 25.5 21 22.5 23 19.5 23.5 C 18 24.5 16.5 25.5 15.5 27 Z" }
      Part { fill: "transparent"; stroke: mochi.hairLight; strokeWidth: 1; d: "M 22 13.5 C 25 11.6 28 11 31 11" }

    }
    // The one hair that never stays down.
    Item {
      layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
      width: 64; height: 80
      transform: Rotation { origin.x: 32.8; origin.y: 9.4; angle: buddy.ahogeSwing }
      Part { fill: mochi.hair; d: "M 32 9.5 C 30.5 5.5 32 2 36.5 1 C 34.5 3 33.5 5.5 33.6 9.5 Z" }
    }

    // Sleep bubble.
    Rectangle {
      visible: buddy.face === "sleep"
      readonly property real r: 1.1 + 1.7 * (0.5 + 0.5 * buddy.wav(3))
      x: 35.4 - r; y: 33 - r
      width: 2 * r; height: 2 * r; radius: r
      color: "#bfe3ff"; opacity: 0.7
      border.color: "#ffffff"; border.width: 0.4
    }
  }

  // ---- Left arm: hand on the edge, in front so it shows when raised ---
  Item {
    layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
    width: 64; height: 80
    transform: Rotation { origin.x: 24; origin.y: 44; angle: buddy.armL }
    Part { fill: "transparent"; stroke: mochi.line; strokeWidth: 6.2; d: "M 24 44 Q 20.6 49 19.2 54.4" }
    Part { fill: "transparent"; stroke: mochi.hoodie; strokeWidth: 4.6; d: "M 24 44 Q 20.6 49 19.2 54.4" }
    Part { fill: mochi.skin; d: "M 16.8 55.6 A 2.3 2.3 0 1 0 21.4 55.6 A 2.3 2.3 0 1 0 16.8 55.6 Z" }
  }

  // ---- Right arm: rests, or waves -----------------------------------
  Item {
    layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)
    width: 64; height: 80
    transform: Rotation { origin.x: 40; origin.y: 44; angle: buddy.armR }
    Part { fill: "transparent"; stroke: mochi.line; strokeWidth: 6.2; d: "M 40 44 Q 43.4 49 44.8 54.4" }
    Part { fill: "transparent"; stroke: mochi.hoodie; strokeWidth: 4.6; d: "M 40 44 Q 43.4 49 44.8 54.4" }
    Part { fill: mochi.skin; d: "M 42.6 55.6 A 2.3 2.3 0 1 0 47.2 55.6 A 2.3 2.3 0 1 0 42.6 55.6 Z" }
  }
}
