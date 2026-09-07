"""Reconstruct the contention topology from ASYNC-A3's existing journals.

    python tools/async_contention_topology.py

NO NEW MODEL CALLS. Everything here is computed from artifacts already frozen by
the A3 run. This is mining, not measurement.

WHY. A3 showed that timing redistributes a fixed quantity of STALE_CONFLICT
(198 in both NATURAL and EQUALIZED) across agents. Contention decides how much
conflict exists; timing decides who pays. That means the object doing the
"deciding how much" -- the contention graph -- is worth building explicitly
rather than describing as a nuisance.

The graph is NOT a confound for the within-arm timing comparison: target
selection is fixed across NATURAL and EQUALIZED and does not vary with the
treatment, so it cannot manufacture the arm difference. It is an EFFECT
MODIFIER. It determines where timing has anything to act on.

WHAT IS DELIBERATELY NOT CONCLUDED. Stable selection over presented choices does
not tell us WHICH property drives it. Identifier preference, list-position
preference, availability-pattern preference and transition/cycling behaviour are
all consistent with the same frequency table. This script measures all four
separately so the question stays open rather than being answered by assumption.
"""

import json
import os
from collections import Counter, defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")
AG = {"agent_0": "lfm2.5", "agent_1": "qwen3.5", "agent_2": "falcon"}
ORDER = ["agent_0", "agent_1", "agent_2"]


def corpus(arm, exp="A3"):
    p = os.path.join(RESULTS, "ASYNC_%s_%s_r0_corpus.json" % (exp, arm))
    return json.load(open(p, encoding="utf-8"))["corpus"]


def rule(t):
    print("\n" + t)
    print("-" * len(t))


def selection_profile(rows, arm):
    """Identifier frequency vs visible-list-rank frequency, side by side.

    If a model's choices concentrate on particular IDs regardless of where they
    sit in the presented list, that is identifier preference. If they
    concentrate on particular ranks regardless of which ID occupies them, that
    is position preference. The two are separated here and nowhere else.
    """
    rule("SELECTION PROFILE — %s" % arm)
    ids = defaultdict(Counter)
    ranks = defaultdict(Counter)
    for x in rows:
        a = x["agent_id"]
        ids[a][x["chosen_target"]] += 1
        vis = x["visible_target_ids"]
        try:
            ranks[a][vis.index(x["chosen_target"])] += 1
        except ValueError:
            ranks[a]["not-visible"] += 1
    out = {}
    for a in ORDER:
        n = sum(ids[a].values()) or 1
        top_id = ids[a].most_common(4)
        top_rk = ranks[a].most_common(4)
        print("  %-8s n=%4d" % (AG[a], n))
        print("      by id    %s" % ", ".join("%s:%d" % kv for kv in top_id))
        print("      by rank  %s" % ", ".join("%s:%d" % kv for kv in top_rk))
        # concentration: share taken by the single most common id vs rank
        ci = top_id[0][1] / n if top_id else 0
        cr = top_rk[0][1] / n if top_rk else 0
        print("      top-1 share   id %.3f   rank %.3f" % (ci, cr))
        out[AG[a]] = {"by_id": dict(ids[a]),
                      "by_rank": {str(k): v for k, v in ranks[a].items()},
                      "top1_id_share": ci, "top1_rank_share": cr}
    return out


def transitions(rows, arm):
    """previous choice -> next choice, per agent."""
    rule("TRANSITION MATRIX — %s" % arm)
    seq = defaultdict(list)
    for x in sorted(rows, key=lambda r: (r["agent_id"], r["observed_tick"])):
        seq[x["agent_id"]].append(x["chosen_target"])
    out = {}
    for a in ORDER:
        s = seq[a]
        tr = Counter(zip(s, s[1:]))
        top = tr.most_common(6)
        det = sum(1 for (p, q), c in tr.items()) / max(len(set(s)), 1)
        print("  %-8s %d steps, %d distinct states, %.2f successors/state"
              % (AG[a], len(s), len(set(s)), det))
        print("      %s" % ", ".join("%s->%s:%d" % (p, q, c) for (p, q), c in top))
        out[AG[a]] = {"steps": len(s), "states": len(set(s)),
                      "successors_per_state": det,
                      "top": [["%s->%s" % (p, q), c] for (p, q), c in top]}
    return out


def contention_graph(rows, arm):
    """Edge weight = simultaneous same-target selections / simultaneous
    opportunities, for each unordered pair of agents.

    "Simultaneous" is the same observed_tick: both agents formed their view of
    the world at the same instant, so a same-target choice is a genuine
    collision rather than a sequential handover.
    """
    rule("CONTENTION GRAPH — %s" % arm)
    by_tick = defaultdict(dict)
    for x in rows:
        by_tick[x["observed_tick"]][x["agent_id"]] = x["chosen_target"]
    opp = Counter()
    coll = Counter()
    for t, m in by_tick.items():
        for i in range(len(ORDER)):
            for j in range(i + 1, len(ORDER)):
                a, b = ORDER[i], ORDER[j]
                if a in m and b in m:
                    opp[(a, b)] += 1
                    if m[a] == m[b]:
                        coll[(a, b)] += 1
    print("  %-20s %10s %10s %10s" % ("pair", "simul", "collisions", "rate"))
    out = {}
    for i in range(len(ORDER)):
        for j in range(i + 1, len(ORDER)):
            a, b = ORDER[i], ORDER[j]
            o, c = opp[(a, b)], coll[(a, b)]
            r = c / o if o else 0.0
            print("  %-20s %10d %10d %9.1f%%"
                  % ("%s-%s" % (AG[a], AG[b]), o, c, 100 * r))
            out["%s-%s" % (AG[a], AG[b])] = {"simultaneous": o,
                                             "collisions": c, "rate": r}
    return out


def stale_mechanism(rows, arm):
    """Separate the TWO sources of staleness.

    THE WINDOW HAS TO INCLUDE THE OBSERVATION TICK ITSELF. A first pass used
    the half-open window (observed_tick, applied_tick] and explained 100% of
    EQUALIZED but only 16.7% of NATURAL. That gap was the predictor being
    wrong, not NATURAL being mysterious: the world marks a target stale when
    `invalidated_at_version > observation.version`, which is a VERSION
    comparison, and an accept applied in the SAME tick as the observation but
    later in the within-tick order already carries a higher version. Under
    NATURAL the fast agent frequently takes the resource inside the observing
    agent's own tick, so the half-open window discarded most of the mechanism.

    With [observed_tick, applied_tick] and self excluded, both arms are
    explained at 100%.
    """
    rule("STALE MECHANISM - %s" % arm)
    acc = defaultdict(list)
    for x in rows:
        if x["outcome"] == "ACCEPTED":
            acc[x["chosen_target"]].append(
                (x["applied_tick"], x["agent_id"], x["request_id"]))
    for t in acc:
        acc[t].sort()
    stale = [x for x in rows if x["outcome"] == "STALE_CONFLICT"]
    acquisition = unexplained = 0
    winner = Counter()
    for x in stale:
        o, p, t = x["observed_tick"], x["applied_tick"], x["chosen_target"]
        hit = [(at, ag) for at, ag, rid in acc.get(t, [])
               if o <= at <= p and rid != x["request_id"]]
        if hit:
            acquisition += 1
            winner[hit[0][1]] += 1
        else:
            unexplained += 1
    n = len(stale) or 1
    print("  stale events                        %d" % len(stale))
    print("  explained by 'same target, taken first' %4d = %5.1f%%"
          % (acquisition, 100 * acquisition / n))
    print("  unexplained                          %4d" % unexplained)
    if winner:
        print("  agent that took the resource first:")
        for a, c in winner.most_common():
            print("      %-8s %4d  (%.1f%% of explained)"
                  % (AG[a], c, 100 * c / max(acquisition, 1)))
    return {"stale": len(stale), "acquisition_driven": acquisition,
            "unexplained": unexplained, "explained_rate": acquisition / n,
            "winner": {AG[a]: c for a, c in winner.items()}}


def rank_vs_identifier(report):
    """Is a model's stable selection a preference for IDENTIFIERS or for
    POSITIONS in the presented list?

    These are indistinguishable from a frequency table alone. They separate
    across arms: a position-driven model keeps the same rank while the ids under
    it change; an identifier-driven model keeps the same ids while their rank
    moves.
    """
    rule("IDENTIFIER PREFERENCE vs LIST-POSITION PREFERENCE")
    print("  %-10s %-28s %-28s" % ("", "top-1 RANK share by arm",
                                   "top-1 ID share by arm"))
    for m in ("lfm2.5", "qwen3.5", "falcon"):
        rk = []
        idd = []
        for arm in ("SERIAL", "NATURAL", "EQUALIZED"):
            s = report[arm]["selection"][m]
            rk.append("%.2f" % s["top1_rank_share"])
            idd.append("%.2f" % s["top1_id_share"])
        print("  %-10s %-28s %-28s" % (m, " ".join(rk), " ".join(idd)))
    print()
    print("  A model that holds a RANK constant while the ids under it change")
    print("  is position-driven. One that holds IDS constant while their rank")
    print("  moves is identifier-driven. Reported, not adjudicated: this is")
    print("  observational separation across three arms, not a manipulation.")



def collision_resolution(rows, arm):
    """For simultaneous same-target collisions, who won and how."""
    rule("COLLISION RESOLUTION — %s" % arm)
    by_tick = defaultdict(list)
    for x in rows:
        by_tick[x["observed_tick"]].append(x)
    won = Counter()
    lost = Counter()
    pairs = 0
    for t, xs in by_tick.items():
        seen = defaultdict(list)
        for x in xs:
            seen[x["chosen_target"]].append(x)
        for tgt, group in seen.items():
            if len(group) < 2:
                continue
            pairs += 1
            group.sort(key=lambda r: r["applied_tick"])
            for x in group:
                (won if x["outcome"] == "ACCEPTED" else lost)[x["agent_id"]] += 1
    print("  simultaneous same-target groups  %d" % pairs)
    print("  %-10s %8s %8s" % ("agent", "won", "lost"))
    for a in ORDER:
        print("  %-10s %8d %8d" % (AG[a], won[a], lost[a]))
    return {"groups": pairs,
            "won": {AG[a]: won[a] for a in ORDER},
            "lost": {AG[a]: lost[a] for a in ORDER}}


def main():
    report = {}
    for arm in ("SERIAL", "NATURAL", "EQUALIZED"):
        rows = corpus(arm)
        print("\n" + "=" * 64)
        print("ARM %s   (%d envelopes)" % (arm, len(rows)))
        print("=" * 64)
        report[arm] = {
            "selection": selection_profile(rows, arm),
            "transitions": transitions(rows, arm),
            "graph": contention_graph(rows, arm),
            "stale": stale_mechanism(rows, arm),
            "resolution": collision_resolution(rows, arm),
        }
    rank_vs_identifier(report)

    out = os.path.join(RESULTS, "ASYNC_A3_TOPOLOGY.json")
    json.dump(report, open(out, "w", encoding="utf-8"), indent=2)
    print("\nwrote %s" % os.path.relpath(out, REPO))


if __name__ == "__main__":
    main()
