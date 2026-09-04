#!/usr/bin/env python3
"""Can the swarm resolver reach anything that carries meaning?

    python tools/lint_locality.py

The runtime half of this boundary is scripts/arena/swarm_resolver_selftest.gd,
which offers every forbidden field to the resolver and requires each to be
refused. That test protects the DATA path.

This protects the IMPORT path, which the test cannot see. A resolver that
preloads gonzo_recall or live_match has access to history, scars and turn text
whether or not anything is currently passed through its arguments, and the next
person who needs a tiebreak will reach for what is already in scope.

Pre-registered in docs/EXPERIMENT_SWARM.md at 85d34f2: "the resolver cannot
import history, scars, traces, turn text, relationships, direct-address state,
or memory. Adding one should turn verification red."

The resolver is meant to stay this small. If it ever legitimately needs another
import, that is a change to the experiment, not to this lint.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = ROOT / "scripts" / "arena" / "swarm_resolver.gd"

# Any load of another script at all. The resolver needs none.
LOADS = re.compile(r"\b(?:preload|load)\s*\(")

# Identifiers that carry meaning rather than resource state. Matched only in
# code, never in comments -- the file's own documentation has to be able to
# explain what it refuses without tripping the check that enforces it.
FORBIDDEN = [
    "history", "transcript", "turns", "scar", "trace", "excerpt",
    "speaker", "text", "topic", "addressed", "direct_address",
    "relationship", "memory", "gonzo", "live_match", "recall",
    "intensity", "provenance", "reason",
]


def code_lines(text):
    """Source with comments and docstrings stripped, keeping line numbers."""
    out = []
    for i, line in enumerate(text.split("\n"), 1):
        stripped = re.sub(r"#.*$", "", line)
        out.append((i, stripped))
    return out


def main():
    if not TARGET.exists():
        print(f"FAIL: {TARGET.relative_to(ROOT)} does not exist")
        return 1

    text = TARGET.read_text(encoding="utf-8", errors="replace")
    bad = 0

    for lineno, line in code_lines(text):
        m = LOADS.search(line)
        if m:
            print(f"FAIL {TARGET.name}:{lineno}: resolver loads another script "
                  f"-> {line.strip()[:70]}")
            bad += 1
        for word in FORBIDDEN:
            if re.search(rf"\b{re.escape(word)}\b", line, re.I):
                print(f"FAIL {TARGET.name}:{lineno}: semantic identifier "
                      f"{word!r} in code -> {line.strip()[:70]}")
                bad += 1

    # The boundary is only meaningful if the vocabulary is closed.
    if "const ALLOWED_KEYS" not in text:
        print(f"FAIL {TARGET.name}: no ALLOWED_KEYS whitelist")
        bad += 1
    for key in ('"agent_id"', '"eligible"', '"bid"'):
        if key not in text:
            print(f"FAIL {TARGET.name}: {key} missing from the vocabulary")
            bad += 1

    print(f"\nlocality lint: {TARGET.name}, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
