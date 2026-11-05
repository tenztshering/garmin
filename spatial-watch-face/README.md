# Spatial: layered-hour watch face for the Forerunner 165

The hour is drawn as giant geometric digits: one layer of frosted glass over a solid orange
one ("10" = glass pill over an orange disc), with analog hands on top. Inspired by the
layered-numeral idea of Samsung's Spatial Number face; digits and layout are our own.

| Element | Meaning |
|---|---|
| Glass + orange digits | Current hour (12 h). Two-digit hours: first digit glass. One-digit hours: first stroke glass |
| Hands | Hours and minutes |
| Left arc | Steps towards your daily goal, count along the edge |
| Right ticks | Battery, one tick per 10% |
| Always-on | Thin dim hands only, shifted 2 px a minute (burn-in) |

Battery: static face, one redraw per minute, no animation.

## Build

    SDK="$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)"
    "$SDK/bin/monkeyc" -d fr165 -f monkey.jungle -o bin/spatial-fr165.prg -y ../developer_key

Copy `bin/spatial-fr165.prg` to **GARMIN/Apps** on the watch (`-d fr165m` for the Music model).

## Change the look

`python3 tools/render.py` regenerates the 12 hour scenes (`resources/drawables/hourNN.png`)
and a contact sheet at `build/sheet.png`. Colours, digit shapes and glass strength are at the
top of that file.
