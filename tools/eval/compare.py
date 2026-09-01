#!/usr/bin/env python3
"""Combine mechanical metrics and judge scores into one report.

    python tools/eval/compare.py

Judges are reported SEPARATELY and their agreement is reported as a
measurement, never as a validation. Two models agreeing can mean the excerpts
really differ, or that both share a bias; this script cannot tell the two
apart and does not pretend to.
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNS = os.path.join(ROOT, "tools", "eval", "runs")
DIMENSIONS = ["coherence", "relevance", "distinctiveness", "argument_quality",
              "responsiveness", "entertainment"]


def mean(xs):
    xs = list(xs)
    return sum(xs) / float(len(xs)) if xs else float("nan")


def pearson(a, b):
    n = len(a)
    if n < 2:
        return float("nan")
    ma, mb = mean(a), mean(b)
    va = sum((x - ma) ** 2 for x in a)
    vb = sum((x - mb) ** 2 for x in b)
    if va <= 0 or vb <= 0:
        return float("nan")
    cov = sum((a[i] - ma) * (b[i] - mb) for i in range(n))
    return cov / math.sqrt(va * vb)


def ranks(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    r = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1
        for k in range(i, j + 1):
            r[order[k]] = avg
        i = j + 1
    return r


def spearman(a, b):
    return pearson(ranks(a), ranks(b))


def main():
    key = json.load(open(os.path.join(RUNS, "_blind_key.json"), encoding="utf-8"))
    metrics = json.load(open(os.path.join(RUNS, "_metrics.json"), encoding="utf-8"))
    judges = []
    for f in sorted(os.listdir(RUNS)):
        if f.startswith("_judge_") and f.endswith(".json"):
            judges.append(json.load(open(os.path.join(RUNS, f), encoding="utf-8")))
    if not judges:
        raise SystemExit("no judge files; run tools/eval/judge.py first")

    conds = sorted(set(v["condition"] for v in key.values()))

    print("\n" + "=" * 78)
    print("BLIND JUDGE SCORES  (1-5, each judge reported separately)")
    print("=" * 78)
    per_judge_cond = {}
    for J in judges:
        print("\nJUDGE %s   model=%s   scored %d excerpts, %d unusable"
              % (J["tag"], J["model"], J["scored"], len(J["unusable"])))
        print("  " + "dimension".ljust(20) + "".join(c.rjust(13) for c in conds))
        table = {}
        for d in DIMENSIONS:
            row = []
            for c in conds:
                vals = [s[d] for eid, s in J["scores"].items()
                        if key.get(eid, {}).get("condition") == c]
                row.append(mean(vals))
            table[d] = row
            print("  " + d.ljust(20) + "".join(("%.2f" % v).rjust(13) for v in row))
        overall = []
        for i, c in enumerate(conds):
            overall.append(mean([table[d][i] for d in DIMENSIONS]))
        print("  " + "OVERALL".ljust(20) + "".join(("%.2f" % v).rjust(13) for v in overall))
        best = conds[overall.index(max(overall))]
        print("  ranking: " + " > ".join(
            c for _, c in sorted(zip(overall, conds), reverse=True))
            + "     (best: %s)" % best)
        per_judge_cond[J["tag"]] = dict(zip(conds, overall))

    if len(judges) >= 2:
        print("\n" + "=" * 78)
        print("JUDGE AGREEMENT  (a measurement, not a validation)")
        print("=" * 78)
        A, B = judges[0], judges[1]
        common = sorted(set(A["scores"]) & set(B["scores"]))
        print("  excerpts scored by both: %d" % len(common))
        for d in DIMENSIONS + ["OVERALL"]:
            if d == "OVERALL":
                xa = [mean([A["scores"][e][k] for k in DIMENSIONS]) for e in common]
                xb = [mean([B["scores"][e][k] for k in DIMENSIONS]) for e in common]
            else:
                xa = [A["scores"][e][d] for e in common]
                xb = [B["scores"][e][d] for e in common]
            mad = mean([abs(xa[i] - xb[i]) for i in range(len(xa))])
            exact = mean([1.0 if abs(xa[i] - xb[i]) < 1e-9 else 0.0
                          for i in range(len(xa))])
            print("  %-18s pearson r=%6.3f   mean|diff|=%.2f   exact=%.0f%%   means %.2f / %.2f"
                  % (d, pearson(xa, xb), mad, exact * 100, mean(xa), mean(xb)))
        ca = [per_judge_cond[A["tag"]][c] for c in conds]
        cb = [per_judge_cond[B["tag"]][c] for c in conds]
        print("  condition-ranking spearman: %.3f" % spearman(ca, cb))
        agree = (conds[ca.index(max(ca))] == conds[cb.index(max(cb))])
        print("  judges pick the same best condition: %s" % ("YES" if agree else "NO"))

    print("\n" + "=" * 78)
    print("THROUGHPUT vs QUALITY")
    print("=" * 78)
    mm = {m["condition"]: m for m in metrics}
    print("  " + "condition".ljust(13) + "spm".rjust(8) + "fail".rjust(8)
          + "models".rjust(8) + "".join(("%s" % J["tag"]).rjust(9) for J in judges)
          + "useful/min".rjust(12))
    for c in conds:
        m = mm.get(c, {})
        spm = m.get("speeches_per_min", 0)
        cells = ""
        qs = []
        for J in judges:
            q = per_judge_cond[J["tag"]].get(c, float("nan"))
            qs.append(q)
            cells += ("%.2f" % q).rjust(9)
        # Useful debate per minute: speeches/min weighted by mean judged
        # quality on the 1-5 scale, normalised so 5/5 counts as 1.0.
        useful = spm * (mean(qs) / 5.0) if qs else 0.0
        print("  " + c.ljust(13) + ("%.2f" % spm).rjust(8)
              + ("%.0f%%" % (100 * m.get("failure_rate", 0))).rjust(8)
              + ("%d" % m.get("distinct_models", 0)).rjust(8) + cells
              + ("%.2f" % useful).rjust(12))
    print("\n  'useful/min' = speeches per minute x (mean judge score / 5).")
    print("  It is a derived convenience, not a measurement. Read the columns.")


if __name__ == "__main__":
    main()
