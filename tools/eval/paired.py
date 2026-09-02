#!/usr/bin/env python3
"""Paired block analysis for interleaved A/B runs.

    python tools/eval/paired.py <arm_a_label> <arm_b_label>

Compares block i of A against block i of B rather than arm mean against arm
mean. Blocks are interleaved in time, so each pair is judged against the
baseline nearest it, and session drift falls on both members of a pair instead
of on one arm.

Run it first with two labels that are the SAME configuration. Whatever it
reports then is what the protocol manufactures with nothing changed, and no
threshold below that is worth setting -- see CONTRIBUTING.md rule 2.
"""
import json
import os
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "tools", "eval", "runs")

CHALLENGE = re.compile(r"\b(disagree|wrong|however|but |actually|contrary|refute|reject|"
                       r"fallac|mistaken|incorrect|nonsense|challenge|object|flawed|"
                       r"misses|overlooks|naive)\b", re.I)


def norm(s):
    return re.sub(r"\s+", " ", s).strip().lower()


def shingles(t, k=4):
    w = re.findall(r"[a-z']+", t.lower())
    return set(tuple(w[i:i + k]) for i in range(max(0, len(w) - k + 1)))


def block_metrics(speeches, wall_share):
    n = len(speeches)
    if n == 0:
        return None
    names = sorted(set(s["speaker"] for s in speeches))
    sh = [shingles(s["text"]) for s in speeches]
    dup = 0
    for i in range(len(sh)):
        for j in range(i):
            u = len(sh[i] | sh[j])
            if u and len(sh[i] & sh[j]) / u >= 0.5:
                dup += 1
                break
    words = [len(re.findall(r"[A-Za-z']+", s["text"])) for s in speeches]
    return {
        "spm": n / (wall_share / 60.0) if wall_share else 0.0,
        "challenge": 100.0 * sum(1 for s in speeches if CHALLENGE.search(s["text"])) / n,
        "addresses": 100.0 * sum(1 for s in speeches
                                 if any(norm(o) in norm(s["text"])
                                        for o in names if o != s["speaker"])) / n,
        "near_dup": 100.0 * dup / n,
        "mean_words": sum(words) / float(n),
    }


def blocks_of(label):
    rec = json.load(open(os.path.join(RUNS, label + ".json"), encoding="utf-8"))
    sp = rec["speeches"]
    chunks = sorted(set(s.get("chunk", 1) for s in sp))
    walls = rec.get("chunk_walls") or []
    out = []
    for i, c in enumerate(chunks):
        # Real per-block wall time when recorded; an even split is only a
        # fallback for runs made before that was captured, and it makes
        # per-block throughput meaningless, so it is flagged.
        w = walls[i] if i < len(walls) else rec["wall_sec"] / float(len(chunks))
        out.append(block_metrics([s for s in sp if s.get("chunk", 1) == c], w))
    if not walls:
        print("  (per-block wall times unavailable in %s: spm row is not meaningful)" % label)
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    a_label, b_label = sys.argv[1], sys.argv[2]
    A, B = blocks_of(a_label), blocks_of(b_label)
    pairs = min(len(A), len(B))
    if pairs == 0:
        sys.exit("no blocks")

    print("\nPAIRED BLOCKS  %s (A) vs %s (B)   %d pairs\n" % (a_label, b_label, pairs))
    keys = ["spm", "challenge", "addresses", "near_dup", "mean_words"]
    print("%-12s %s" % ("metric", "  ".join("pair%d" % (i + 1) for i in range(pairs))
                        + "      mean      sd   |mean|/sd"))
    out = {}
    for k in keys:
        deltas = [B[i][k] - A[i][k] for i in range(pairs)]
        m = statistics.mean(deltas)
        sd = statistics.pstdev(deltas) if pairs > 1 else 0.0
        out[k] = {"deltas": deltas, "mean": m, "sd": sd}
        cells = "  ".join("%+6.1f" % d for d in deltas)
        ratio = abs(m) / sd if sd > 0 else float("inf")
        print("%-12s %s   %+7.2f  %6.2f   %6.2f" % (k, cells, m, sd, ratio))

    print("\nNOISE ENVELOPE  (|mean delta| + 2 sd of the paired differences)")
    print("A threshold below this cannot be resolved by this protocol.")
    for k in keys:
        env = abs(out[k]["mean"]) + 2 * out[k]["sd"]
        print("  %-12s %.2f" % (k, env))
    json.dump(out, open(os.path.join(RUNS, "_paired_%s_vs_%s.json" % (a_label, b_label)),
                        "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    raise SystemExit(main())
