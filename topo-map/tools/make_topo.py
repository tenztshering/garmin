#!/usr/bin/env python3
"""Build resources/data/topo.json: contours, rivers, roads and peaks around a centre point.

Elevation: AWS Terrain Tiles (terrarium PNGs, public, no account).
Rivers/roads/peaks: OpenStreetMap via the public Overpass API.

All coordinates are integer metres east/north of the centre, using the same flat-earth
conversion the watch uses (TopoView.mc), so the two must stay in sync.

Usage: python3 -I tools/make_topo.py [lat lon half_size_m interval_m]
Downloads are cached in the directory given by $TOPO_CACHE (default: ./.topo-cache).
"""
import io, json, math, os, sys, urllib.request, urllib.parse
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

LAT0, LON0 = 27.4728, 89.6393      # Thimphu
HALF = 5000                          # metres from centre to edge
INTERVAL = 20                        # contour interval (m); every 5th is an index contour
ZOOM = 13                            # terrain tile zoom (~17 m/px here)
SIMPLIFY = 10.0                      # Douglas-Peucker tolerance (m)

if len(sys.argv) == 5:
    LAT0, LON0, HALF, INTERVAL = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "resources", "data", "topo.json")
CACHE = os.environ.get("TOPO_CACHE", os.path.join(HERE, "..", ".topo-cache"))
os.makedirs(CACHE, exist_ok=True)
UA = {"User-Agent": "topo-map-builder/1.0"}

KX = 111320.0 * math.cos(math.radians(LAT0))   # metres per degree of longitude
KY = 110540.0                                   # metres per degree of latitude

def to_m(lat, lon):
    return (lon - LON0) * KX, (lat - LAT0) * KY

def fetch(url, name, data=None):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        req = urllib.request.Request(url, data=data, headers=UA)
        with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
            f.write(r.read())
    with open(path, "rb") as f:
        return f.read()

# ---------------------------------------------------------------- elevation grid

def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y

def elevation_grid():
    dlat, dlon = HALF / KY * 1.15, HALF / KX * 1.15
    x0, y0 = tile_xy(LAT0 + dlat, LON0 - dlon, ZOOM)
    x1, y1 = tile_xy(LAT0 - dlat, LON0 + dlon, ZOOM)
    tx = range(int(x0), int(x1) + 1)
    ty = range(int(y0), int(y1) + 1)
    rows = []
    for y in ty:
        row = []
        for x in tx:
            png = fetch(f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{ZOOM}/{x}/{y}.png",
                        f"t{ZOOM}_{x}_{y}.png")
            a = np.asarray(Image.open(io.BytesIO(png)).convert("RGB"), dtype=np.float64)
            row.append(a[:, :, 0] * 256 + a[:, :, 1] + a[:, :, 2] / 256 - 32768)
        rows.append(np.hstack(row))
    z = np.vstack(rows)
    global MOSAIC
    MOSAIC = (z, tx[0], ty[0])
    n = 2 ** ZOOM
    px = (tx[0] + (np.arange(z.shape[1]) + 0.5) / 256) / n * 360 - 180
    py = ty[0] + (np.arange(z.shape[0]) + 0.5) / 256
    lat = np.degrees(np.arctan(np.sinh(math.pi * (1 - 2 * py / n))))
    lon2, lat2 = np.meshgrid(px, lat)
    return (lon2 - LON0) * KX, (lat2 - LAT0) * KY, z

# ---------------------------------------------------------------- geometry helpers

def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0]), np.array(pts[-1])
    ab = b - a
    nab = np.hypot(*ab)
    arr = np.array(pts[1:-1])
    if nab == 0:
        d = np.hypot(*(arr - a).T)
    else:
        d = np.abs(ab[0] * (arr[:, 1] - a[1]) - ab[1] * (arr[:, 0] - a[0])) / nab
    i = int(np.argmax(d))
    if d[i] > eps:
        return rdp(pts[: i + 2], eps)[:-1] + rdp(pts[i + 1 :], eps)
    return [pts[0], pts[-1]]

def clip(pts):
    """Split a polyline into the runs that lie inside the map square."""
    runs, cur = [], []
    for x, y in pts:
        if abs(x) <= HALF and abs(y) <= HALF:
            cur.append((x, y))
        elif cur:
            runs.append(cur); cur = []
    if cur:
        runs.append(cur)
    return [r for r in runs if len(r) >= 2]

CHUNK = 16   # points per stored piece, so the watch can skip pieces that are off screen

def packs(kind, pts):
    """Split a polyline into short overlapping pieces and pack each one."""
    out = []
    for i in range(0, len(pts) - 1, CHUNK - 1):
        piece = pts[i : i + CHUNK]
        if len(piece) >= 2:
            out.append(pack(kind, piece))
    return out

def pack(kind, pts):
    """[kind, minx, miny, maxx, maxy, x0, y0, x1, y1, ...] with integer metres."""
    p = [(int(round(x)), int(round(y))) for x, y in pts]
    xs, ys = [q[0] for q in p], [q[1] for q in p]
    return [kind, min(xs), min(ys), max(xs), max(ys)] + [v for q in p for v in q]

# ---------------------------------------------------------------- layers

KIND_CONTOUR, KIND_INDEX, KIND_WATER, KIND_ROAD, KIND_TRACK, KIND_STREET = 0, 1, 2, 3, 4, 5

LABEL_EVERY = 1500   # metres between elevation labels along an index contour
LABEL_GAP = 500      # minimum distance between any two labels

def place_labels(run, level):
    """Labels spaced along a line: [x, y, elevation, angle] (degrees counter-clockwise, kept upright)."""
    out, walked = [], 0.0
    target = LABEL_EVERY / 2
    for i in range(len(run) - 1):
        (xa, ya), (xb, yb) = run[i], run[i + 1]
        seg = math.hypot(xb - xa, yb - ya)
        while seg > 0 and walked + seg >= target:
            f = (target - walked) / seg
            ang = math.degrees(math.atan2(yb - ya, xb - xa))
            if ang > 90: ang -= 180
            if ang < -90: ang += 180
            out.append([int(xa + (xb - xa) * f), int(ya + (yb - ya) * f), level, int(round(ang))])
            target += LABEL_EVERY
        walked += seg
    return out

def contours():
    X, Y, Z = elevation_grid()
    lo = math.ceil(Z.min() / INTERVAL) * INTERVAL
    levels = np.arange(lo, Z.max(), INTERVAL)
    cs = plt.contour(X, Y, Z, levels=levels)
    lines, labels = [], []
    for level, segs in zip(cs.levels, cs.allsegs):
        index = int(level) % (INTERVAL * 5) == 0
        for seg in segs:
            for run in clip([tuple(p) for p in seg]):
                run = rdp(run, SIMPLIFY)
                if len(run) < 2:
                    continue
                length = sum(math.hypot(run[i+1][0]-run[i][0], run[i+1][1]-run[i][1]) for i in range(len(run)-1))
                if length < 150:
                    continue
                lines.extend(packs(KIND_INDEX if index else KIND_CONTOUR, run))
                if index and length > 800:
                    labels.extend(place_labels(run, int(level)))
    # keep labels at least LABEL_GAP apart so they never crowd
    kept = []
    for l in labels:
        if all(math.hypot(l[0] - k[0], l[1] - k[1]) >= LABEL_GAP for k in kept):
            kept.append(l)
    return lines, kept

def overpass(q, name):
    raw = fetch("https://overpass-api.de/api/interpreter", name,
                data=urllib.parse.urlencode({"data": q}).encode())
    return json.loads(raw)["elements"]

def bbox_str():
    s, w = LAT0 - HALF / KY, LON0 - HALF / KX
    n, e = LAT0 + HALF / KY, LON0 + HALF / KX
    return f"{s:.5f},{w:.5f},{n:.5f},{e:.5f}"

def osm():
    bbox = bbox_str()
    q = f"""[out:json][timeout:90];
(
  way["waterway"~"^(river|stream)$"]({bbox});
  way["highway"~"^(trunk|primary|secondary|tertiary|unclassified|track|path|footway)$"]({bbox});
);
out geom;"""
    lines = []
    for el in overpass(q, f"osm_{bbox}.json"):
        tags = el.get("tags", {})
        if "waterway" in tags:
            kind = KIND_WATER
        elif tags.get("highway") in ("track", "path", "footway"):
            kind = KIND_TRACK
        elif tags.get("highway") in ("trunk", "primary", "secondary"):
            kind = KIND_ROAD
        else:
            kind = KIND_STREET
        pts = [to_m(g["lat"], g["lon"]) for g in el.get("geometry", [])]
        for run in clip(pts):
            run = rdp(run, SIMPLIFY)
            if len(run) >= 2:
                lines.extend(packs(kind, run))
    return lines

def join_rings(ways):
    """Chain open ways (lists of points) into closed rings by matching end points."""
    rings, ways = [], [w[:] for w in ways if len(w) >= 2]
    while ways:
        ring = ways.pop(0)
        grown = True
        while ring[0] != ring[-1] and grown:
            grown = False
            for i, w in enumerate(ways):
                if w[0] == ring[-1]:   ring += w[1:]
                elif w[-1] == ring[-1]: ring += w[::-1][1:]
                elif w[-1] == ring[0]:  ring = w[:-1] + ring
                elif w[0] == ring[0]:   ring = w[::-1][:-1] + ring
                else: continue
                ways.pop(i); grown = True
                break
        if len(ring) >= 4:
            rings.append(ring)
    return rings

TREE_SPACING = 420   # metres between tree icons inside forest areas

def forest_and_places():
    from matplotlib.path import Path
    bbox = bbox_str()
    q = f"""[out:json][timeout:120];
(
  way["landuse"="forest"]({bbox});
  way["natural"="wood"]({bbox});
  relation["landuse"="forest"]({bbox});
  relation["natural"="wood"]({bbox});
  node["place"~"^(town|village|suburb|hamlet|neighbourhood)$"]({bbox});
);
out geom;"""
    els = overpass(q, f"osm_forest_{bbox}.json")
    outers, inners, places = [], [], []
    for el in els:
        if el["type"] == "node":
            name = el.get("tags", {}).get("name:en") or el.get("tags", {}).get("name")
            if name and name.isascii():
                x, y = to_m(el["lat"], el["lon"])
                if abs(x) < HALF and abs(y) < HALF:
                    places.append([int(x), int(y), name])
        elif el["type"] == "way":
            outers.append([(g["lat"], g["lon"]) for g in el.get("geometry", [])])
        else:
            for role, bucket in (("outer", outers), ("inner", inners)):
                ws = [[(g["lat"], g["lon"]) for g in m["geometry"]]
                      for m in el.get("members", []) if m.get("role") == role and "geometry" in m]
                bucket.extend(join_rings(ws))
    to_path = lambda ring: Path([to_m(a, b) for a, b in ring])
    outer_paths = [to_path(r) for r in outers if len(r) >= 4]
    inner_paths = [to_path(r) for r in inners if len(r) >= 4]
    rng = np.random.default_rng(7)
    g = np.arange(-HALF + TREE_SPACING / 2, HALF, TREE_SPACING)
    gx, gy = np.meshgrid(g, g)
    pts = np.column_stack([gx.ravel(), gy.ravel()]) + rng.uniform(-70, 70, (gx.size, 2))
    inside = np.zeros(len(pts), bool)
    for p in outer_paths:
        inside |= p.contains_points(pts)
    for p in inner_paths:
        inside &= ~p.contains_points(pts)
    # small clusters of 1-3 trees around each sample, like hand-placed map symbols
    trees = []
    for x, y in pts[inside]:
        for _ in range(int(rng.integers(1, 3))):
            tx, ty = x + rng.uniform(-45, 45), y + rng.uniform(-45, 45)
            if abs(tx) < HALF and abs(ty) < HALF:
                trees.append((float(tx), float(ty)))
    return trees, places

# ---------------------------------------------------------------- shaded relief
# Hill-shading as paper-tinted grey tones, saved as palette PNG tiles plus one overview.
# The colours are part of the watch's 16-colour map palette (TopoView.mc), so keep them in sync.

SHADE_COLOURS = ["F4F3EF", "E9E8E3", "DDDBD4", "D0CDC5", "C2BEB5", "B3AEA4"]   # lit, flat(paper), 4 shadows
SHADE_TILE = 128          # px per tile
SHADE_M_PER_PX = 13.0     # target shading resolution
SHADE_OVERVIEW = 256      # px, used at the 5 and 10 km zooms

def sample_dem(mx, my):
    """Bilinear elevation at map metres (arrays), from the terrain tile mosaic."""
    z, tx0, ty0 = MOSAIC
    n = 2 ** ZOOM
    lat = LAT0 + my / KY
    lon = LON0 + mx / KX
    fx = ((lon + 180) / 360 * n - tx0) * 256 - 0.5
    fy = ((1 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2 * n - ty0) * 256 - 0.5
    x0 = np.clip(np.floor(fx).astype(int), 0, z.shape[1] - 2)
    y0 = np.clip(np.floor(fy).astype(int), 0, z.shape[0] - 2)
    ax, ay = np.clip(fx - x0, 0, 1), np.clip(fy - y0, 0, 1)
    top = z[y0, x0] * (1 - ax) + z[y0, x0 + 1] * ax
    bot = z[y0 + 1, x0] * (1 - ax) + z[y0 + 1, x0 + 1] * ax
    return top * (1 - ay) + bot * ay

def hillshade(size):
    """size x size shade levels (0..5) covering the map square, row 0 = north edge."""
    res = 2 * HALF / size
    c = -HALF + (np.arange(size) + 0.5) * res
    mx, my = np.meshgrid(c, c[::-1])
    z = sample_dem(mx, my)
    dzdy_rows, dzdx = np.gradient(z, res)
    dzdy = -dzdy_rows                         # rows run north -> south
    norm = np.sqrt(dzdx ** 2 + dzdy ** 2 + 1)
    # light from the north-west, 45 degrees up: L = (-0.5, 0.5, 0.707)
    hs = (dzdx * 0.5 - dzdy * 0.5 + 0.707) / norm
    levels = np.digitize(hs, [0.24, 0.38, 0.5, 0.62, 0.8])   # 0 darkest .. 5 lit
    return (5 - levels).astype(np.uint8)                     # index into SHADE_COLOURS

def save_palette_png(levels, path):
    img = Image.fromarray(levels, mode="P")
    pal = []
    for hexc in SHADE_COLOURS:
        pal += [int(hexc[i:i + 2], 16) for i in (0, 2, 4)]
    img.putpalette(pal + [0] * (768 - len(pal)))
    img.convert("RGB").save(path, optimize=True)

def shaded_relief():
    root = os.path.join(HERE, "..")
    out_dir = os.path.join(root, "resources", "shade")
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, f))
    entries, ids = [], []
    full = hillshade(SHADE_TILE * SHADE_TILES)  # SHADE_TILES set in main from the map size
    for r in range(SHADE_TILES):
        for col in range(SHADE_TILES):
            name = f"shade_{r}_{col}"
            tile = full[r * SHADE_TILE:(r + 1) * SHADE_TILE, col * SHADE_TILE:(col + 1) * SHADE_TILE]
            save_palette_png(tile, os.path.join(out_dir, name + ".png"))
            entries.append(name); ids.append(f"Rez.Drawables.{name}")
    save_palette_png(hillshade(SHADE_OVERVIEW), os.path.join(out_dir, "shade_overview.png"))
    entries.append("shade_overview")
    with open(os.path.join(out_dir, "shade.xml"), "w") as f:
        f.write("<drawables>\n")
        for e in entries:
            # no palette: scaled drawing on the watch needs native-colour source bitmaps
            f.write(f'    <bitmap id="{e}" filename="{e}.png" dithering="none" automaticPalette="false"/>\n')
        f.write("</drawables>\n")
    with open(os.path.join(root, "source", "ShadeTiles.mc"), "w") as f:
        f.write("// Generated by tools/make_topo.py. Do not edit.\n")
        f.write("import Toybox.Lang;\n\nmodule ShadeTiles {\n")
        f.write(f"    const TILE = {SHADE_TILE};\n    const PER_SIDE = {SHADE_TILES};\n")
        f.write(f"    const OVERVIEW = {SHADE_OVERVIEW};\n\n")
        f.write("    // Row-major from the north-west corner.\n")
        f.write("    function tiles() as Array<ResourceId> {\n        return [\n")
        f.write(",\n".join("            " + i for i in ids))
        f.write("\n        ];\n    }\n}\n")
    print(f"shade: {len(entries)} bitmaps, {sum(os.path.getsize(os.path.join(out_dir, e + '.png')) for e in entries)} bytes")

# Compact encoding read by TopoView.decode(): each value is 12 bits (0..4095 across the map,
# ~2.4 m steps) written as two characters, 6 bits each, as byte 35+v ('\\' is swapped for 'c').
def enc(v):
    q = max(0, min(4095, int(round((v + HALF) / (2 * HALF) * 4095))))
    out = ""
    for six in (q >> 6, q & 63):
        b = 35 + six
        out += "c" if b == 92 else chr(b)
    return out

def main():
    global SHADE_TILES
    SHADE_TILES = max(1, round(2 * HALF / (SHADE_TILE * SHADE_M_PER_PX)))   # tiles per side
    c_lines, labels = contours()
    shaded_relief()
    o_lines = osm()
    trees, places = forest_and_places()
    write_vector_tiles(c_lines + o_lines)
    meta = {"h": HALF, "lat": LAT0, "lon": LON0,
            "t": labels, "tr": "".join(enc(x) + enc(y) for x, y in trees), "pl": places}
    with open(OUT, "w") as f:
        json.dump(meta, f, separators=(",", ":"))
    print(f"labels={len(labels)} trees={len(trees)} places={len(places)} meta_bytes={os.path.getsize(OUT)}")

# Vector data is split into VEC_TILE_M square tiles so the watch only loads what is on screen
# (one big file runs out of memory). Each tile has a "major" file (index contours, water, roads,
# tracks, streets) and a "minor" file (20 m contours, only drawn when zoomed in).
VEC_TILE_M = 4000

def write_vector_tiles(lines):
    root = os.path.join(HERE, "..")
    n = max(1, round(2 * HALF / VEC_TILE_M))
    tile_m = 2 * HALF / n
    q = lambda v: max(0, min(4095, int(round((v + HALF) / (2 * HALF) * 4095))))
    tiles = {}
    for l in lines:
        cx, cy = (l[1] + l[3]) / 2, (l[2] + l[4]) / 2
        col = min(n - 1, max(0, int((cx + HALF) // tile_m)))
        row = min(n - 1, max(0, int((HALF - cy) // tile_m)))
        part = "minor" if l[0] == KIND_CONTOUR else "major"
        t = tiles.setdefault((row, col, part), {"k": [[] for _ in range(6)], "b": [[] for _ in range(6)]})
        t["k"][l[0]].append("".join(enc(v) for v in l[5:]))
        t["b"][l[0]] += [q(l[1]) << 12 | q(l[2]), q(l[3]) << 12 | q(l[4])]
    data_dir = os.path.join(root, "resources", "data")
    for f in os.listdir(data_dir):
        if f.startswith("v_"):
            os.remove(os.path.join(data_dir, f))
    entries = ['    <jsonData id="Topo" filename="topo.json"/>']
    ids = {"major": [], "minor": []}
    biggest = 0
    for r in range(n):
        for c in range(n):
            for part in ("major", "minor"):
                name = f"v_{r}_{c}_{part}"
                t = tiles.get((r, c, part), {"k": [[] for _ in range(6)], "b": [[] for _ in range(6)]})
                path = os.path.join(data_dir, name + ".json")
                with open(path, "w") as f:
                    json.dump(t, f, separators=(",", ":"))
                biggest = max(biggest, os.path.getsize(path))
                entries.append(f'    <jsonData id="{name}" filename="{name}.json"/>')
                ids[part].append(f"Rez.JsonData.{name}")
    with open(os.path.join(data_dir, "data.xml"), "w") as f:
        f.write("<resources>\n" + "\n".join(entries) + "\n</resources>\n")
    with open(os.path.join(root, "source", "VectorTiles.mc"), "w") as f:
        f.write("// Generated by tools/make_topo.py. Do not edit.\n")
        f.write("import Toybox.Lang;\n\nmodule VectorTiles {\n")
        f.write(f"    const PER_SIDE = {n};\n\n    // Row-major from the north-west corner.\n")
        for part in ("major", "minor"):
            f.write(f"    function {part}() as Array<ResourceId> {{\n        return [\n")
            f.write(",\n".join("            " + i for i in ids[part]))
            f.write("\n        ];\n    }\n\n")
        f.write("}\n")
    print(f"vector tiles: {n}x{n}, biggest file {biggest} bytes")

if __name__ == "__main__":
    main()
