# Topo: offline topographic map for the Garmin Forerunner 165

A Garmin-topo-style map that runs fully on the watch: contours, shaded relief, rivers, roads,
forests and place names for a **16 x 16 km area around Thimphu**, centred on your GPS position.
No phone or internet needed while using it.

## On the watch

| Button | Action |
|---|---|
| UP | Zoom in (10 → 5 → 2 → 1 km across the screen) |
| DOWN | Zoom out |
| Hold UP (menu) | Settings: **Battery saver** on/off |
| BACK | Exit (screen returns to its normal timeout) |

What is on screen:

| Element | Meaning |
|---|---|
| Crosshair (centre) | Your position, always at the screen centre |
| `2348 M` (top) | Current altitude from the barometric altimeter (GPS altitude as fallback); `-- M` until the first reading |
| Green `SEARCHING GPS` | No current fix yet (up to 90 s); map is centred on your last known position meanwhile |
| Red `NO GPS` | Still no fix after 90 s (e.g. indoors) |
| Dark `OUTSIDE MAP` | Fix is fine, but you are outside the 16 km map area |
| Red arrow (top left) | North. The map is always north-up |
| Scale bar (bottom) | Length on the ground at this zoom: 200 m, 250 m, 1 km, 2 km |

Map style: grey paper, brown 20 m contours with a darker line every 100 m, bold elevation
numbers (1 and 2 km zooms) on paper halos, hill-shading lit from the north-west, thin blue
rivers, ochre main roads, grey streets and paths, green pine symbols in forests, place names.
Fine contours and elevation numbers are hidden at 5 km and wider; paths, trees and place names
at 10 km.

Settings:

| | Battery saver off (default) | Battery saver on |
|---|---|---|
| Satellites | GPS + GLONASS + Galileo + BeiDou | GPS only |
| Screen | Kept on while the app is open | Normal timeout |

The setting is also exposed to Garmin Connect, which may not show it for sideloaded apps.

## Install (sideload)

Requires the Connect IQ SDK with the `fr165` device profile, and `../developer_key`.

    SDK=~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.3.0-2026-10-20-95888f262
    "$SDK/bin/monkeyc" -d fr165 -f monkey.jungle -o bin/topo-fr165.prg -y ../developer_key -r

Copy `bin/topo-fr165.prg` to **GARMIN/Apps** on the watch (on a Mac use OpenMTP; quit OneDrive
and Garmin Express first). Open it from the activities/apps list (START button).

## How it works

- **Map data** is built on a Mac by `tools/make_topo.py` from public elevation tiles and
  OpenStreetMap, then compiled into the app. Nothing is downloaded on the watch.
- **Vector data** (contours, roads, rivers, paths) is split into 4 km tiles. Each tile has a
  `major` file and a `minor` file (20 m contours). The watch loads only the tiles around the
  view, and `minor` only at 1 and 2 km zoom. Lines are stored as compact strings
  (2 characters per coordinate, ~4 m precision) with packed bounding boxes for fast culling.
- **Shaded relief** is 100 tiles of 128 px (~13 m/px) plus a 256 px overview used at 10 km zoom.
  They are scaled up with bilinear filtering.
- **Rendering** is progressive: the map is drawn into an off-screen bitmap a few hundred points
  every 50 ms, because drawing it in one go trips the watch's watchdog. The screen only copies
  that bitmap and draws the overlays. The map is re-rendered on zoom, or after moving 15% of
  the screen; GPS updates under 1 px of movement are ignored.
- **Memory** (simulator, at the four zooms): 88 / 117 / 154 / 178 KB of 764 KB.
  App file: 3.8 MB (watch limit 64 MB).

Files:

| Path | What |
|---|---|
| `source/TopoApp.mc` | App, GPS setup, buttons, settings menu |
| `source/TopoView.mc` | Rendering, position, altitude, overlays |
| `source/VectorTiles.mc`, `source/ShadeTiles.mc` | Generated resource lists |
| `resources/data/` | `topo.json` (labels, trees, places) and `v_<row>_<col>_<major|minor>.json` |
| `resources/shade/` | Hill-shade bitmaps |
| `tools/make_topo.py` | Builds all map data |
| `tools/preview.py` | Renders the map on a Mac in the same style |

## Rebuild the map data

    python3 -I tools/make_topo.py <lat> <lon> <half_size_m> <contour_interval_m>
    python3 -I tools/preview.py preview.png [span_m [centre_x_m centre_y_m]]

Current map: `python3 -I tools/make_topo.py 27.45471 89.6393 8000 20`

Downloads are cached in `$TOPO_CACHE` (default `.topo-cache/`). The public Overpass
(OpenStreetMap) server sometimes returns 502; just run it again.

## Verified vs not yet verified

Verified in the simulator: all four zooms fill the screen at an off-centre position, memory
figures above, no watchdog or memory errors, status pills, centred crosshair.

Not yet verified on the watch:
- Time to first GPS fix with the phone off or in airplane mode
- Altitude reading from the barometer (the simulator reports a fixed value)
- The settings menu (hold UP) and the battery saver's real battery effect
- How long the screen actually stays on before AMOLED burn-in protection dims it

## To do

Ideas for future versions, roughly by value:

- [ ] **Breadcrumb trail**: draw where you have walked this session
- [ ] **Record the hike** as a Garmin activity (FIT file) so it syncs to Garmin Connect
- [ ] **Waypoints**: save the current position (e.g. car, camp) and show distance/bearing back to it
- [ ] **Follow a route**: load a GPX track built on the Mac and draw it on the map
- [ ] **Summit markers**: ▲ with elevation at local high points, computed from the elevation data
- [ ] **Pan mode**: move the map away from your position, then snap back
- [ ] **Data fields**: distance, time, ascent, speed in a small strip
- [ ] **Bigger or multiple areas**: e.g. Paro, Punakha, trek routes; pick the area in settings
- [ ] **Faster zoom**: keep the previous zoom's bitmap to show instantly while the new one renders
- [ ] **GPS update interval** setting for longer battery life on multi-day hikes
- [ ] **Trail names and POIs** from OpenStreetMap (huts, bridges, viewpoints, water)
- [ ] **Dark map theme** for night use (less power on AMOLED)
- [ ] **Support more watches** (other 390 / 416 / 454 px round AMOLED models)

## Data sources

- Elevation: AWS Terrain Tiles (Mapzen terrarium; SRTM and other public sources)
- Roads, rivers, forests, places: © OpenStreetMap contributors, ODbL
  (https://www.openstreetmap.org/copyright)
