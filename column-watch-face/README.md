# Column: minimal data watch face for the Forerunner 165

Tall monoline hour and minute digits stacked on the left, a battery bar down the middle,
and weather, steps, calories and heart rate on the right. Layout inspired by COROS's Tidy
face; drawing and code are original.

| Element | Source |
|---|---|
| Big time | Drawn from lines and arcs (`drawDigit`), no font needed, sharp at any size |
| `1105` under the time | Month + day (MMDD), day in green |
| `50%` + middle bar | Battery; bar turns red under 15%, bolt below it while charging |
| Cloud / sun + temperature | Garmin weather from the phone, follows your °C/°F setting |
| Shoe / flame / heart | Steps today, calories today, current or latest heart rate |
| `THU` | Weekday |
| Always-on | Thin dim digits only, shifted 2 px a minute (burn-in) |

## Build

    SDK="$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)"
    "$SDK/bin/monkeyc" -d fr165 -f monkey.jungle -o bin/column-fr165.prg -y ../developer_key

Copy `bin/column-fr165.prg` to **GARMIN/Apps** on the watch (`-d fr165m` for the Music model).
