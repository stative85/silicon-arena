#!/usr/bin/env python3
"""Render docs/arena.gif and docs/console.png from a real console capture.

    godot --headless --path . > capture.txt 2>&1     # let it run ~5 minutes
    python tools/make_hero.py capture.txt

The hero assets must never contain fabricated terminal text, so they are built
from a capture rather than written by hand. This script exists so regenerating
them after the output format changes is a command, not an archaeology project.
"""
import os
import re
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow is required:  pip install pillow")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEEP = re.compile(r"model-policy|^\[TURN\]|BLOCKED|compat|LOADING|^[┃┏┣┗]")
FONT = r"C:\Windows\Fonts\consola.ttf"
FONT_B = r"C:\Windows\Fonts\consolab.ttf"

AGENT_COLOURS = ["#c471ed", "#3db1ff", "#00d2ff", "#5ad78c", "#ff6b6b"]
BG, BAR, DIM, WHITE = "#0b0f14", "#161b22", "#6e7681", "#c9d1d9"
GREEN, YELLOW, CYAN, GREY = "#3fb950", "#d29922", "#39c5cf", "#30363d"
FS, ROWS, WIDTH, PAD = 18, 22, 1180, 24
LH = int(FS * 1.44)


def select(path, limit=30):
    raw = open(path, encoding="utf-8", errors="ignore").read().split("\n")
    try:
        start = next(i for i, l in enumerate(raw) if "model-policy" in l)
    except StopIteration:
        print("no [model-policy] line in the capture — is this a real run?")
        sys.exit(1)
    out, last_load = [], None
    for line in raw[start:]:
        line = line.rstrip()
        if not line.strip() or not KEEP.search(line):
            continue
        if line.startswith("[LOADING]"):
            who = line.split("—")[0]
            if who == last_load:
                continue
            last_load = who
            line = re.sub(r"\(cold model swaps.*\)", "(cold model swap in progress)", line)
        out.append(line)
        if len(out) >= limit:
            break
    return out


def colour_for(line, names):
    if "model-policy" in line:
        return GREEN, True
    if line.startswith("[compat]"):
        return YELLOW, True
    if line.startswith("[LOADING]"):
        return YELLOW, False
    if line.startswith("[TURN]"):
        return DIM, False
    if line[:1] in "┏┣┗":
        return GREY, False
    if "🎤" in line:
        for i, n in enumerate(names):
            if n in line:
                return AGENT_COLOURS[i % len(AGENT_COLOURS)], True
        return WHITE, True
    if "📌" in line:
        return CYAN, False
    return WHITE, False


def title_for(path):
    """Describe the run from the CAPTURE, not from a constant.

    This was hardcoded to "5 local models". A capture of five agents sharing
    three models therefore shipped a title claiming five models -- a false
    claim baked into the storefront image, which is exactly the kind of
    detail a sceptical reader checks first. Count what the run actually did.
    """
    raw = open(path, encoding="utf-8", errors="ignore").read()
    agents, models = set(), set()
    for line in raw.splitlines():
        if line.startswith("[TURN] ") and "(" in line:
            agents.add(line[7:].split("(")[0].strip())
            models.add(line.split("(", 1)[1].split(")")[0].strip())
    if not agents:
        return "Silicon Arena"
    if len(models) == 1:
        return "Silicon Arena - %d agents on 1 local model, one 8GB GPU" % len(agents)
    return ("Silicon Arena - %d agents, %d local models, one 8GB GPU"
            % (len(agents), len(models)))


def render(lines, names, font, bold, title):
    h = PAD * 2 + LH * ROWS + 38
    img = Image.new("RGB", (WIDTH, h), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, WIDTH, 34], fill=BAR)
    for i, c in enumerate(["#ff5f56", "#ffbd2e", "#27c93f"]):
        d.ellipse([16 + i * 20, 12, 26 + i * 20, 22], fill=c)
    tw = d.textlength(title, font=font)
    d.text((max(PAD, (WIDTH - tw) // 2), 9), title, font=font, fill=DIM)
    y = 34 + PAD
    for line in lines[-ROWS:]:
        col, is_bold = colour_for(line, names)
        # Strip variation selectors too: the emoji are U+1F3A4/U+1F4CC followed
        # by U+FE0F, and replacing only the base codepoint left the selector
        # behind, which the console font drew as a tofu box in the hero image.
        plain = (line.replace("🎤", ">").replace("📌", "#")
                 .replace("️", "").replace("︎", "")
                 # consolab.ttf has no U+2503 HEAVY VERTICAL, so speaker
                 # header lines -- the only bold ones -- drew a tofu box while
                 # every body line rendered fine in the regular face.
                 .replace("┃", "|"))
        d.text((PAD, y), plain,
               font=bold if is_bold else font, fill=col)
        y += LH
    return img


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    lines = select(sys.argv[1])
    title = title_for(sys.argv[1])
    print("title:", title)
    names = []
    for l in lines:
        if "🎤" in l:
            n = l.split("🎤")[1].split("(")[0].strip()
            if n and n not in names:
                names.append(n)

    font = ImageFont.truetype(FONT, FS)
    bold = ImageFont.truetype(FONT_B, FS)

    frames, durations, visible = [], [], []
    for line in lines:
        visible.append(line)
        frames.append(render(visible, names, font, bold, title))
        if "🎤" in line:
            durations.append(900)
        elif line.startswith(("[compat]", "[LOADING]")):
            durations.append(700)
        elif "model-policy" in line:
            durations.append(1200)
        else:
            durations.append(260)
    frames.append(render(visible, names, font, bold, title))
    durations.append(2600)

    gif = os.path.join(ROOT, "docs", "arena.gif")
    png = os.path.join(ROOT, "docs", "console.png")
    frames[0].save(gif, save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, optimize=True)
    frames[-1].save(png)
    print(f"{len(frames)} frames  {frames[0].size}")
    print(f"  {gif}  {os.path.getsize(gif) / 1024:.0f} KB")
    print(f"  {png}  {os.path.getsize(png) / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
