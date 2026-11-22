# Garmin Connect IQ projects

Target: Forerunner 165 (390 × 390 round AMOLED, RGB565). SDK 9.3.0. Build with strict
typing (`-l 2`). `developer_key` never leaves this folder or enters git.

## Every change: optimise first

- **Battery.** GPS is the biggest drain: continuous all-systems only while it matters,
  and a GPS-only "Battery saver" option on anything that records. Redraw on events or a
  1 s timer at most; stop timers in `onHide`. Watch faces: one update a minute when
  asleep, nothing animated in low power.
- **AMOLED.** Mostly black screens, few lit pixels, dim secondary content. Always-on mode
  under 10% lit and shifted 2 px a minute against burn-in.
- **Memory.** Load only the bitmap the screen needs now; no growing arrays (sum as you go
  instead of storing tracks). Check the simulator's memory readout after changes.
- **Art.** Pre-render what the watch can't do (blur, ray tracing, detailed art) in
  Python, snap colours to RGB565, crop to content, keep bitmaps as small as the layout
  allows.
- **Leave one runnable check** for non-trivial logic (`(:test)` + `monkeydo -t`).

## Every screen: design it to impress

- **One hero per screen** (the time, the count) in white and large; everything else steps
  back: soft grey secondary text, dim artwork, thin rings. Squint test before shipping.
- **Sharp text:** native fonts (`FONT_TINY`, `FONT_XTINY`, `FONT_NUMBER_*`) for small text;
  vector fonts only at large sizes.
- **Round-screen safe zones:** keep text inside the circle at its row; nothing touches the
  bezel except rings and ticks.
- **Every line earns its place:** plain words that say what to do ("UP / DOWN change
  goal"); delete text the user can't act on (e.g. 0.00 km before starting).
- **States read at a glance:** paused, goal reached and weak GPS each change colour or dim
  the screen, not only a word.
- **Review the whole journey** in the simulator (every state, start to finish) and show the
  user screenshots before calling UI done.

## Watch faces: always customisable

- Every watch face ships with **settings** (`properties.xml` + `settings.xml`, applied in
  `onSettingsChanged`) **and on-watch customisation**: implement `getSettingsView()` in the
  app with a `Menu2` (accent colour, data fields, etc.), so the watch's face picker offers
  **Customize** alongside the system **Delete** option.
- Offer at least an accent colour choice; if colours are baked into bitmaps, pre-render one
  per accent.

## Connect IQ pitfalls (learned on a real FR165)

- **START button** arrives as the `onSelect` behaviour, not `onKey(KEY_ENTER)`. Swallow
  screen taps in `onTap` so a sleeve can't trigger it.
- **Never `System.exit()`** from a menu or confirmation callback, least of all right after
  ending an `ActivityRecording` session: it froze the watch with no crash log. End the
  session, pop back to the main view, show a toast, let BACK exit.
- Crash logs: `GARMIN/Apps/LOGS/CIQ_LOG.YML` on the watch (copy with OpenMTP Cmd+C /
  Cmd+V; dragging to Finder only makes `download.svg`).

## Simulator

- Launch: `monkeydo bin/<app>.prg fr165`. Drive buttons with
  `osascript -e 'tell application "System Events" to key code N'`
  (36 START, 126 UP, 125 DOWN, 53 BACK); mouse clicks and menu navigation don't register.
  Drive menus from a debug copy in the scratchpad (never inside the project).
- Screenshot: find the window id with `CGWindowListCopyWindowInfo` and
  `screencapture -x -l<id>`; wait ~2 s after a key press.

## Shipping

- Release builds go to `dist/` (gitignored); copy the `.prg` to `~/Desktop/<App>/` for
  sideloading into `GARMIN/Apps` with OpenMTP.
- Commit and push only when asked ("push all"): short imperative message, no AI attribution.
