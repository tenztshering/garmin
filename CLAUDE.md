# Garmin Connect IQ projects

Target: Forerunner 165 (390 × 390 round AMOLED, RGB565). SDK 9.3.0. Build with strict
typing (`-l 2`). `developer_key` never leaves this folder or enters git.

## Every change: optimise first

- **Battery.** GPS is the biggest drain: continuous all-systems only while it matters,
  and a GPS-only "Battery saver" option on anything that records. Redraw on events or a
  1 s timer at most; stop timers in `onHide`. Watch faces: one update a minute when
  asleep, nothing animated in low power.
- **AMOLED.** Mostly black screens, few lit pixels, dim secondary content. Always-on mode
  follows the burn-in rules under "Watch faces" (a 2 px nudge is not enough).
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

## Watch faces: building rules

- **Customize:** every face ships with settings (`properties.xml` + `settings.xml`, applied in
  `onSettingsChanged`) and on-watch customisation: copy `source/Customize.mc` from an
  existing face and return `new CustomizeMenu(rows).views()` from `getSettingsView()`.
  The face picker then shows **Customize**. Offer at least an accent colour, and check every
  choice for contrast against the artwork (orange hands vanished on Spatial's orange digit).
- **Delete is not ours to add.** Garmin draws it: faces installed from the Connect IQ Store
  (or the Connect IQ phone app) show Delete on the watch; sideloaded `.prg` files may not.
  Remove a sideloaded face by deleting its `.prg` from `GARMIN/Apps` over USB. Say so; never
  promise a Delete option.
- **Always-on (sleep) mode or the watch shows its plain default face instead.** The FR165
  (Venu 2 and later) enforces under 10% of screen *luminance*, and it may switch to
  always-on **without calling `onEnterSleep`**: a face that only watches `onEnterSleep`
  keeps drawing its full design, breaks the rule, and is replaced. Copy
  `source/AlwaysOn.mc` and start `onUpdate` with `if (isLowPower(_sleeping))`, which also
  checks `System.getDisplayMode()`. Faces with layers or animation must hide/stop them when
  `onUpdate` detects low power (see Gargantua `setLowPower`). In always-on draw only the
  time, thin and dim, nudge with `aodShift(min)` and finish with `burnInMask(dc, min)`.
  Check with Settings → Display Mode → Always-On and back to High Power in the simulator,
  then confirm on the watch: the simulator does not catch this one.
- **Lock Device (hold LIGHT) shows Garmin's plain face** instead of our faces until
  unlocked, even with the always-on fix. Faces get no lock signal and no API to draw the
  locked screen: treat it as firmware behaviour, don't chase it in code.

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
