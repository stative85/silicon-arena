#!/usr/bin/env python3
"""Generate the room textures procedurally.

No downloads, no asset pack. Concrete, grime, stains, panel seams and worn
metal, built from layered value noise and written as PNGs the Godot scene
loads. This is the difference between untextured boxes and a room.

    python tools/gen_textures.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(1771)


def value_noise(size, cells, seed):
    """Smooth tileable value noise at one frequency."""
    r = np.random.default_rng(seed)
    g = r.random((cells + 1, cells + 1)).astype(np.float32)
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    img = Image.fromarray((g * 255).astype(np.uint8), "L").resize(
        (size, size), Image.BICUBIC)
    return np.asarray(img).astype(np.float32) / 255.0


def fbm(size, seed, octaves=5, base=4):
    """Fractal noise: the thing that makes a flat colour look like a material."""
    out = np.zeros((size, size), dtype=np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(size, base * (2 ** o), seed + o * 977) * amp
        total += amp
        amp *= 0.5
    return out / total


def to_img(rgb):
    return Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB")


def concrete(size=1024, tint=(0.088, 0.074, 0.070), seed=11):
    """Poured concrete: broad blotching, fine grain, dark pitting, damp streaks."""
    base = fbm(size, seed, 6, 3)
    grain = fbm(size, seed + 500, 3, 64)
    v = 0.72 + 0.5 * (base - 0.5) + 0.10 * (grain - 0.5)

    # pitting
    pits = fbm(size, seed + 900, 2, 128)
    v -= np.clip((pits - 0.74) * 3.2, 0, 1) * 0.42

    # damp streaks running down the wall
    streak = fbm(size, seed + 1300, 4, 6)
    col = np.linspace(0, 1, size, dtype=np.float32)[None, :]
    run = np.clip(fbm(size, seed + 1700, 2, 10) - 0.52, 0, 1) * 3.0
    grad = np.clip(np.linspace(-0.2, 1.15, size, dtype=np.float32)[:, None], 0, 1)
    v -= run * grad * 0.30 * (0.6 + 0.4 * streak)

    v = np.clip(v, 0.05, 1.4)
    rgb = np.dstack([v * tint[0], v * tint[1], v * tint[2]])

    # rust/nicotine bloom, sparse
    warm = np.clip(fbm(size, seed + 2100, 3, 5) - 0.60, 0, 1) * 2.4
    rgb[..., 0] += warm * 0.055
    rgb[..., 1] += warm * 0.024
    return np.clip(rgb * 6.0, 0, 1)


def add_panels(rgb, rows=4, cols=4, groove=0.42):
    """Cast-in panel seams. Straight lines are what read as 'built', not 'noise'."""
    size = rgb.shape[0]
    out = rgb.copy()
    for i in range(1, rows):
        y = int(size * i / rows)
        out[y - 2:y + 2, :, :] *= groove
        out[y + 2:y + 4, :, :] *= 1.22
    for j in range(1, cols):
        x = int(size * j / cols)
        out[:, x - 2:x + 2, :] *= groove
        out[:, x + 2:x + 4, :] *= 1.22
    return np.clip(out, 0, 1)


def floor_tex(size=1024, seed=31):
    rgb = concrete(size, (0.070, 0.060, 0.057), seed)
    out = (rgb * 255).astype(np.uint8)
    img = Image.fromarray(out, "RGB")
    a = np.asarray(img).astype(np.float32) / 255.0
    # scuff arcs where chairs have been dragged
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    for k in range(7):
        cx, cy = RNG.uniform(120, size - 120, 2)
        r = RNG.uniform(90, 300)
        d = np.abs(np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) - r)
        a *= (1.0 - np.clip(1.0 - d / 6.0, 0, 1)[..., None] * 0.20)
    return np.clip(a, 0, 1)


def metal_tex(size=512, seed=57):
    """Worn dark steel for the table top."""
    base = fbm(size, seed, 5, 6)
    brush = fbm(size, seed + 300, 2, 200)
    v = 0.42 + 0.34 * (base - 0.5) + 0.14 * (brush - 0.5)
    scr = np.clip(fbm(size, seed + 700, 2, 90) - 0.66, 0, 1) * 3.0
    v += scr * 0.30
    v = np.clip(v, 0.05, 1.2)
    rgb = np.dstack([v * 0.115, v * 0.096, v * 0.090])
    stain = np.clip(fbm(size, seed + 1100, 3, 4) - 0.58, 0, 1) * 2.2
    rgb[..., 0] += stain * 0.045
    rgb[..., 1] += stain * 0.016
    return np.clip(rgb * 4.4, 0, 1)


def roughness_from(rgb, lo=0.62, hi=0.99):
    v = rgb.mean(axis=2)
    v = (v - v.min()) / max(1e-6, (v.max() - v.min()))
    r = hi - (hi - lo) * v
    return np.dstack([r, r, r])


def save(name, rgb, blur=0.0):
    img = to_img(rgb)
    if blur > 0:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    path = os.path.join(OUT, name)
    img.save(path)
    print("  %-22s %s" % (name, img.size))


print("generating room textures")
wall = add_panels(concrete(1024, (0.090, 0.075, 0.071), 11), 3, 3)
save("wall_albedo.png", wall)
save("wall_rough.png", roughness_from(wall, 0.70, 0.99))

flr = floor_tex(1024, 31)
save("floor_albedo.png", flr)
save("floor_rough.png", roughness_from(flr, 0.66, 0.98))

ceil = concrete(512, (0.062, 0.052, 0.049), 71)
save("ceiling_albedo.png", ceil)

met = metal_tex(512, 57)
save("table_albedo.png", met)
save("table_rough.png", roughness_from(met, 0.42, 0.86))

print("done ->", os.path.normpath(OUT))
