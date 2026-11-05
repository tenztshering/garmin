# Ridge: mountain watch face for the Forerunner 165

Big halftone time with mountain line art in front, weather and date above, the sun's path
through the day below, and the next sunrise or sunset at the bottom. Layout inspired by
COROS's Night Climber; the mountain art and drawing are original.

| Element | Source |
|---|---|
| Battery (top) | `System.getSystemStats()` |
| Weather icon, temp, low/high | Garmin weather (`Toybox.Weather`), synced from the phone |
| Date + weekday | Watch clock |
| Sun curve | 24 h across, crosses the horizon at today's sunrise/sunset; dot = now |
| Bottom time | Next sunrise (arrow up) or sunset (arrow down); `-- --` until weather has a location |
| Always-on | Smaller dim time only, shifted 2 px a minute (burn-in) |

## Build

    SDK="$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)"
    "$SDK/bin/monkeyc" -d fr165 -f monkey.jungle -o bin/ridge-fr165.prg -y ../developer_key

Copy `bin/ridge-fr165.prg` to **GARMIN/Apps** on the watch (`-d fr165m` for the Music model).

`python3 tools/render.py` regenerates the halftone + mountain overlay
(`resources/drawables/overlay.png`) and a preview at `build/preview.png`.
