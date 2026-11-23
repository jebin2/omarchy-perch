# Character packs

Perch draws its character from a **pack**: a folder with a `Character.qml`.
Mochi ships with the plugin in `characters/mochi/`. Your own packs go in
`~/.config/perch/characters/<name>/`, outside the plugin folder, so they stay
private and survive plugin updates.

## Choosing a character

`~/.config/perch/config.json`:

```json
{ "character": "mochi" }
```

Names are letters, digits, `-` and `_`. A name shipped with the plugin wins;
otherwise Perch loads `~/.config/perch/characters/<name>/Character.qml`. The
switch happens when you save the file. If a pack fails to load, Perch logs
`perch: character pack failed to load` and falls back to Mochi.

## Writing a pack

Start from a copy of `characters/mochi/` (copy `Part.qml` from the plugin
folder next to it: a pack outside the plugin can't import the plugin's files).

```
~/.config/perch/characters/<name>/
  Character.qml
  Part.qml        # copy of the plugin's Part.qml: one vector shape
```

`Character.qml` is an `Item` with a `property var buddy`, 64 x 80 in size.
Perch sets `buddy` when it creates the pack and scales the whole thing.

### The grid

Everything is drawn in a 64 x 80 grid, so every pack fits the same
skeleton and all of Perch's moves work:

| Point | Where |
|---|---|
| Seat line | y = 56: above it sits on the window edge, legs hang below |
| Hips (leg pivots) | (28, 56) and (36, 56) |
| Shoulders (arm pivots) | (24, 44) left, (40, 44) right; hands rest at about (19, 55) and (45, 55) |
| Head pivot | (32, 42) |
| Swing ropes | x = 19.1 and 44.9, so the resting hands hold them |
| Top of the box | y = 0; keep the head below y = 1 |

Draw the swing seat yourself when `buddy.hanging` is true (Mochi's pack shows
how), between the legs and the body.

### What `buddy` gives you

Bind your pieces' rotations and visibility to these; Perch animates them.

| Property | What |
|---|---|
| `legL`, `legR` | Leg angles, degrees, around the hips |
| `armL`, `armR` | Arm angles, degrees, around the shoulders (wave, stretch, yawn) |
| `headTilt` | Head angle, degrees, around the head pivot |
| `tailSwing` | Slow sway for hair, ponytails, earrings |
| `ahogeSwing` | Faster bob for a single hair or an antenna |
| `breathe` | Vertical scale for the body, around (32, 57) |
| `eyeOpen` | 0..1 for blinking (vertical scale of the eyes) |
| `face` | `"normal"`, `"happy"`, `"startled"`, `"sleep"` or `"yawn"`: show one expression at a time |
| `thinkAmt` | 0..1: chin-on-hand pose during some calm spells (optional; ignore it if your character has no such pose) |
| `hanging` | On the swing (draw the seat) |
| `talking` | A speech bubble is showing (for a talking mouth) |
| `topic`, `mood`, `line`, `lineCount` | The last line she said: its kind (a `lines.json` section such as `battery_low`, `window_closed`, `break`, `charging`; a time of day such as `morning` or `noon`; `app`, `chatter`, `wake`, `yawn`, `theme`; `say` for the IPC command), the mood it came from (`serious`, `fun`, `sassy`, or empty), its text, and a counter that goes up with every line: react in `onLineCountChanged` |
| `app` | The class of the window she sits on (`kitty`, `spotify`, `discord`…), or empty: show a pose for the app |
| `action`, `actionCount` | A move asked for with `act <name>` that Perch doesn't do itself (e.g. `act cheer`), and a counter that goes up every time: react in `onActionCountChanged` |
| `calm`, `sleeping` | Between leg-swinging bursts; napping |
| `walking`, `walkDir`, `running`, `jumping` | Travelling to the next window (`-1` left, `1` right): along a level edge she walks, `running` on long trips (600 px or more), on the swing (`hanging`) the swing slides; `jumping` when the next window isn't level: she flies there in an arc |
| `roaming` | She's on the desktop of an empty workspace (the bottom of the screen is her floor); only for packs that set `roams: true` on their root |
| `flying` | On her broom (only packs with `flies: true`): long trips, joyrides and sky trips on the desktop (a loop or two in the sky, a hover, then down somewhere else), the entrance; `walkDir` is the direction |
| `ambient` (on the pack's root) | Drifting things on the desktop: `"leaves"`, `"petals"`, `"snowflakes"`, `"stars"` (a shooting star now and then: `shootingStar()`), `{ "kind": "fireflies", "x": 0..1 }` |
| `bubbleAt` (on the pack's root) | `[x, y]` in grid units: soap bubbles float up from there while it's set |
| `peekSide` | Set `-1`/`1` and she runs to that edge of the desktop and peeks out from it (hide and seek); `0` brings her back. Clicks don't make her scoot while she hides |
| `skyHover()` | A sky trip's hover just started (a few seconds): a good moment for a little card |
| `climbing`, `climbDir` | On her ladder from the desktop floor to the bar (`climbs: true`), `1` up, `-1` down; up there she `hanging`s from the bar |
| `deskX`, `goTo(x)` | On the desktop: where she is across the screen (0..1), and `buddy.goTo(0.1)` sends her walking there |
| `desktopProps` (on the pack's root) | Things to draw on the desktop floor: `[{ source, x (0..1), w, h }]`, sizes in grid units (a plant, a lamp...). Optional: `id`, `mirror`, `lift` (grid units up), `front` (in front of her), `speed` (glides to a new `x` at that many grid units a second: a pet), `tap` (clickable, see `propTapped`). Keep the list the same length while it shows, so moving things glide |
| `propTapped(id)` | A `tap: true` prop was clicked |
| `welcomed(kind)` | She came in from off screen: `"login"`, `"resume"` or `"back"`. Broom packs: fired while she hovers in the middle of the screen (6.5 s, `flying` stays true) before she flies to her place; others: when she lands |
| `sensed(kind, app)` | She noticed something: `"volup"` / `"voldown"` (volume turned up or down), `"loud"` (to 100%), `"mute"`, `"brighter"` / `"dimmer"`, `"bright"` (to full), `"selfie"` (you took a screenshot) or `"notify"` (`app` = the app's name). One per burst of key presses. Set `senses: true` on the pack's root to react yourself; otherwise Perch says a line |
| `weather` (on the pack's root) | `"rain"` or `"snow"`: Perch lets it fall across the empty workspace |
| `stay` (on the pack's root) | `true` while she's busy at something on the desktop: she doesn't wander off |
| `moves` (on the pack's root) | `[{ "id": "dance", "label": "Dance" }, …]`: extra buttons in the panel's "Make her…"; each sends that id as an `act` (see `action`) |
| `games` | False when the user turned games off for the empty workspace: don't start one (and end one that's running) |
| `focusing`, `focusLeft`, `focusStarted(min)`, `focusDone(min)` | The focus timer runs (seconds left): Perch keeps her quiet and in place; a pack can show a calm pose |
| `meeting` | The mic or camera is in use: Perch keeps her quiet |
| `music`, `movie` | A music player is playing; a video player (or a browser on a video site) is playing |
| `windowTitle` | The focused window's title |
| `dragging`, `dragOffset` | She's being carried with the pointer (`dragOffset`: how far it has moved, a point) |
| `highFives` | Goes up with every double click on her |
| `signText`, `signCount` | A message to hold up on a sign (`omarchy-shell jebin2.perch sign "text"`, or the pack's own `buddy.showSign(text)`): react in `onSignCountChanged`; set `hasSign: true` on the pack's root so Perch doesn't also say it in a bubble |
| `patted`, `pats`, `patCount` | A click on her: `patted` for a moment, `pats` = clicks in the current quick burst, `patCount` goes up with every click: react in `onPatCountChanged` |
| `startled`, `startleDir` | The pointer touched her; she scoots left (`-1`) or right (`1`) |
| `waveAmt`, `yawnAmt`, `stretchAmt` | 0..1 while she waves, yawns or stretches |
| `fallT`, `falling` | 0..1 while she falls off a closed window |
| `lively`, `shown`, `motion` | Swinging her legs right now; visible; animations on |
| `sleepAmt` | 0..1 while dozing off |
| `t`, `wav(period, shift)` | The animation clock (0..12 s) and a sine of it, for your own loops; periods must divide 12 |
| `cache`, `tex` | Put `layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)` on each moving group: it is drawn once and then only moved, which keeps the shell light |

A pack can make her talk with `buddy.say(text, topic)`: the line goes through Perch like any other (Talk and the quiet gap apply) and comes back as `topic`/`line`.

A pack can also set, on its root item:

| Property | What |
|---|---|
| `ownSwing` | `true` while it draws its own swing ropes, so Perch hides its own |
| `ownFall` | `true` if it has its own falling frames: Perch then only drops and fades her, without tipping her over |
| `headroom` | Grid units the pack draws above its box (a hat, standing up to walk), up to 40: Perch keeps that much room above her. Keep it constant |

Sprite packs (frames of drawn poses instead of moving parts) use these: a
timer picks the frame for the current state from the values above.

Perch itself draws the swing ropes and the sleeping z's, tilts and drops the
whole character when she falls off, and handles the speech bubble.

### Tips

- Keep each moving part (each leg, each arm, the head, a ponytail) in its own
  `Item` with its own `transform` and a `layer`, and keep the parts that
  change often (an animated bubble) out of the layers.
- Bind colors to `Color.accent` (`import qs.Commons`) if you want the theme
  to recolor something.
- Text in a pack should use `textFormat: Text.PlainText`.
- Background plugins don't hot-reload: run `omarchy restart shell` after
  editing a pack (switching packs in `config.json` does apply live).
- Test the moves with `omarchy-shell jebin2.perch act wave` (also `yawn`,
  `stretch`, `think`, `fall`); any other name reaches the pack as
  `buddy.action`.
