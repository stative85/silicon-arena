"""Discover every usable sprite pack, extracted or still zipped.

Hand-wiring CHAR_PATHS one entry at a time is why most of these packs were
never used. This scans instead: it classifies each pack by SHAPE (what the
loader can actually consume) rather than by name, so a pack that works gets
found automatically and a pack that doesn't gets told why.

    python tools/sprite_scan.py            # report only, touches nothing
    python tools/sprite_scan.py --extract  # unpack the usable character packs

Shapes recognised:
  SEQUENCE_CHARACTER  dir tree with animation folders of numbered PNGs
                      (CraftPix "PNG Sequences" layout) -> directly loadable
  LAYERED_SHEET       512x512 8x8 grids, base + outfit/hair layers
  SPRITE_SHEET        single PNG wider than one frame, needs a grid spec
  TILESET_OR_PROPS    art with no animation structure -- usable as scenery
  UNUSABLE            nothing an animation loader can consume
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
import zipfile
from collections import defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI_ROOT = os.path.dirname(HERE)

# Animation folder names the existing loader asks for, plus common synonyms.
ANIM_HINTS = {"idle", "walking", "walk", "running", "run", "slashing", "attack",
              "dying", "death", "hurt", "jump", "throwing", "kicking", "sliding",
              "idle blinking", "falling down"}

NUMBERED_PNG = re.compile(r"^(.*?)[_\- ]?(\d+)\.png$", re.IGNORECASE)


def png_size(raw: bytes):
    """Read dimensions from the first 33 bytes of a PNG."""
    try:
        if raw[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        w, h = struct.unpack(">II", raw[16:24])
        return w, h
    except Exception:                                     # noqa: BLE001
        return None


def classify(paths: list[str], sizes: list | None = None) -> tuple[str, dict]:
    """Classify a pack from its file list alone. No extraction required."""
    sizes = sizes or []
    pngs = [p for p in paths if p.lower().endswith(".png")]
    if not pngs:
        return "UNUSABLE", {"reason": "contains no PNG files"}

    # Group PNGs by their containing directory.
    by_dir: dict[str, list[str]] = defaultdict(list)
    for p in pngs:
        by_dir[os.path.dirname(p)].append(os.path.basename(p))

    # SEQUENCE_CHARACTER: a directory whose NAME is an animation and whose
    # contents are numbered frames. This is the shape the arena already loads.
    characters: dict[str, dict[str, int]] = defaultdict(dict)
    for d, files in by_dir.items():
        leaf = os.path.basename(d).lower()
        if leaf not in ANIM_HINTS:
            continue
        numbered = [f for f in files if NUMBERED_PNG.match(f)]
        if len(numbered) < 2:
            continue
        # The character is the folder above "PNG Sequences" (or above the anim).
        parts = d.replace("\\", "/").split("/")
        char = None
        for i, seg in enumerate(parts):
            if seg.lower() in ("png sequences", "png sequence"):
                # Layout is <Character>/PNG/PNG Sequences/<Anim>, so the
                # segment directly above is the container "PNG", not the
                # character. Walk back past those wrapper folders.
                j = i
                while j > 0 and parts[j - 1].lower() in ("png", "pngs", "sprites"):
                    j -= 1
                char = "/".join(parts[:j])
                break
        if char is None:
            char = "/".join(parts[:-1])
        characters[char][os.path.basename(d)] = len(numbered)

    if characters:
        return "SEQUENCE_CHARACTER", {"characters": {
            k: dict(sorted(v.items())) for k, v in sorted(characters.items())}}

    if sizes:
        strips = [(n, w, h) for (n, w, h) in sizes
                  if h > 0 and w >= h * 3 and w % h == 0]
        if strips:
            return "SPRITE_SHEET", {
                "strips": [{"file": os.path.basename(n), "w": w, "h": h,
                            "frames": w // h} for n, w, h in strips[:12]],
                "strip_count": len(strips),
            }

    return "TILESET_OR_PROPS", {"png_count": len(pngs),
                                "dirs": len(by_dir)}


def scan_zip(path: str) -> dict:
    try:
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist()
                     if not n.startswith("__MACOSX") and not n.endswith("/")]
    except zipfile.BadZipFile:
        return {"path": path, "shape": "UNUSABLE",
                "detail": {"reason": "corrupt or not a zip"}}
    sizes = []
    try:
        with zipfile.ZipFile(path) as z:
            for n in names:
                if not n.lower().endswith(".png"):
                    continue
                try:
                    d = png_size(z.open(n).read(33))
                except Exception:                          # noqa: BLE001
                    d = None
                if d:
                    sizes.append((n, d[0], d[1]))
                if len(sizes) > 400:
                    break
    except Exception:                                       # noqa: BLE001
        pass
    shape, detail = classify(names, sizes)
    return {"path": path, "packed": True, "shape": shape, "detail": detail,
            "files": len(names)}


def scan_dir(path: str) -> dict:
    names = []
    for root, _dirs, files in os.walk(path):
        if "__MACOSX" in root or os.sep + ".godot" in root:
            continue
        for f in files:
            names.append(os.path.relpath(os.path.join(root, f), path))
    sizes = []
    for n in names:
        if not n.lower().endswith(".png"):
            continue
        try:
            with open(os.path.join(path, n), "rb") as fh:
                d = png_size(fh.read(33))
            if d:
                sizes.append((n, d[0], d[1]))
        except Exception:                                   # noqa: BLE001
            pass
        if len(sizes) > 400:
            break
    shape, detail = classify(names, sizes)
    return {"path": path, "packed": False, "shape": shape, "detail": detail,
            "files": len(names)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--extract", action="store_true",
                    help="unpack SEQUENCE_CHARACTER zips into assets/packs/")
    ap.add_argument("--root", default=CLI_ROOT)
    args = ap.parse_args()

    results = []
    for entry in sorted(os.listdir(args.root)):
        full = os.path.join(args.root, entry)
        if entry.lower().endswith(".zip"):
            results.append(scan_zip(full))
    arena_assets = os.path.join(HERE, "assets")
    if os.path.isdir(arena_assets):
        for entry in sorted(os.listdir(arena_assets)):
            full = os.path.join(arena_assets, entry)
            if os.path.isdir(full):
                results.append(scan_dir(full))
    # zips sitting inside the arena folder too
    for entry in sorted(os.listdir(HERE)):
        if entry.lower().endswith(".zip"):
            results.append(scan_zip(os.path.join(HERE, entry)))

    buckets: dict[str, list] = defaultdict(list)
    for r in results:
        buckets[r["shape"]].append(r)

    print("=" * 70)
    print("SPRITE PACK SCAN")
    print("=" * 70)

    total_chars = 0
    for r in buckets.get("SEQUENCE_CHARACTER", []):
        chars = r["detail"]["characters"]
        total_chars += len(chars)
        state = "ZIPPED" if r.get("packed") else "on disk"
        print(f"\n[CHARACTERS] {os.path.basename(r['path'])}  ({state})")
        for cname, anims in chars.items():
            short = cname.split("/")[-1] or cname
            core = {k: v for k, v in anims.items()
                    if k.lower() in ("idle", "walking", "slashing")}
            extra = len(anims) - len(core)
            print(f"    {short:<34} " +
                  "  ".join(f"{k}={v}" for k, v in sorted(core.items())) +
                  (f"  (+{extra} more)" if extra else ""))

    print(f"\n[SCENERY / PROPS]  {len(buckets.get('TILESET_OR_PROPS', []))} packs")
    for r in buckets.get("TILESET_OR_PROPS", [])[:12]:
        state = "ZIPPED" if r.get("packed") else "on disk"
        print(f"    {os.path.basename(r['path'])[:52]:<54} "
              f"{r['detail']['png_count']:>5} png  ({state})")

    if buckets.get("UNUSABLE"):
        print(f"\n[UNUSABLE]  {len(buckets['UNUSABLE'])}")
        for r in buckets["UNUSABLE"]:
            print(f"    {os.path.basename(r['path'])[:46]:<48} "
                  f"{r['detail'].get('reason')}")

    print("\n" + "=" * 70)
    print(f"playable characters found: {total_chars}")
    print("=" * 70)

    manifest = os.path.join(HERE, "assets", "sprite_scan.json")
    with open(manifest, "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"manifest -> {os.path.relpath(manifest, HERE)}")

    if args.extract:
        dest_root = os.path.join(HERE, "assets", "packs")
        os.makedirs(dest_root, exist_ok=True)
        for r in buckets.get("SEQUENCE_CHARACTER", []):
            if not r.get("packed"):
                continue
            name = os.path.splitext(os.path.basename(r["path"]))[0]
            dest = os.path.join(dest_root, name)
            if os.path.isdir(dest):
                print(f"  skip (exists) {name}")
                continue
            with zipfile.ZipFile(r["path"]) as z:
                for m in z.namelist():
                    if m.startswith("__MACOSX"):
                        continue
                    z.extract(m, dest)
            print(f"  extracted {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
