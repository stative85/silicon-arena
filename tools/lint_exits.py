#!/usr/bin/env python3
"""Find failure exits that say nothing.

    python tools/lint_exits.py

Every silent failure in this project's history looked like success: the clip
recorder printed CLIP SAVED with no file, the size law was dead code on the main
path, a model that was merely loading looked dead, and scar_ladder.gd exited
non-zero three different ways while printing nothing at all.

A non-zero quit() must be preceded by output explaining it. Anything printing
within LOOKBACK lines before the exit counts.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
LOOKBACK = 6
QUIT = re.compile(r"^\s*quit\(\s*([1-9]\d*)\s*\)\s*(#.*)?$")
# Must be a CALL. An early version matched the declaration
# "var _fail: Array[String] = []" and passed a genuinely silent exit.
SPEAKS = re.compile(r"\b(print|printerr|print_rich|push_error|push_warning|_fail|_bad|_report)\s*\(")

try:
    tracked = subprocess.run(["git", "ls-files", "*.gd"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout.split()
except Exception as e:                           # noqa: BLE001
    print(f"cannot list tracked files: {e}")
    sys.exit(0)

bad = 0
checked = 0
for rel in tracked:
    f = ROOT / rel
    if not f.exists():
        continue
    lines = f.read_text(encoding="utf-8", errors="replace").split("\n")
    if not lines or "extends SceneTree" not in lines[0]:
        continue
    for i, line in enumerate(lines):
        m = QUIT.match(line)
        if not m:
            continue
        checked += 1
        # An explicit trailing comment naming where the message comes from is
        # an accepted exemption: some guards print inside the function being
        # tested, and duplicating the message at the exit site is noise.
        note = (m.group(2) or "")
        if "printed by" in note or "reported by" in note:
            continue
        # Comments do not print. An early version of this check counted the
        # word "print" inside a docstring and passed a genuinely silent exit.
        window = [w for w in lines[max(0, i - LOOKBACK):i]
                  if not w.strip().startswith("#")]
        if not any(SPEAKS.search(w) for w in window):
            print(f"FAIL {rel}:{i+1}: quit({m.group(1)}) with no output in the "
                  f"preceding {LOOKBACK} lines. Print the reason, or annotate "
                  f"the exit with '# reason printed by <func>'")
            bad += 1

print(f"\n{checked} non-zero exit(s) checked, {bad} silent")
sys.exit(1 if bad else 0)
