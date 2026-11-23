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
| `topic`, `mood`, `lineCount` | The last line she said: its kind (a `lines.json` section such as `battery_low`, `window_closed`, `break`, `charging`; a time of day such as `morning` or `noon`; `app`, `chatter`, `wake`, `yawn`, `theme`; `say` for the IPC command), the mood it came from (`serious`, `fun`, `sassy`, or empty), and a counter that goes up with every line: react in `onLineCountChanged` |
| `calm`, `sleeping` | Between leg-swinging bursts; napping |
| `startled`, `startleDir` | The pointer touched her; she scoots left (`-1`) or right (`1`) |
| `waveAmt`, `yawnAmt`, `stretchAmt` | 0..1 while she waves, yawns or stretches |
| `fallT`, `falling` | 0..1 while she falls off a closed window |
| `lively`, `shown`, `motion` | Swinging her legs right now; visible; animations on |
| `sleepAmt` | 0..1 while dozing off |
| `t`, `wav(period, shift)` | The animation clock (0..12 s) and a sine of it, for your own loops; periods must divide 12 |
| `cache`, `tex` | Put `layer.enabled: buddy.cache; layer.smooth: true; layer.textureSize: Qt.size(64 * buddy.tex, 80 * buddy.tex)` on each moving group: it is drawn once and then only moved, which keeps the shell light |

A pack can also set, on its root item:

| Property | What |
|---|---|
| `ownSwing` | `true` while it draws its own swing ropes, so Perch hides its own |
| `ownFall` | `true` if it has its own falling frames: Perch then only drops and fades her, without tipping her over |

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
  `stretch`, `think`, `fall`).
