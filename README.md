# Perch for Omarchy

Mochi, a tiny chibi friend who lives on your focused window in
[Omarchy](https://omarchy.org). She sits on the window's top-right corner and
swings her legs, chats in comic speech bubbles, waves when you switch windows,
and naps when you step away.

![Mochi sitting and waving, on her swing, and asleep](preview.png)

## Install

```bash
omarchy plugin add https://github.com/jebin2/omarchy-perch.git --enable
omarchy restart shell
```

She shows up on the focused window. Nothing else to set up.

## What she does

- **Sits on the focused window's top edge**, near its right corner. She
  swings her legs in little bursts, and her hair and ponytail sway along.
- **Swings from the window's top border** on windows that touch the bar (the
  usual tiled case). There is no room above those, so she hangs inside the
  corner on a little swing instead of covering the bar.
- **Waves** when you switch to another window.
- **Talks** in comic speech bubbles (see below).
- **Yawns** a few seconds before she naps, then **naps** after 90 seconds
  without keyboard or mouse input: eyes closed, a sleep bubble and a few z's.
  While a video is playing (anything that keeps the screen awake) she stays
  up and watches with you. When you come back she **stretches** and says hi.
- **Falls off** when the window she sits on closes ("waah!"), and pops up on
  the next one.
- **Gets out of the way:** when the pointer touches her, she scoots along
  the edge away from it, looking surprised, so you can click whatever was
  under her (a tab, a button, a bar icon). She drifts back to her corner a
  few seconds after the pointer has gone.
- **Hides** on fullscreen windows.
- Her hoodie follows your theme's accent color.

Only her body takes the pointer; the rest of her little window, bubble
included, lets clicks through.

## What she says

She has three moods, **serious** (gentle reminders), **fun** and **sassy**,
and mixes all three. She speaks up:

| When | For example |
|---|---|
| The first time she appears, or after a long nap | "good morning! ☀️", "…why are we still awake 🦉" |
| Now and then when you switch windows, about the app | terminal: "sudo make me a sandwich 🥪", browser: "that's like 40 tabs" |
| Every few minutes, something random | "posture check!", "I see you. 👀" |
| After an hour of activity | "an hour in. stand up and stretch?" |
| Battery at 15%, charger in or out | "I'm hungry… charger? 🔋", "nom nom ⚡" |
| Her window closed | "hey! I was sitting there" |
| A new theme | "new outfit! ✨" |

Ordinary lines keep at least 45 seconds apart; the events above skip the
wait. Apps are recognised by their window class only; window titles and
contents are never read.

### Your own lines

Her lines live in `lines.json` next to `Perch.qml`. To change them without
touching the plugin, create `~/.config/perch/lines.json` with any of the same
sections; each section you include replaces hers (for `app`, each app entry).
It reloads on save.

```json
{
  "chatter": {
    "fun": ["pizza later?"],
    "serious": ["one thing at a time"],
    "sassy": ["is that a bug I see?"]
  },
  "app": {
    "obsidian": ["writing again? nice"]
  }
}
```

A section is a list of lines (any mood) or lists keyed by `serious`, `fun`
and `sassy`. `app` keys are matched against the window class,
case-insensitively, as regular expressions. The sections are `app`, `time`
(`morning`, `noon`, `afternoon`, `evening`, `night`, `latenight`), `chatter`,
`battery_low`, `charging`, `unplugged`, `window_closed`, `theme`, `break`,
`wake` and `yawn`. Lines are at most 160 characters.

### Make her say or do something

```bash
omarchy-shell jebin2.perch say "build passed! 🎉"
omarchy-shell jebin2.perch act wave      # also: yawn, stretch, fall
```

Handy at the end of a long script.

## How it works

Perch is a background (`service`) plugin. It draws Mochi in a small,
transparent layer window and moves it to the focused window.

- **Where the window is:** Hyprland sends no events while a window is dragged
  or resized, so Perch asks Hyprland's socket for the focused window
  (`j/activewindow`) every 150 ms while she is awake. It stops while she
  sleeps.
- **Idle:** the Wayland idle notification (the same one Omarchy's screensaver
  uses). Perch never reads your keyboard.
- **Drawing:** she is made of separate vector pieces (legs, arms, face,
  ponytail, the one hair that never stays down), each drawn once into a
  texture and then moved in code. No images, no Live2D.
- **Cost:** each redraw costs the shell about a millisecond, so she updates
  25 times a second while swinging her legs and 10 while calm or asleep. On
  average that's about 6% of one CPU core while she is awake (measured on a
  laptop iGPU), less on battery, where she sits still for longer between
  bursts.
- Turning animations off (`omarchy toggle animations`) freezes her in place.

## Tuning

The numbers at the top of `Perch.qml`:

| Setting | Default | What |
|---|---|---|
| `size` | `0.9` | Her size; 1.0 is a 64 × 80 px box |
| `inset` | `26` | Gap between her and the window's right edge, px |
| `sleepAfter` | `90` | Seconds without input before she naps |
| `pollMs` | `150` | How often the focused window's position is checked while she is awake |
| `talk` | `true` | `false` keeps her quiet |
| `moods` | all three | Which moods she picks lines from |
| `quietGapSec` | `45` | Least time between ordinary lines |
| `chatterEverySec` | `360` | About how often she says something random |
| `appChance` | `0.35` | Chance of an app line when you switch windows |
| `breakAfterMin` | `60` | Minutes of activity before a break reminder |

Background plugins don't hot-reload: run `omarchy restart shell` after an
edit.

## Uninstall

```bash
omarchy plugin remove jebin2.perch
omarchy restart shell
```

## License

MIT. Mochi is an original character, drawn for this plugin.
