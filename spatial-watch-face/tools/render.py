#!/usr/bin/env python3
"""Bake the 12 hour scenes for the Spatial face.

The hour is drawn as two giant geometric digits (01..12): the first is frosted glass, the
second solid orange, so "10" is a glass pill over an orange disc. The watch can't blur at
runtime, so the glass is pre-rendered here (blur what is behind, lift it towards white).
Hands, arcs and ticks are drawn live by source/SpatialView.mc.

Usage: python3 tools/render.py   ->  resources/drawables/hour01.png .. hour12.png, launcher_icon.png
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "resources", "drawables")
S = 3                          # supersampling
W = 390

# Flat colours sit exactly on the RGB565 grid (multiples of 8/4/8), so they need no dither.
OLIVE_DARK = (40, 48, 40)
OLIVE_LIGHT = (56, 68, 56)
ORANGE = (248, 108, 40)
GLASS_TINT = (236, 238, 230)
RIM = 0.30                     # strength of the 1 px light edge on the glass

BOX_W, BOX_H = 150, 270        # one digit's box
BOXES = [(52, 60), (180, 60)]  # top-left of digit 1 and digit 2 (they overlap a little)
SINGLE = 1.18                  # single-digit hours are drawn alone, this much bigger, centred
T = 60                         # stroke thickness of the digits


# ---------------------------------------------------------------- digit shapes
# Each digit: list of ("line", x0, y0, x1, y1) / ("arc", cx, cy, r, a0, a1) / ("disc", cx, cy, r)
# / ("pill", x0, y0, x1, y1, width) in box coordinates (0..150, 0..270), y down, degrees
# clockwise from 3 o'clock (PIL convention).
DIGITS = {
    "0": [("disc", 75, 135, 106)],
    "1": [("pill", 75, 58, 75, 212, 116)],
    "1s": [("line", 26, 80, 66, 44), ("pill", 75, 58, 75, 212, 116)],   # single "1": glass flag + pill
    "2": [("arc", 75, 82, 45, 180, 20), ("line", 117, 98, 34, 238), ("line", 34, 238, 120, 238)],
    "3": [("arc", 75, 78, 44, 170, 90), ("arc", 75, 186, 50, 270, 190)],
    "4": [("line", 102, 32, 32, 172), ("line", 32, 172, 128, 172), ("line", 102, 32, 102, 238)],
    "5": [("line", 120, 32, 38, 32), ("line", 38, 32, 38, 118), ("arc", 72, 178, 54, 215, 150)],
    "6": [("arc", 75, 184, 50, 0, 360), ("line", 112, 34, 30, 176)],
    "7": [("line", 30, 32, 120, 32), ("line", 120, 32, 58, 238)],
    "8": [("arc", 75, 76, 40, 0, 360), ("arc", 75, 186, 50, 0, 360)],
    "9": [("arc", 75, 86, 50, 0, 360), ("line", 120, 94, 40, 238)],
}


def px(v):
    return int(round(v * S))


def digit_mask(ch, ox, oy, k=1.0, parts=slice(None)):
    """Mask of digit ch (or a slice of its shapes), box at (ox, oy), scaled by k."""
    m = Image.new("L", (W * S, W * S), 0)
    d = ImageDraw.Draw(m)
    def P(o, v):              # box coordinate -> screen, scaled about the box origin
        return px(o + v * k)

    def cap(x, y, w):
        r = w * k / 2
        d.ellipse([px(ox + x * k - r), px(oy + y * k - r), px(ox + x * k + r), px(oy + y * k + r)], fill=255)

    for shape in DIGITS[ch][parts]:
        kind = shape[0]
        if kind == "disc":
            _, cx, cy, r = shape
            cap(cx, cy, 2 * r)
        elif kind in ("line", "pill"):
            x0, y0, x1, y1 = shape[1:5]
            w = shape[5] if kind == "pill" else T
            d.line([P(ox, x0), P(oy, y0), P(ox, x1), P(oy, y1)], fill=255, width=px(w * k))
            cap(x0, y0, w)
            cap(x1, y1, w)
        elif kind == "arc":
            _, cx, cy, r, a0, a1 = shape
            R = r + T / 2
            d.arc([P(ox, cx - R), P(oy, cy - R), P(ox, cx + R), P(oy, cy + R)],
                  a0, a1 if a1 != a0 else a0 + 360, fill=255, width=px(T * k))
            if (a1 - a0) % 360:
                for a in (a0, a1):
                    cap(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)), T)
    return m


def scene(hour):
    n = W * S
    img = Image.new("RGB", (n, n), OLIVE_DARK)
    ImageDraw.Draw(img).rectangle([0, 0, n // 2, n], fill=OLIVE_LIGHT)
    if hour >= 10:          # two digits: first is glass, second solid
        d1, d2 = f"{hour}"
        solid = digit_mask(d2, *BOXES[1])
        glass = digit_mask(d1, *BOXES[0])
    else:                   # one digit: its first stroke is glass, the rest solid
        ch = "1s" if hour == 1 else str(hour)
        o = (195 - BOX_W * SINGLE / 2, 195 - BOX_H * SINGLE / 2)
        solid = digit_mask(ch, *o, SINGLE, slice(1, None))
        glass = digit_mask(ch, *o, SINGLE, slice(0, 1))
    img.paste(Image.new("RGB", (n, n), ORANGE), (0, 0), solid)

    # frosted glass: blur whatever is behind it, lift towards white
    frost = img.filter(ImageFilter.GaussianBlur(px(16)))
    frost = Image.blend(frost, Image.new("RGB", (n, n), GLASS_TINT), 0.42)
    img.paste(frost, (0, 0), glass)
    # crisp light rim on the glass edge (~1 px on the watch)
    rim = Image.fromarray(np.asarray(glass) - np.asarray(glass.filter(ImageFilter.MinFilter(7))))
    img.paste(Image.new("RGB", (n, n), (255, 255, 255)), (0, 0), rim.point(lambda v: int(v * RIM)))

    img = img.resize((W, W), Image.Resampling.LANCZOS)
    a = np.asarray(img).astype(np.float32)
    # RGB565: ordered dither only inside the glass, where the blur gradient would band.
    # Everywhere else (flat fills, anti-aliased edges) round straight to the grid so it stays crisp.
    inside = np.asarray(glass.resize((W, W), Image.Resampling.BOX).filter(ImageFilter.MinFilter(3)))[..., None] > 250
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16 - 0.5
    t = np.tile(bayer, (W // 4 + 1, W // 4 + 1))[:W, :W, None] * inside
    step = np.array([8, 4, 8], np.float32)
    a = np.clip(np.round(a / step + t) * step, 0, 255)
    yy, xx = np.mgrid[0:W, 0:W]
    a[(xx - 194.5) ** 2 + (yy - 194.5) ** 2 > 195 ** 2] = 0
    return Image.fromarray(a.astype(np.uint8))


def main():
    os.makedirs(RES, exist_ok=True)
    for f in os.listdir(RES):
        if f == "scene.png":
            os.remove(os.path.join(RES, f))
    sheet = Image.new("RGB", (W * 4, W * 3))
    for h in range(1, 13):
        img = scene(h)
        img.save(os.path.join(RES, f"hour{h:02d}.png"))
        sheet.paste(img, (((h - 1) % 4) * W, ((h - 1) // 4) * W))
        if h == 10:
            img.resize((54, 54), Image.Resampling.LANCZOS).save(os.path.join(RES, "launcher_icon.png"))
    os.makedirs(os.path.join(HERE, "..", "build"), exist_ok=True)
    sheet.resize((W * 2, W * 3 // 2)).save(os.path.join(HERE, "..", "build", "sheet.png"))
    print("wrote resources/drawables/hour01..12.png, build/sheet.png")


if __name__ == "__main__":
    main()
