#!/usr/bin/env python3
"""Structural measures of whether a debate is watchable.

    python tools/eval/entertainment.py

Entertainment was the weakest judged dimension in every roster condition
(2.0-3.0 of 5) and it is also the dimension the judges were WORST at: pairwise
correlations of -0.066, -0.108 and +0.184, which is noise. So this measures
conflict STRUCTURE mechanically and leaves "is it funny" to a human.

What is deliberately NOT claimed: none of these is a fun-meter. They describe
the shape of an argument -- how often people take each other on, how much they
repeat, how long they talk, whether anyone ever changes position. A transcript
can score well here and still be boring.

GUARD METRICS. Several obvious interventions -- "mandate a rebuttal", "always
open by addressing the last speaker" -- raise the conflict numbers BY
CONSTRUCTION while making the output formulaic. opener_uniqueness and
formulaic_openers exist to catch that: an intervention that raises challenges
AND raises opener uniformity has gamed the metric, not improved the product.
"""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "tools", "eval", "runs")

STOP = set("""the a an and or but if then than that this these those is are was were be been
being to of in on at by for with as from it its i you he she they we not no do does did have
has had will would can could should may might must there their them his her our your my me us
am so such what which who whom when where why how all any both each few more most other some
only own same very just also into about over under again further once because while during
before after above below up down out off between through""".split())

CHALLENGE = re.compile(r"\b(disagree|wrong|however|but |actually|contrary|refute|reject|"
                       r"fallac|mistaken|incorrect|nonsense|challenge|object|flawed|"
                       r"misses|overlooks|naive)\b", re.I)
CONCEDE = re.compile(r"\b(agree|concede|fair point|you'?re right|valid point|granted|"
                     r"i accept|good point)\b", re.I)
HEDGE = re.compile(r"\b(perhaps|maybe|arguably|it depends|to some extent|in some sense|"
                   r"one could argue|it is possible)\b", re.I)
FORMULAIC = re.compile(r"^\W*(as an ai|i (?:agree|disagree)|while |however|indeed|"
                       r"it is (?:true|important)|the question|in (?:my|this))", re.I)


def words(t):
    return re.findall(r"[a-z']+", t.lower())


def content(t):
    return [w for w in words(t) if w not in STOP and len(w) > 3]


def analyse(rec):
    sp = rec["speeches"]
    n = len(sp)
    if n == 0:
        return None
    texts = [s["text"] for s in sp]
    names = sorted(set(s["speaker"] for s in sp))
    lens = [len(words(t)) for t in texts]

    # --- conflict --------------------------------------------------------
    challenges = sum(1 for t in texts if CHALLENGE.search(t))
    concedes = sum(1 for t in texts if CONCEDE.search(t))
    hedges = sum(1 for t in texts if HEDGE.search(t))

    def norm(s):
        return re.sub(r"\s+", " ", s).strip().lower()

    addressed = sum(1 for s in sp
                    if any(norm(o) in norm(s["text"]) for o in names if o != s["speaker"]))

    # Escalation: does challenge density rise across the run? Compare the
    # challenge rate of the last third against the first third.
    third = max(1, n // 3)
    early = sum(1 for t in texts[:third] if CHALLENGE.search(t)) / float(third)
    late = sum(1 for t in texts[-third:] if CHALLENGE.search(t)) / float(third)

    # --- repetition and shape -------------------------------------------
    openers = [" ".join(words(t)[:4]) for t in texts]
    opener_uniqueness = len(set(openers)) / float(n)
    formulaic = sum(1 for t in texts if FORMULAIC.match(t))

    short = sum(1 for L in lens if L <= 40)
    long_ = sum(1 for L in lens if L >= 90)

    # --- drift: how far the vocabulary moves from the opening ------------
    first = set(content(" ".join(texts[:3])))
    last = set(content(" ".join(texts[-3:])))
    drift = 1.0 - (len(first & last) / float(len(first | last))) if (first | last) else 0.0

    # Truncation: a reply that ends without terminal punctuation was almost
    # certainly cut off by the token budget mid-thought. This is the guard on
    # the compression experiment -- squeezing word count until sentences break
    # would otherwise look like a win.
    cut = 0
    for t in texts:
        stripped = t.rstrip()
        if stripped and stripped[-1] not in ".!?\"')]":
            cut += 1

    # --- dead air: seconds a viewer waits with nothing happening ---------
    lat = sorted(s["latency_ms"] for s in sp)
    slow = sum(1 for s in sp if s["latency_ms"] >= 10000)

    return {
        "condition": rec["condition"],
        "speeches": n,
        "challenge_rate": challenges / float(n),
        "concede_rate": concedes / float(n),
        "hedge_rate": hedges / float(n),
        "addresses_someone": addressed / float(n),
        "escalation": late - early,
        "opener_uniqueness": opener_uniqueness,
        "formulaic_openers": formulaic / float(n),
        "short_replies": short / float(n),
        "long_replies": long_ / float(n),
        "mean_words": sum(lens) / float(n),
        "topic_drift": drift,
        "truncation_rate": cut / float(n),
        "median_latency_ms": lat[len(lat) // 2],
        "waits_over_10s": slow / float(n),
    }


ROWS = [
    ("speeches", "speeches", "{:d}", None),
    ("challenge_rate", "challenges", "{:.1%}", "high"),
    ("concede_rate", "concessions", "{:.1%}", None),
    ("hedge_rate", "hedging", "{:.1%}", "low"),
    ("addresses_someone", "addresses someone", "{:.1%}", "high"),
    ("escalation", "escalation (late-early)", "{:+.2f}", "high"),
    ("opener_uniqueness", "opener uniqueness [guard]", "{:.2f}", "high"),
    ("formulaic_openers", "formulaic openers [guard]", "{:.1%}", "low"),
    ("short_replies", "replies <= 40 words", "{:.1%}", "high"),
    ("long_replies", "replies >= 90 words", "{:.1%}", "low"),
    ("mean_words", "mean words", "{:.1f}", None),
    ("truncation_rate", "truncated mid-thought", "{:.1%}", "low"),
    ("topic_drift", "topic drift", "{:.2f}", None),
    ("median_latency_ms", "median latency (ms)", "{:.0f}", "low"),
    ("waits_over_10s", "waits over 10s", "{:.1%}", "low"),
]


def main():
    recs = []
    for f in sorted(os.listdir(RUNS)):
        if f.endswith(".json") and not f.startswith("_"):
            recs.append(json.load(open(os.path.join(RUNS, f), encoding="utf-8")))
    res = [r for r in (analyse(x) for x in recs) if r]
    if not res:
        sys.exit("no runs in %s" % RUNS)

    conds = [r["condition"] for r in res]
    w = 27
    print("\nENTERTAINMENT STRUCTURE  (mechanical; not a fun-meter)\n")
    print("metric".ljust(w) + "".join(c.rjust(13) for c in conds) + "   better")
    print("-" * (w + 13 * len(conds) + 9))
    for key, label, fmt, better in ROWS:
        cells = "".join(fmt.format(r[key]).rjust(13) for r in res)
        print(label.ljust(w) + cells + "   "
              + {"high": "higher", "low": "lower"}.get(better, ""))
    print("\n[guard] metrics exist to catch interventions that raise conflict")
    print("        numbers by making every turn open the same way.")
    json.dump(res, open(os.path.join(RUNS, "_entertainment.json"), "w",
                        encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
