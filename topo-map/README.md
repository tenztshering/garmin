# Topo: offline topographic map for the Forerunner 165

Contours, shaded relief, rivers, roads, forests and place names for a 16 x 16 km area
around Thimphu (centre 2 km south of the Clock Tower), centred on your GPS position.

- UP / DOWN: zoom (1, 2, 5, 10 km across)
- Hold UP: settings (battery saver: GPS only, screen sleeps normally)
- BACK: exit

## Rebuild the map data

    python3 -I tools/make_topo.py [lat lon half_size_m contour_interval_m]
    python3 -I tools/preview.py preview.png [span_m [centre_x_m centre_y_m]]

`make_topo.py` writes `resources/data/*` (4 km vector tiles + `topo.json` labels/trees/places),
`resources/shade/*`, `source/VectorTiles.mc` and `source/ShadeTiles.mc`.
Current map: `python3 -I tools/make_topo.py 27.45471 89.6393 8000 20`
Downloads are cached in `$TOPO_CACHE` (default `.topo-cache/`).

## Data sources

- Elevation: AWS Terrain Tiles (Mapzen terrarium; SRTM and other public sources)
- Roads, rivers, forests, places: © OpenStreetMap contributors, ODbL (https://www.openstreetmap.org/copyright)
