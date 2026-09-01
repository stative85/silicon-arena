"""Fail if a script depends on the PRIVATE sibling checkout as its only path.

This repository is developed next to a private ../extinct_os/ checkout. Code
written there works locally and is dead on arrival in a public clone, and the
failure is invisible to the author because the file is right there on their
disk. Five scripts shipped that way: alliance_proof, scar_ab_probe,
scar_ladder, scar_table and match_scene each hardcoded

    ../extinct_os/config/arena-roster.v1.json

as their ONLY roster path, so every one of them failed on a clean clone.

A reference to the private tree is allowed only when the file ALSO offers a
public path -- either by going through the shared resolver, or by listing a
res:// candidate of its own first. Prose in comments is ignored; only code
lines count, because documenting the private layout is fine and depending on
it is not.

    python tools/lint_private_paths.py
"""
import os
import re
import sys

PRIVATE = "extinct_os"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The resolver itself is where the private fallback is SUPPOSED to live.
RESOLVER = os.path.join("scripts", "arena", "roster_path.gd")

# Schema mirrors: these selftests read a .ts file from the private tree to
# compare constants, and are written to skip cleanly when it is absent. They
# are cross-checks, not runtime dependencies.
ALLOWED = {
    os.path.join("scripts", "arena", "cinematic_selftest.gd"),
    os.path.join("scripts", "arena", "scar_lattice_selftest.gd"),
    RESOLVER,
}


def code_lines(path):
    """Yield (lineno, text) for lines that are not pure comments."""
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for n, raw in enumerate(fh, 1):
            stripped = raw.strip()
            if stripped.startswith("#"):
                continue
            yield n, raw


def main():
    problems = []
    scanned = 0
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "node_modules")]
        for name in files:
            if not name.endswith(".gd"):
                continue
            full = os.path.join(base, name)
            rel = os.path.relpath(full, ROOT)
            scanned += 1
            if rel in ALLOWED:
                continue
            hits = [(n, t) for n, t in code_lines(full) if PRIVATE in t]
            if not hits:
                continue
            body = open(full, encoding="utf-8", errors="ignore").read()
            # A public escape hatch: the shared resolver, or its own res:// path
            # to the same file.
            has_public = (
                "RosterPath" in body
                or "roster_path.gd" in body
                or re.search(r'"res://config/[^"]+\.json"', body) is not None
            )
            if not has_public:
                for n, t in hits:
                    problems.append(
                        "%s:%d depends on the private checkout with no public "
                        "path\n      %s" % (rel, n, t.strip())
                    )

    for p in problems:
        print("  FAIL %s" % p)
    print("\n%d script(s) scanned, %d problem(s)" % (scanned, len(problems)))
    if problems:
        print("PRIVATE PATH LINT FAILED")
        return 1
    print("PRIVATE PATHS OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
