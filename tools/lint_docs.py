#!/usr/bin/env python3
"""Catch documentation defects that a human eye slides past.

    python tools/lint_docs.py

Exists because README.md shipped a command reading "toolserify.cmd": a vertical
tab (0x0B) had replaced the backslash in "tools\verify.cmd" during a scripted
edit. The rendered page looked almost right and the command did not exist.

Checks every tracked markdown file for:
  - control characters other than tab and newline
  - broken relative links to files in the repo
  - fenced code blocks that are never closed
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")
LINK = re.compile(r"\[[^\]]*\]\(([^)#:]+?)\)")

try:
    tracked = subprocess.run(
        ["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True,
        text=True, check=True).stdout.split()
except Exception as e:                           # noqa: BLE001
    print(f"cannot list tracked files: {e}")
    sys.exit(0)

bad = 0
for rel in tracked:
    f = ROOT / rel
    if not f.exists():
        continue
    text = f.read_text(encoding="utf-8", errors="replace")

    for i, line in enumerate(text.split("\n"), 1):
        m = CTRL.search(line)
        if m:
            print(f"FAIL {rel}:{i}: control character 0x{ord(m.group()):02x} "
                  f"in {line.strip()[:60]!r}")
            bad += 1

    if text.count("```") % 2 != 0:
        print(f"FAIL {rel}: unclosed code fence ({text.count('```')} markers)")
        bad += 1

    for target in LINK.findall(text):
        t = target.strip()
        if t.startswith(("http://", "https://", "mailto:")):
            continue
        if not (f.parent / t).exists() and not (ROOT / t).exists():
            print(f"FAIL {rel}: broken link -> {t}")
            bad += 1

print(f"\n{len(tracked)} markdown file(s), {bad} problem(s)")
sys.exit(1 if bad else 0)
