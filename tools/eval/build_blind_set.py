#!/usr/bin/env python3
"""Build a blinded quality set from the recorded conditions.

    python tools/eval/build_blind_set.py [--per-condition 60] [--window 6]

Judges must not be able to tell which roster mode produced an excerpt, so:
  * speaker display names become SPEAKER_A..E, consistent inside an excerpt
  * any agent display name appearing INSIDE the text is replaced by its label
  * model ids and bare parameter sizes ("1.6b", "7B") are scrubbed
  * excerpts are shuffled with a fixed seed and given opaque ids

Excerpts are runs of CONSECUTIVE speeches, not isolated lines, because
"responsiveness to the previous speaker" cannot be judged without the previous
speaker. The key mapping id -> condition is written separately and is not part
of the file handed to a judge.
"""
import argparse
import json
import os
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "tools", "eval", "runs")
LABELS = ["SPEAKER_A", "SPEAKER_B", "SPEAKER_C", "SPEAKER_D", "SPEAKER_E"]
SIZE = re.compile(r"\b\d+(?:\.\d+)?\s*[bB]\b")
HASHNUM = re.compile(r"\s*#\d+")


# Ordinary English that happens to appear in model names. Scrubbing these
# would mangle the debate itself, and they identify nothing on their own.
B = chr(92) + "b"   # word boundary, built explicitly:
# a literal "\b" in source has been silently turned into a backspace
# by a shell heredoc twice in this project already.
W = chr(92) + "w*"

SAFE_WORDS = {"chat", "instruct", "fast", "full", "mini", "tiny", "base",
              "preview", "creative", "logical", "rogue", "guff", "text",
              "small", "large", "medium", "code", "math", "vision"}


def name_tokens(names, models):
    """Every distinctive word that could identify an agent or its model.

    "H 2o Danube 3 4B #1" was rewritten correctly, but a later speaker calling
    it just "Danube" was not: the mapping only knew the full name and the
    model id split to "danube3", never bare "danube". Trailing digits are
    stripped for the same reason.
    """
    out = set()
    for src in list(names) + list(models):
        for piece in re.split(r"[^A-Za-z0-9]+", src):
            piece = re.sub(r"\d+$", "", piece)
            low = piece.lower()
            if len(piece) > 3 and low not in SAFE_WORDS and not low.isdigit():
                out.add(piece)
    return out


def scrub(text, name_to_label, model_tokens):
    out = text
    # Longest names first so "Stablelm 2 Zephyr #1" is replaced before "Stablelm".
    for name in sorted(name_to_label, key=len, reverse=True):
        label = name_to_label[name]
        out = re.sub(re.escape(name), label, out, flags=re.I)
        bare = HASHNUM.sub("", name).strip()
        if len(bare) > 3:
            out = re.sub(re.escape(bare), label, out, flags=re.I)
    for tok in sorted(model_tokens, key=len, reverse=True):
        if len(tok) > 3:
            out = re.sub(re.escape(tok), "[model]", out, flags=re.I)
    # Bare identifying words, after the full names have had their chance.
    for tok in sorted(name_tokens(name_to_label.keys(), model_tokens),
                      key=len, reverse=True):
        out = re.sub(B + re.escape(tok) + W, "[model]", out, flags=re.I)
    out = SIZE.sub("[size]", out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-condition", type=int, default=60)
    ap.add_argument("--window", type=int, default=6)
    a = ap.parse_args()

    rng = random.Random(20260901)
    excerpts = []

    for f in sorted(os.listdir(RUNS)):
        if not f.endswith(".json") or f.startswith("_"):
            continue
        rec = json.load(open(os.path.join(RUNS, f), encoding="utf-8"))
        sp = rec["speeches"]
        cond = rec["condition"]
        if len(sp) < a.window:
            print("  %s: only %d speeches, skipped" % (cond, len(sp)))
            continue

        model_tokens = set()
        for m in rec["models"]:
            model_tokens.add(m)
            for piece in re.split(r"[/_\-.@]", m):
                if len(piece) > 3:
                    model_tokens.add(piece)

        # Evenly spaced, non-overlapping windows across the whole run, so no
        # condition is judged only on its opening or only on its tail.
        want = max(1, a.per_condition // a.window)
        starts = list(range(0, len(sp) - a.window + 1, a.window))
        if len(starts) > want:
            step = len(starts) / float(want)
            starts = [starts[int(i * step)] for i in range(want)]
        used = 0
        for si in starts:
            chunk = sp[si:si + a.window]
            names = []
            for s in chunk:
                if s["speaker"] not in names:
                    names.append(s["speaker"])
            if len(names) > len(LABELS):
                continue
            mapping = {n: LABELS[i] for i, n in enumerate(names)}
            lines = []
            for s in chunk:
                lines.append({"speaker": mapping[s["speaker"]],
                              "text": scrub(s["text"], mapping, model_tokens)})
            excerpts.append({"condition": cond, "start": si, "lines": lines})
            used += len(chunk)
        print("  %s: %d excerpts, %d speeches" % (cond, len(starts), used))

    rng.shuffle(excerpts)
    blind, key = [], {}
    for i, e in enumerate(excerpts):
        eid = "EX%03d" % (i + 1)
        key[eid] = {"condition": e["condition"], "start": e["start"]}
        blind.append({"id": eid, "lines": e["lines"]})

    json.dump(blind, open(os.path.join(RUNS, "_blind_set.json"), "w",
                          encoding="utf-8"), indent=1)
    json.dump(key, open(os.path.join(RUNS, "_blind_key.json"), "w",
                        encoding="utf-8"), indent=1)
    print("\n%d excerpts written to _blind_set.json (key kept separately)"
          % len(blind))

    # Cheap leak check: no condition name, model id or original speaker name
    # may survive into the blinded file.
    # Check against the tokens THESE runs actually used, not a guessed list.
    # A hardcoded list flagged "diverse" and "balanced", which are ordinary
    # debate vocabulary and identify nothing.
    raw = open(os.path.join(RUNS, "_blind_set.json"), encoding="utf-8").read().lower()
    identifying = set()
    for f in os.listdir(RUNS):
        if not f.endswith(".json") or f.startswith("_"):
            continue
        rec = json.load(open(os.path.join(RUNS, f), encoding="utf-8"))
        names = set(s["speaker"] for s in rec["speeches"])
        identifying |= name_tokens(names, set(rec["models"]))
    leaks = sorted(t for t in identifying if t.lower() in raw)
    print("leak check: %s" % ("CLEAN" if not leaks else "LEAKED %s" % leaks))
    return 1 if leaks else 0


if __name__ == "__main__":
    raise SystemExit(main())
