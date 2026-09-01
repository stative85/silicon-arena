#!/usr/bin/env python3
"""Mechanical metrics over the four roster conditions.

    python tools/eval/metrics.py

Everything here is computed from transcripts without a model in the loop, so it
is reproducible and cannot flatter any condition. Judge scores live separately
in judge.py and are deliberately not mixed with these.
"""
import json
import math
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "tools", "eval", "runs")

WORD = re.compile(r"[A-Za-z']+")
STOP = set("""the a an and or but if then than that this these those is are was were be been being
to of in on at by for with as from it its it's i you he she they we not no do does did have has had
will would can could should may might must there their them his her our your my me us am so such
what which who whom when where why how all any both each few more most other some only own same
very just also into about over under again further once because while during before after above
below up down out off between through
""".split())


def norm(s):
    return re.sub(r"\s+", " ", s).strip().lower()


def words(s):
    return [w.lower() for w in WORD.findall(s)]


def content_words(s):
    return [w for w in words(s) if w not in STOP and len(w) > 2]


def shingles(s, k=4):
    w = words(s)
    return set(tuple(w[i:i + k]) for i in range(max(0, len(w) - k + 1)))


def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / float(len(a | b))


def load():
    out = []
    for f in sorted(os.listdir(RUNS)):
        if f.endswith(".json") and not f.startswith("_"):
            out.append(json.load(open(os.path.join(RUNS, f), encoding="utf-8")))
    return out


# --- VRAM estimate mirrored from scripts/arena/vram.gd --------------------
def bpw(q):
    q = (q or "").upper()
    if q.startswith("F32"):
        return 4.2
    if q.startswith("F16") or q.startswith("BF16"):
        return 2.1
    for tag, v in (("Q8", 1.1), ("Q6", .85), ("Q5", .72), ("Q3", .48), ("Q2", .36)):
        if tag in q:
            return v
    return 0.6


def params_from_id(mid):
    m = re.search(r"(\d+(?:\.\d+)?)\s*b\b", mid.lower())
    return float(m.group(1)) if m else 0.0


def vram_estimate(models):
    total = 0.0
    for mid in set(models):
        p = params_from_id(mid)
        total += (p * bpw("") + 0.35) if p > 0 else 0.0
    return total


def analyse(rec):
    sp = rec["speeches"]
    names = sorted(set(s["speaker"] for s in sp))
    texts = [s["text"] for s in sp]
    n = len(sp)
    mins = rec["wall_sec"] / 60.0

    # near-duplicate: max 4-gram Jaccard against any earlier speech
    sh = [shingles(t) for t in texts]
    dup = 0
    dup_scores = []
    for i in range(len(sh)):
        best = 0.0
        for j in range(i):
            best = max(best, jaccard(sh[i], sh[j]))
        dup_scores.append(best)
        if best >= 0.5:
            dup += 1

    # novelty: fraction of content words never seen before, averaged
    seen = set()
    nov = []
    for t in texts:
        cw = content_words(t)
        if not cw:
            nov.append(0.0)
            continue
        new = sum(1 for w in cw if w not in seen)
        nov.append(new / float(len(cw)))
        seen.update(cw)

    # references to OTHER agents by name; self-prefix leakage
    refs = 0
    selfpre = 0
    for s in sp:
        others = [x for x in names if x != s["speaker"]]
        if any(norm(o) in norm(s["text"]) for o in others):
            refs += 1
        c = s["text"].find(":")
        if 0 < c <= 48:
            head = s["text"][:c].replace("*", "").replace('"', "")
            if norm(head) == norm(s["speaker"]):
                selfpre += 1

    # challenge / contradiction markers
    CH = re.compile(r"\b(disagree|wrong|however|but |actually|contrary|refute|reject|"
                    r"fallac|mistaken|incorrect|no,|nonsense|challenge|object)\b", re.I)
    chal = sum(1 for t in texts if CH.search(t))

    # Uptake: does a speaker use a term the PREVIOUS speaker just introduced
    # to the debate?
    #
    # The first version of this asked whether a speech shared two content words
    # with any of the previous three turns. That scored 98.3% in all four
    # conditions -- it measured that the debate was in English, not that anyone
    # was listening. This asks something a condition can fail: a term must be
    # NEW to the whole run when the previous speaker used it, and then be
    # picked up by the next speaker.
    docs = [set(content_words(t)) for t in texts]
    seen = set()
    uptake = 0
    eligible = 0
    for i in range(len(sp)):
        if i == 0:
            seen |= docs[0]
            continue
        introduced = docs[i - 1] - seen
        if sp[i - 1]["speaker"] != sp[i]["speaker"] and introduced:
            eligible += 1
            if docs[i] & introduced:
                uptake += 1
        seen |= docs[i - 1]
    ret = uptake
    ret_base = eligible

    lat = sorted(s["latency_ms"] for s in sp) or [0]
    lens = [len(words(t)) for t in texts] or [0]
    turns_total = n + len(rec["failures"])

    return {
        "condition": rec["condition"],
        "distinct_models": rec["distinct_models"],
        "vram_est_gb": vram_estimate(rec["models"]),
        "speeches": n,
        "wall_sec": rec["wall_sec"],
        "speeches_per_min": n / mins if mins else 0,
        "failure_rate": len(rec["failures"]) / float(turns_total) if turns_total else 0,
        "near_dup_rate": dup / float(n) if n else 0,
        "mean_max_similarity": sum(dup_scores) / float(n) if n else 0,
        "novelty": sum(nov) / float(n) if n else 0,
        "ref_other_rate": refs / float(n) if n else 0,
        "challenge_rate": chal / float(n) if n else 0,
        "self_prefix_rate": selfpre / float(n) if n else 0,
        "term_uptake": ret / float(ret_base) if ret_base else 0,
        "uptake_n": ret_base,
        "mean_words": sum(lens) / float(len(lens)),
        "median_latency_ms": lat[len(lat) // 2],
        "p90_latency_ms": lat[int(len(lat) * 0.9)] if len(lat) > 1 else lat[0],
    }


ROWS = [
    ("speeches", "speeches", "{:d}", None),
    ("wall_sec", "wall (s)", "{:.0f}", None),
    ("speeches_per_min", "speeches / min", "{:.2f}", "high"),
    ("failure_rate", "failure rate", "{:.1%}", "low"),
    ("distinct_models", "distinct models", "{:d}", "high"),
    ("vram_est_gb", "resident VRAM est (GB)", "{:.1f}", None),
    ("median_latency_ms", "median latency (ms)", "{:.0f}", "low"),
    ("p90_latency_ms", "p90 latency (ms)", "{:.0f}", "low"),
    ("mean_words", "mean words / speech", "{:.1f}", None),
    ("near_dup_rate", "near-duplicate rate", "{:.1%}", "low"),
    ("mean_max_similarity", "mean max similarity", "{:.3f}", "low"),
    ("novelty", "content novelty", "{:.3f}", "high"),
    ("ref_other_rate", "refers to another agent", "{:.1%}", "high"),
    ("challenge_rate", "challenge / contradiction", "{:.1%}", "high"),
    ("term_uptake", "picks up new term", "{:.1%}", "high"),
    ("uptake_n", "  (opportunities)", "{:d}", None),
    ("self_prefix_rate", "self-prefix leakage", "{:.1%}", "low"),
]


def main():
    recs = load()
    if not recs:
        sys.exit("no runs in %s" % RUNS)
    res = [analyse(r) for r in recs]
    conds = [r["condition"] for r in res]

    w = 24
    print("\nMECHANICAL METRICS  (no model in the loop)\n")
    print("metric".ljust(w) + "".join(c.rjust(13) for c in conds) + "   better")
    print("-" * (w + 13 * len(conds) + 9))
    for key, label, fmt, better in ROWS:
        vals = [r[key] for r in res]
        cells = "".join(fmt.format(v).rjust(13) for v in vals)
        mark = {"high": "higher", "low": "lower"}.get(better, "")
        print(label.ljust(w) + cells + "   " + mark)

    out = os.path.join(RUNS, "_metrics.json")
    json.dump(res, open(out, "w", encoding="utf-8"), indent=1)
    print("\nwrote %s" % os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
