#!/usr/bin/env python3
"""Generate the three table cards.

A card is seen at roughly 30 pixels tall on the table, so the mark on it has to
survive being tiny: one bold shape, one colour, high contrast. Detailed artwork
turns to mush at that size, which is why the beautiful sigil renders on disk are
the wrong asset for this job.

    python tools/gen_cards.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated")
os.makedirs(OUT, exist_ok=True)

W, H = 512, 768
CORNER = 34


def stock(seed, base, edge):
    """Worn card stock: grain, blotching, darkened edges, rounded corners."""
    rng = np.random.default_rng(seed)
    grain = rng.random((H // 4, W // 4)).astype(np.float32)
    grain = np.asarray(
        Image.fromarray((grain * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    ).astype(np.float32) / 255.0
    blot = rng.random((H // 26, W // 26)).astype(np.float32)
    blot = np.asarray(
        Image.fromarray((blot * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    ).astype(np.float32) / 255.0

    v = 0.80 + 0.26 * (blot - 0.5) + 0.10 * (grain - 0.5)
    yy = np.linspace(-1, 1, H, dtype=np.float32)[:, None]
    xx = np.linspace(-1, 1, W, dtype=np.float32)[None, :]
    edge_fall = np.clip(1.25 - (xx ** 2 + yy ** 2) * 0.55, 0.55, 1.15)
    v *= edge_fall

    rgb = np.dstack([v * base[0], v * base[1], v * base[2]])

    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, W - 3, H - 3], CORNER, outline=edge, width=6)
    d.rounded_rectangle([16, 16, W - 17, H - 17], CORNER - 10, outline=edge, width=2)

    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], CORNER, fill=255)
    img.putalpha(mask)
    return img


def sigil_signal(d, cx, cy, r, col):
    """SIGNAL: a closed ring with an upward spike. Reads as 'intact'."""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=16)
    d.ellipse([cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55],
              outline=col, width=9)
    d.line([cx, cy - r * 1.42, cx, cy + r * 1.42], fill=col, width=16)
    for k in range(6):
        a = math.tau * k / 6.0
        d.line([cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55,
                cx + math.cos(a) * r, cy + math.sin(a) * r], fill=col, width=8)
    d.polygon([(cx, cy - r * 1.72), (cx - r * 0.26, cy - r * 1.30),
               (cx + r * 0.26, cy - r * 1.30)], fill=col)


def sigil_noise(d, cx, cy, r, col):
    """NOISE: the same ring, broken, with the spike snapped and falling."""
    for k in range(5):
        a0 = math.tau * k / 5.0 + 0.22
        a1 = a0 + math.tau / 5.0 - 0.52
        d.arc([cx - r, cy - r, cx + r, cy + r],
              math.degrees(a0), math.degrees(a1), fill=col, width=16)
    d.line([cx - r * 0.80, cy - r * 0.80, cx + r * 0.80, cy + r * 0.80],
           fill=col, width=15)
    d.line([cx + r * 0.80, cy - r * 0.80, cx - r * 0.80, cy + r * 0.80],
           fill=col, width=15)
    d.polygon([(cx + r * 0.30, cy - r * 1.62), (cx + r * 0.02, cy - r * 1.22),
               (cx + r * 0.56, cy - r * 1.16)], fill=col)


def sigil_back(d, cx, cy, r, col):
    """The face-down mark. Seen most often, so it is the simplest of the three."""
    d.ellipse([cx - r * 1.15, cy - r * 1.15, cx + r * 1.15, cy + r * 1.15],
              outline=col, width=10)
    for k in range(12):
        a = math.tau * k / 12.0
        d.line([cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62,
                cx + math.cos(a) * r * 1.05, cy + math.sin(a) * r * 1.05],
               fill=col, width=7)
    d.regular_polygon((cx, cy, int(r * 0.60)), 6, rotation=90, outline=col, width=12)


def build(name, base, edge, glyph, glyph_col, seed):
    card = stock(seed, base, edge)
    # Draw the mark on its own layer so it can be bloomed before compositing.
    mark = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(mark)
    glyph(d, W // 2, int(H * 0.47), int(W * 0.27), glyph_col)
    glow = mark.filter(ImageFilter.GaussianBlur(18))
    card = Image.alpha_composite(card, glow)
    card = Image.alpha_composite(card, mark)

    # Scuff the surface so it does not look printed today.
    rng = np.random.default_rng(seed + 7)
    d2 = ImageDraw.Draw(card)
    for _ in range(26):
        x0, y0 = rng.integers(20, W - 20), rng.integers(20, H - 20)
        d2.line([x0, y0, x0 + rng.integers(-70, 70), y0 + rng.integers(-70, 70)],
                fill=(0, 0, 0, int(rng.integers(20, 60))), width=int(rng.integers(1, 3)))

    path = os.path.join(OUT, name)
    card.save(path)
    print("  %-20s %s" % (name, card.size))


print("generating cards")
# SIGNAL: hemp green on pale stock. NOISE: maroon on the same stock, so the
# difference is the mark and the colour, not the paper.
build("card_signal.png", (0.66, 0.63, 0.53), (44, 36, 30), sigil_signal, (128, 168, 84, 255), 3)
build("card_noise.png", (0.63, 0.57, 0.51), (44, 32, 30), sigil_noise, (196, 46, 44, 255), 11)
build("card_back.png", (0.20, 0.15, 0.14), (58, 30, 34), sigil_back, (150, 44, 52, 255), 23)
print("done ->", os.path.normpath(OUT))
