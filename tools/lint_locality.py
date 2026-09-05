#!/usr/bin/env python3
"""Can the resolver reach meaning, or an agent reach global resource state?

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

METABOLISM-A (docs/EXPERIMENT_METABOLISM.md at 858f1ab) adds the second half.
Agent-side policy is ALLOWED to understand meaning -- that is the architecture --
but it must never read global RESOURCE state. If an agent could see which models
are loaded or how much VRAM is free, every agent would be reading the same
global variable and they would coordinate through shared state that no local
view should contain. That is the cage returning as a resource signal instead of
a semantic one, and the semantic check above would stay green the whole time.

The resolver is meant to stay this small. If it ever legitimately needs another
import, that is a change to the experiment, not to this lint.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = ROOT / "scripts" / "arena" / "swarm_resolver.gd"

# Agent-side policy: may reason about meaning, may not read the world.
AGENT_SIDE = [
    ROOT / "scripts" / "arena" / "swarm_bid.gd",
    ROOT / "scripts" / "arena" / "swarm_request.gd",
]

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

# Resource-oracle vocabulary. A local policy that mentions any of this is
# reading the world instead of reading itself.
RESOURCE = [
    "vram", "gpu", "catalog", "loaded", "resident", "evict", "eviction",
    "queue", "budget", "availability", "available", "model_policy",
    "modelpolicy", "oracle", "free_gb", "cost", "granted", "denied",
    "downgrade", "lm_studio", "lmstudio", "endpoint",
]

# A request is not authority. requested_class may be validated and must never
# be acted on, so it may not appear anywhere in the selection arithmetic.
SELECTION = re.compile(r"\b(?:best_bid|best_id|salt|_tie_key)\b")


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
    # Check the DECLARATION, not the whole file. An earlier version searched the
    # entire source, and `entry["requested_class"]` elsewhere satisfied it -- so
    # deleting the key from ALLOWED_KEYS left this lint green. Found by
    # sabotage, which is the only reason it is not still there.
    decl = ""
    for line in text.splitlines():
        if line.strip().startswith("const ALLOWED_KEYS"):
            decl = line
            break
    for key in ('"agent_id"', '"eligible"', '"bid"', '"requested_class"'):
        if key not in decl:
            print(f"FAIL {TARGET.name}: {key} missing from ALLOWED_KEYS")
            bad += 1

    # requested_class may be validated, never acted on.
    for lineno, line in code_lines(text):
        if "requested_class" in line and SELECTION.search(line):
            print(f"FAIL {TARGET.name}:{lineno}: requested_class reaches the "
                  f"selection arithmetic -> {line.strip()[:70]}")
            bad += 1

    # Agent-side policy may not read global resource state.
    for path in AGENT_SIDE:
        if not path.exists():
            print(f"FAIL {path.name}: agent-side policy file is missing")
            bad += 1
            continue
        src = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in code_lines(src):
            if LOADS.search(line) and "swarm_bid.gd" not in line:
                print(f"FAIL {path.name}:{lineno}: agent policy loads a "
                      f"module -> {line.strip()[:70]}")
                bad += 1
            # SUBSTRING, not word-bounded. Word-bounded matching never fires on
            # VRAM_FREE_GB, because underscore counts as a word character -- so
            # a constant named for the exact thing it must not read sailed
            # straight through. Found by sabotage; it would not have been found
            # by reading the code, because it looks correct.
            low = line.lower()
            for word in RESOURCE + ["reason"]:
                if word in low:
                    print(f"FAIL {path.name}:{lineno}: resource-oracle "
                          f"identifier {word!r} in agent-side code "
                          f"-> {line.strip()[:70]}")
                    bad += 1

    names = ", ".join([TARGET.name] + [p.name for p in AGENT_SIDE])
    print(f"\nlocality lint: {names}, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
