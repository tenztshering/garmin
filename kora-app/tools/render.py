#!/usr/bin/env python3
"""Bake the chorten watermark and launcher icon for Kora from tools/jangchub-chorten.png
(gold line art on transparent).

Watermark: the lines dimmed to ~42% on black, so the round count reads over it and few
AMOLED pixels are lit. Colours snapped to RGB565.

Usage: python3 tools/render.py  ->  resources/drawables/chorten.png, launcher_icon.png
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "resources", "drawables")
SRC = os.path.join(HERE, "jangchub-chorten.png")
HEIGHT = 280          # watermark height on the 390 px screen; must match KoraView.mc
DIM = 0.42


def on_black(img, gain):
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    # thin lines lose coverage when downscaled; lift it back so they stay visible
    cover = np.minimum(1.0, a[..., 3:] / 255.0 * 1.8)
    rgb = a[..., :3] * cover * gain
    return Image.fromarray(rgb.clip(0, 255).astype(np.uint8), "RGB")


def main():
    src = Image.open(SRC)
    src = src.crop(src.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox())  # trim margins (ignore faint stray pixels)
    w = round(src.width * HEIGHT / src.height)
    mark = on_black(src.resize((w, HEIGHT), Image.Resampling.LANCZOS), DIM)
    mark.point(lambda v: (v // 8) * 8).save(os.path.join(RES, "chorten.png"))

    # icon: full-strength gold, a little brighter so thin lines survive at 54 px
    side = src.height
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(src, ((side - src.width) // 2, 0), src)
    on_black(sq.resize((54, 54), Image.Resampling.LANCZOS), 1.6).save(os.path.join(RES, "launcher_icon.png"))
    print(f"wrote chorten.png ({w}x{HEIGHT}), launcher_icon.png")


if __name__ == "__main__":
    main()
