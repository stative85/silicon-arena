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
    raw = open(os.path.join(RUNS, "_blind_set.json"), encoding="utf-8").read().lower()
    leaks = []
    for token in ["diverse", "balanced", "fast", "fit", "stablelm", "mistral",
                  "gemma", "elyza", "zephyr", "danube", "qwen", "llama",
                  "deepscaler", "distill", "granite"]:
        if token in raw:
            leaks.append(token)
    print("leak check: %s" % ("CLEAN" if not leaks else "LEAKED %s" % leaks))
    return 1 if leaks else 0


if __name__ == "__main__":
    raise SystemExit(main())
