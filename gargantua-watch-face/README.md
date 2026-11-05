# Gargantua: black-hole watch face for the Forerunner 165

A ray-traced black hole swallowing its accretion disk. Light from the far side of the disk
bends over and under the shadow, hot clumps of gas spiral in and redden as they cross the
horizon, and starlight smears around the hole.

| Watch state | What you see |
|---|---|
| Awake (wrist raised) | Full-screen 6 s loop at 10 fps, time + date below the hole |
| Always-on | Animation stopped: dim outline of the shadow + time, shifted 2 px a minute (burn-in) |

## Build

    SDK="$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)"
    "$SDK/bin/monkeyc" -d fr165 -f monkey.jungle -o bin/gargantua-fr165.prg -y ../developer_key

Copy `bin/gargantua-fr165.prg` to **GARMIN/Apps** on the watch (OpenMTP on a Mac).
Use `-d fr165m` for the Music model.

## Re-render the animation

    python3 tools/render.py --preview   # one frame -> build/preview.png (~4 s)
    python3 tools/render.py             # 60 frames -> resources/animations/ (~3 min)

Needs numpy, Pillow, ffmpeg. Tunables are at the top of `tools/render.py`: tilt (`INCL`),
size (`SCALE`), disk edges, loop length. If you move the hole (`CX`, `CY`, `SCALE`), update
`HOLE_Y` / `HOLE_R` in `source/GargView.mc` so the always-on ring lines up.

## How it works

- Each pixel is a light ray traced back from the camera on the exact Schwarzschild photon
  orbit (`u'' = 3u² - u`). Rays depend only on their impact parameter, so one table of orbits
  serves every pixel.
- Up to 5 disk crossings per ray give the primary image, the lensed far side and the
  photon ring. Doppler + gravitational shift (Luminet 1979) sets brightness and colour.
- Animation is drawn with motion blur (4 sub-frames per frame), because Monkey Motion
  plays at most 10 fps. The loop is seamless.
