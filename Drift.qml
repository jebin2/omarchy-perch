import QtQuick

// A light particle layer for her desktop: a fixed handful of small images
// moved by one timer at 16-22 updates a second. (Qt's particle system made
// her full-screen layer redraw at 60 fps, about 20% of a core; this is a
// fraction of that.)
Item {
  id: d
  // "rain", "snow", "leaf", "petal", "firefly" or "bubble"
  property string kind: ""
  property int count: 20
  // Where fireflies and bubbles come from (px); fireflies stay in an
  // areaW x areaH box above that point.
  property real originX: 0
  property real originY: 0
  property real areaW: 440
  property real areaH: 240
  // Bubbles: only while she blows.
  property bool emitting: true
  property real scaleBy: 1
  readonly property string src: "sky/" + kind + ".png"

  function rnd(a, b) { return a + Math.random() * (b - a) }
  function reset(p, first) {
    var W = width, H = height, s
    p.age = 0
    p.ph = Math.random() * 6.28
    p.vr = 0
    p.alive = true
    if (kind === "rain") {
      p.w = 3; p.h = rnd(34, 50)
      p.x = rnd(-40, W + 40); p.y = first ? rnd(-H, H) : rnd(-90, -50)
      p.vx = -35; p.vy = rnd(650, 820); p.life = 99; p.rotation = 3; p.opacity = 0.5
    } else if (kind === "snow") {
      s = rnd(5, 11); p.w = s; p.h = s
      p.x = rnd(-20, W); p.y = first ? rnd(0, H) : -15
      p.vx = rnd(-8, 10); p.vy = rnd(35, 70); p.life = 999; p.opacity = 0.85
    } else if (kind === "leaf" || kind === "petal") {
      s = rnd(11, 19); p.w = s; p.h = s
      p.x = rnd(-40, W); p.y = first ? rnd(0, H) : -25
      p.vx = rnd(5, 25); p.vy = rnd(38, 65); p.life = 999; p.vr = rnd(-70, 70); p.rotation = rnd(0, 360); p.opacity = 0.9
    } else if (kind === "firefly") {
      s = rnd(7, 15); p.w = s; p.h = s
      p.x = originX + rnd(-areaW / 2, areaW / 2); p.y = originY - rnd(10, areaH)
      p.vx = rnd(-12, 12); p.vy = rnd(-10, 6); p.life = rnd(3, 7); p.age = first ? rnd(0, p.life) : 0; p.opacity = 0
    } else if (kind === "bubble") {
      s = rnd(10, 22) * scaleBy; p.w = s; p.h = s
      p.x = originX - s / 2; p.y = originY - s / 2
      p.vx = rnd(5, 50); p.vy = rnd(-60, -30); p.life = rnd(2.2, 4.6); p.opacity = 0
      p.alive = !first && emitting      // they come out one by one
    }
  }
  function step(dt) {
    var W = width, H = height
    for (var i = 0; i < rep.count; i++) {
      var p = rep.itemAt(i)
      if (!p) continue
      if (!p.alive) { if (emitting && Math.random() < dt * 0.35) reset(p, false); continue }
      p.age += dt
      var t = p.age / p.life
      if (t >= 1 || p.y > H + 30 || p.x > W + 60 || p.x < -90) {
        if (kind === "bubble") p.alive = false
        else reset(p, false)
        continue
      }
      p.ph += dt * 1.6
      var sway = kind === "leaf" || kind === "petal" ? 28 * Math.cos(p.ph)
        : kind === "snow" ? 10 * Math.cos(p.ph)
        : kind === "firefly" || kind === "bubble" ? 14 * Math.cos(p.ph * 1.3) : 0
      p.x += (p.vx + sway) * dt
      p.y += p.vy * dt + (kind === "firefly" ? 8 * Math.sin(p.ph) * dt : 0)
      if (p.vr) p.rotation += p.vr * dt
      if (kind === "firefly") p.opacity = Math.sin(Math.PI * t) * (0.6 + 0.4 * Math.sin(p.ph * 3))
      else if (kind === "bubble") p.opacity = t < 0.1 ? t * 10 : t > 0.85 ? (1 - t) / 0.15 : 1
    }
  }
  Repeater {
    id: rep
    model: d.count
    Image {
      property real vx: 0
      property real vy: 0
      property real vr: 0
      property real age: 0
      property real life: 99
      property real ph: 0
      property real w: 8
      property real h: 8
      property bool alive: false
      width: w
      height: h
      visible: alive
      source: d.src
      smooth: true
      Component.onCompleted: d.reset(this, true)
    }
  }
  Timer {
    interval: d.kind === "rain" ? 45 : 62
    repeat: true
    running: d.visible && d.kind !== "" && d.width > 0
    onTriggered: d.step(interval / 1000)
  }
}
