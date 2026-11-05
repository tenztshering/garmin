#!/usr/bin/env python3
"""Bake the Ridge overlay: halftone fade for the time digits + mountain line art.

The watch draws the time in solid white, then this bitmap on top:
  - a black mask with round holes that shrink towards the bottom, so the lower half of the
    digits dissolves into dots (halftone);
  - a black-filled mountain silhouette with teal ridge lines, in front of the digits.
Everything else is transparent. Geometry must match source/RidgeView.mc (TIME_Y etc.).

Usage: python3 tools/render.py   ->  resources/drawables/overlay.png, launcher_icon.png
"""
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "resources", "drawables")
S = 4
W = 390
TEAL = (64, 184, 176, 255)     # on the RGB565 grid after rounding: close enough, no dither
BLACK = (0, 0, 0, 255)

OX, OY, OW, OH = 20, 140, 350, 120      # overlay bitmap placement on screen
HALF_Y0, HALF_Y1 = 148, 216             # halftone: full digit at Y0, gone by Y1
CELL = 5.0                              # halftone grid pitch (px)
rng = np.random.default_rng(11)


def P(x, y):
    return ((x - OX) * S, (y - OY) * S)


def ridge(x0, y0, x1, y1, rough, depth):
    """Midpoint-displacement ridge line from (x0,y0) to (x1,y1)."""
    pts = [(x0, y0), (x1, y1)]
    for _ in range(depth):
        out = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            mx, my = (ax + bx) / 2, (ay + by) / 2 + rng.normal(0, rough * abs(bx - ax) / 60)
            out += [(mx, my), (bx, by)]
        pts = out
        rough *= 0.55
    return pts


def overlay():
    img = Image.new("RGBA", (OW * S, OH * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # halftone mask: opaque black with holes shrinking downwards
    m = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(m)
    y = HALF_Y0
    row = 0
    while y < OY + OH:
        f = np.clip((y - HALF_Y0) / (HALF_Y1 - HALF_Y0), 0, 1)
        r = CELL * 0.72 * (1 - f) ** 0.9            # hole radius
        x = OX + (CELL / 2 if row % 2 else 0)
        while x < OX + OW:
            if r > 0.35:
                md.ellipse([*P(x - r, y - r), *P(x + r, y + r)], fill=255)
            x += CELL
        y += CELL * 0.866
        row += 1
    mask = np.asarray(m) < 128                      # True = cover (black)
    top = int((HALF_Y0 - CELL / 2 - OY) * S)
    a = np.zeros((OH * S, OW * S, 4), np.uint8)
    a[top:][mask[top:]] = BLACK
    img = Image.fromarray(a, "RGBA")
    d = ImageDraw.Draw(img)

    # mountains: main massif, a lower peak on the left, a shoulder on the right
    sky = (ridge(34, 246, 120, 222, 8, 5) + ridge(120, 222, 160, 204, 8, 4)[1:]
           + ridge(160, 204, 212, 166, 10, 5)[1:] + ridge(212, 166, 256, 196, 9, 5)[1:]
           + ridge(256, 196, 298, 206, 7, 4)[1:] + ridge(298, 206, 358, 244, 8, 5)[1:])
    poly = [P(x, y) for x, y in sky] + [P(358, OY + OH), P(34, OY + OH)]
    d.polygon(poly, fill=BLACK)
    w = int(2.0 * S)
    d.line([P(x, y) for x, y in sky], fill=TEAL, width=w, joint="curve")
    # inner ridge lines (spurs) running down from the peaks
    for (x0, y0, x1, y1, r) in [(212, 166, 200, 236, 10), (212, 166, 240, 220, 8), (160, 204, 148, 250, 8),
                                (256, 196, 270, 250, 8), (120, 222, 104, 254, 6), (298, 206, 310, 252, 6),
                                (204, 200, 178, 228, 6), (228, 186, 250, 232, 6)]:
        line = ridge(x0, y0, x1, y1, r, 4)
        d.line([P(x, y) for x, y in line], fill=TEAL, width=int(1.6 * S), joint="curve")

    img = img.resize((OW, OH), Image.Resampling.LANCZOS)
    a = np.asarray(img).copy()
    # keep the soft alpha: the FR165 blends it, so lines and dots stay anti-aliased
    a[..., 3] = np.where(a[..., 3] < 8, 0, a[..., 3])
    rgb = a[..., :3].astype(np.float32)
    a[..., :3] = (np.round(rgb / [8, 4, 8]) * [8, 4, 8]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def main():
    os.makedirs(RES, exist_ok=True)
    ov = overlay()
    ov.save(os.path.join(RES, "overlay.png"))
    # preview + launcher icon: overlay on white digits
    from PIL import ImageFont
    prev = Image.new("RGB", (W, W), (0, 0, 0))
    try:
        f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Narrow Bold.ttf", 132)
    except OSError:
        f = ImageFont.load_default()
    ImageDraw.Draw(prev).text((195, 168), "08:36", font=f, fill=(255, 255, 255), anchor="mm")
    prev.paste(ov, (OX, OY), ov)
    prev.save(os.path.join(HERE, "..", "build", "preview.png"))
    prev.crop((95, 95, 295, 295)).resize((54, 54), Image.Resampling.LANCZOS).save(
        os.path.join(RES, "launcher_icon.png"))
    print("wrote resources/drawables/overlay.png, build/preview.png")


if __name__ == "__main__":
    main()
