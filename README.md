# Perch for Omarchy

Mochi, a tiny chibi friend who lives on your focused window in
[Omarchy](https://omarchy.org). She sits on the window's top-right corner and
swings her legs, waves when you switch windows, and naps when you step away.

![Mochi sitting and waving, on her swing, and asleep](preview.png)

## Install

```bash
omarchy plugin add https://github.com/jebin2/omarchy-perch.git --enable
omarchy restart shell
```

She shows up on the next window you focus. Nothing else to set up.

## What she does

- **Sits on the focused window's top edge**, near its right corner, swinging
  her legs. Her hair and ponytail sway along.
- **Swings from the window's top border** on windows that touch the bar (the
  usual tiled case). There is no room above those, so she hangs inside the
  corner on a little swing instead of covering the bar.
- **Waves** when you switch to another window, and when you come back after
  a nap.
- **Naps** after 90 seconds without keyboard or mouse input: eyes closed,
  a sleep bubble and a few z's. While a video is playing (anything that
  keeps the screen awake) she stays up and watches with you.
- **Gets out of the way:** when the pointer touches her, she scoots along
  the edge away from it, looking surprised, so you can click whatever was
  under her (a tab, a button, a bar icon). She drifts back to her corner a
  few seconds after the pointer has gone.
- **Hides** on fullscreen windows.
- Her hoodie follows your theme's accent color.

Only her body takes the pointer; the rest of her little window lets clicks
through.

## How it works

Perch is a background (`service`) plugin. It draws Mochi in a small,
transparent layer window and moves it to the focused window.

- **Where the window is:** Hyprland sends no events while a window is dragged
  or resized, so Perch asks Hyprland's socket for the focused window
  (`j/activewindow`) every 150 ms while she is awake. It stops while she
  sleeps.
- **Idle:** the Wayland idle notification (the same one Omarchy's screensaver
  uses). Perch never reads your keyboard.
- **Drawing:** she is made of separate vector pieces (legs, arms, head,
  ponytail, the one hair that never stays down), moved in code. No images,
  no Live2D. Her animation runs at 30 updates a second, 10 while she naps.
- **Cost:** about 3% of one CPU core on a laptop iGPU while she is awake.
- Turning animations off (`omarchy toggle animations`) freezes her in place.

## Tuning

The numbers at the top of `Perch.qml`:

| Setting | Default | What |
|---|---|---|
| `size` | `0.9` | Her size; 1.0 is a 64 × 80 px box |
| `inset` | `26` | Gap between her and the window's right edge, px |
| `sleepAfter` | `90` | Seconds without input before she naps |
| `pollMs` | `150` | How often the focused window's position is checked while she is awake |

Background plugins don't hot-reload: run `omarchy restart shell` after an
edit.

## Uninstall

```bash
omarchy plugin remove jebin2.perch
omarchy restart shell
```

## License

MIT. Mochi is an original character, drawn for this plugin.
