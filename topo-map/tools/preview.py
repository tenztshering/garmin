#!/usr/bin/env python3
"""Render resources/data/topo.json roughly the way TopoView.mc does, to check the look on a Mac.

Usage: python3 -I tools/preview.py out.png [span_m] [centre_x_m centre_y_m]
Keep the styles below in sync with TopoView.mc.
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "resources", "data")
D = json.load(open(os.path.join(DATA, "topo.json")))
# merge the vector tiles (make_topo.py splits lines into v_<row>_<col>_<major|minor>.json)
D["k"] = [[] for _ in range(6)]
for f in sorted(os.listdir(DATA)):
    if f.startswith("v_") and f.endswith(".json"):
        t = json.load(open(os.path.join(DATA, f)))
        for i in range(6):
            D["k"][i] += t["k"][i]
OUT = sys.argv[1]
SPAN = float(sys.argv[2]) if len(sys.argv) > 2 else 2000
CX, CY = (float(sys.argv[3]), float(sys.argv[4])) if len(sys.argv) > 4 else (0.0, 0.0)

W, SS = 390, 3                 # screen size, supersampling
H = D["h"]
U = 2 * H / 4095

PAPER = "#E9E8E3"
STYLE = {0: ("#B4885C", 1), 1: ("#8A5A2E", 1), 2: ("#3F63D6", 1), 4: ("#7E7D78", 1), 5: ("#7E7D78", 1), 3: ("#D2861A", 2)}
ORDER = [0, 1, 2, 4, 5, 3]

def dec(s, i):
    h, l = ord(s[i]), ord(s[i + 1])
    h, l = (92 if h == 99 else h), (92 if l == 99 else l)
    return (h - 35) * 64 + (l - 35)

def scr(mx, my):
    k = W * SS / SPAN
    return (W * SS / 2 + (mx - CX) * k, W * SS / 2 - (my - CY) * k)

# shaded relief underlay: assemble the tiles, crop the view, scale up smoothly (as the watch does)
SHADE_DIR = os.path.join(HERE, "..", "resources", "shade")
n_tiles = int(round(math.sqrt(len([f for f in os.listdir(SHADE_DIR) if f.startswith("shade_") and f[6].isdigit()]))))
tile_px = Image.open(os.path.join(SHADE_DIR, "shade_0_0.png")).width
mosaic = Image.new("RGB", (tile_px * n_tiles, tile_px * n_tiles))
for r in range(n_tiles):
    for col in range(n_tiles):
        mosaic.paste(Image.open(os.path.join(SHADE_DIR, f"shade_{r}_{col}.png")).convert("RGB"), (col * tile_px, r * tile_px))
mpp = 2 * H / mosaic.width                       # metres per shade pixel
box = ((CX - SPAN / 2 + H) / mpp, (H - (CY + SPAN / 2)) / mpp, (CX + SPAN / 2 + H) / mpp, (H - (CY - SPAN / 2)) / mpp)
img = mosaic.resize((W * SS, W * SS), Image.BILINEAR, box=box)
d = ImageDraw.Draw(img)
for kind in ORDER:
    col, pen = STYLE[kind]
    for s in D["k"][kind]:
        pts = [scr(dec(s, i) * U - H, dec(s, i + 2) * U - H) for i in range(0, len(s), 4)]
        d.line(pts, fill=col, width=pen * SS, joint="curve")

# trees: small two-tier pines
tr = D["tr"]
for i in range(0, len(tr), 4):
    x, y = scr(dec(tr, i) * U - H, dec(tr, i + 2) * U - H)
    s = 6 * SS
    d.rectangle([x - SS, y + s * 0.9, x + SS, y + s * 1.5], fill="#6B4A2B")
    d.polygon([(x - s, y + s), (x + s, y + s), (x, y - s * 0.2)], fill="#2F9E44", outline="#1E6B2E")
    d.polygon([(x - s * 0.75, y + s * 0.2), (x + s * 0.75, y + s * 0.2), (x, y - s * 1.2)], fill="#2F9E44", outline="#1E6B2E")

def font(px):
    for f in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/Library/Fonts/Arial Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, px)
    return ImageFont.load_default()

def clear(x, y):
    """Same rule as TopoView.clearOfOverlays: no text under the crosshair, north arrow or scale bar."""
    w = W * SS; c = w / 2
    if (x - c) ** 2 + (y - c) ** 2 < (w * 0.2) ** 2: return False
    if abs(x - w * 0.16) < w * 0.1 and abs(y - w * 0.27) < w * 0.1: return False
    if y > w * 0.78 and abs(x - c) < w * 0.25: return False
    return True

f_label = font(19 * SS)
for x, y, ele, ang in D["t"]:
    sx, sy = scr(x, y)
    if not (0 <= sx < W * SS and 0 <= sy < W * SS) or not clear(sx, sy):
        continue
    txt = str(ele)
    box = f_label.getbbox(txt)
    tw, th = box[2] - box[0] + 10 * SS, box[3] - box[1] + 10 * SS
    t = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ImageDraw.Draw(t).text((5 * SS - box[0], 5 * SS - box[1]), txt, font=f_label, fill="#151515",
                           stroke_width=2 * SS, stroke_fill=PAPER)   # halo knocks out the lines behind
    t = t.rotate(ang, expand=True, resample=Image.BICUBIC)
    img.paste(t, (int(sx - t.width / 2), int(sy - t.height / 2)), t)

f_place = font(17 * SS)
for x, y, name in D["pl"]:
    sx, sy = scr(x, y)
    if not clear(sx, sy):
        continue
    d.text((sx, sy), name, font=f_place, fill="#1A1A1A", anchor="mm", stroke_width=2 * SS, stroke_fill=PAPER)

# overlays: each drawn on a paper-coloured halo so it separates from the map
c = W * SS / 2
r = 0.07 * c
def cross(col, wid):
    d.ellipse([c - r, c - r, c + r, c + r], outline=col, width=wid)
    for a_, b_ in (((c - 2.1 * r, c), (c - r, c)), ((c + r, c), (c + 2.1 * r, c)),
                   ((c, c - 2.1 * r), (c, c - r)), ((c, c + r), (c, c + 2.1 * r))):
        d.line([a_, b_], fill=col, width=wid)
cross(PAPER, 7 * SS)
cross("#111111", 3 * SS)
d.ellipse([c - 2.5 * SS, c - 2.5 * SS, c + 2.5 * SS, c + 2.5 * SS], fill="#111111")

# north arrow at the top left
nx, ny, ns = 0.16 * W * SS, 0.27 * W * SS, 0.032 * W * SS
d.ellipse([nx - ns * 1.9, ny - ns * 1.9, nx + ns * 1.9, ny + ns * 1.9], fill=PAPER)
d.polygon([(nx, ny - ns * 1.5), (nx + ns, ny + ns), (nx, ny + ns * 0.35)], fill="#E0261B")
d.polygon([(nx, ny - ns * 1.5), (nx - ns, ny + ns), (nx, ny + ns * 0.35)], fill="#8E1710")

# scale bar
m = 500 if SPAN >= 2000 else 200
ln = W * SS * m / SPAN
sx0, sy0 = c - ln / 2, 0.87 * W * SS
d.rectangle([sx0 - 4 * SS, sy0 - 26 * SS, sx0 + ln + 4 * SS, sy0 + 5 * SS], fill=PAPER)
d.line([(sx0, sy0), (sx0 + ln, sy0)], fill="#111111", width=3 * SS)
d.line([(sx0, sy0 - 6 * SS), (sx0, sy0)], fill="#111111", width=2 * SS)
d.line([(sx0 + ln, sy0 - 6 * SS), (sx0 + ln, sy0)], fill="#111111", width=2 * SS)
d.text((c, sy0 - 14 * SS), f"{m} m", font=font(14 * SS), fill="#111111", anchor="mm")

img = img.resize((W, W), Image.LANCZOS)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).ellipse([0, 0, W - 1, W - 1], fill=255)
bg = Image.new("RGB", (W, W), "black")
bg.paste(img, (0, 0), mask)
bg.save(OUT)
print("wrote", OUT)
