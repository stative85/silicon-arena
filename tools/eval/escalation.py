#!/usr/bin/env python3
"""Does a debate become more adversarial as it goes, or merely continue?

    python tools/eval/escalation.py <run_label> [...]

Splits each run into early / middle / late thirds and reports the structural
signals in each, plus the late-minus-early slope.

Raw challenge rate has a ~54-point noise floor at 20-speech blocks
(EXPERIMENT_PIPELINE2.md), which makes it useless for comparing arms. A
WITHIN-RUN slope is a different quantity: both thirds come from the same run,
so whatever makes one run hotter than another affects early and late alike and
largely cancels.

That is a reason to expect the slope to be quieter, not proof that it is. Run
this over several identical-config runs first and read the spread of the slope
column before setting any threshold against it.
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
COMMIT = re.compile(r"\b(must|cannot|never|always|refuse|insist|will not|"
                    r"there is no|only if|i choose|i reject)\b", re.I)
FORMULAIC = re.compile(r"^\W*(as an ai|i (?:agree|disagree)|while |however|indeed|"
                       r"it is (?:true|important)|the question|in (?:my|this))", re.I)
STOP = set("""the a an and or but if then that this these those is are was were be been being
to of in on at by for with as from it its i you he she they we not no do does did have has had
will would can could should may might must there their them his her our your my me us am so
such what which who whom when where why how all any both each few more most other some only own
same very just also into about over under again further once because while during before after
above below up down out off between through""".split())


def words(t):
    return re.findall(r"[a-z']+", t.lower())


def content(t):
    return [w for w in words(t) if w not in STOP and len(w) > 3]


def norm(s):
    return re.sub(r"\s+", " ", s).strip().lower()


def segment(speeches, names, seen_before):
    n = len(speeches)
    if n == 0:
        return None
    openers = [" ".join(words(s["text"])[:4]) for s in speeches]
    uptake = 0
    for i in range(1, len(speeches)):
        prev = set(content(speeches[i - 1]["text"]))
        if speeches[i - 1]["speaker"] != speeches[i]["speaker"]:
            if prev & set(content(speeches[i]["text"])):
                uptake += 1
    return {
        "challenge": 100.0 * sum(1 for s in speeches if CHALLENGE.search(s["text"])) / n,
        "commit": 100.0 * sum(1 for s in speeches if COMMIT.search(s["text"])) / n,
        "addresses": 100.0 * sum(1 for s in speeches
                                 if any(norm(o) in norm(s["text"])
                                        for o in names if o != s["speaker"])) / n,
        "uptake": 100.0 * uptake / max(n - 1, 1),
        "formulaic": 100.0 * sum(1 for s in speeches if FORMULAIC.match(s["text"])) / n,
        "opener_uniq": len(set(openers)) / float(n),
    }


def analyse(label):
    rec = json.load(open(os.path.join(RUNS, label + ".json"), encoding="utf-8"))
    sp = rec["speeches"]
    if len(sp) < 9:
        return None
    names = sorted(set(s["speaker"] for s in sp))
    third = len(sp) // 3
    parts = [sp[:third], sp[third:2 * third], sp[2 * third:]]
    segs = [segment(p, names, None) for p in parts]
    out = {"label": label, "n": len(sp), "early": segs[0], "mid": segs[1], "late": segs[2]}
    out["slope"] = {k: segs[2][k] - segs[0][k] for k in segs[0]}
    return out


KEYS = ["challenge", "commit", "addresses", "uptake", "formulaic", "opener_uniq"]


def main():
    labels = sys.argv[1:]
    if not labels:
        print(__doc__)
        return 2
    rows = [r for r in (analyse(l) for l in labels) if r]
    if not rows:
        sys.exit("no usable runs")

    for r in rows:
        print("\n%s  (n=%d)" % (r["label"], r["n"]))
        print("  %-13s %8s %8s %8s %9s" % ("signal", "early", "mid", "late", "slope"))
        for k in KEYS:
            fmt = "%8.2f" if k == "opener_uniq" else "%8.1f"
            print("  %-13s" % k + fmt % r["early"][k] + fmt % r["mid"][k]
                  + fmt % r["late"][k] + ("%+9.2f" if k == "opener_uniq" else "%+9.1f") % r["slope"][k])

    if len(rows) > 1:
        print("\n\nSLOPE ACROSS %d RUNS  (late minus early)" % len(rows))
        print("  %-13s %8s %8s %8s   noise floor (2sd)" % ("signal", "mean", "sd", "range"))
        for k in KEYS:
            v = [r["slope"][k] for r in rows]
            sd = statistics.pstdev(v)
            print("  %-13s %8.2f %8.2f %8.2f   %.2f"
                  % (k, statistics.mean(v), sd, max(v) - min(v), 2 * sd))


if __name__ == "__main__":
    raise SystemExit(main())
