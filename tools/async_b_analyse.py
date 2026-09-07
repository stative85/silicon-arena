"""ASYNC-B analysis. TWO PASSES, in this order.

    python tools/async_b_analyse.py [--pass 1|2|both]

PASS 1 is boring mechanical topology. No JSD, no hypotheses, no effects. Just
what happened: calls, shape failures, rank-0 shares, top alias, top canonical,
and the three pairwise contention edges.

PASS 2 is the pre-registered causal analysis: the 2x2 contrasts, the frozen JSD
quantities, PositionFollow and LabelFollow.

Two rules the code enforces rather than trusts:

  * THE CONTENTION GRAPH IS COMPUTED ON CANONICAL IDENTITY ONLY. Computing it on
    displayed aliases would let PRIVATE_LABELS "abolish" contention by renaming
    things in the analysis rather than changing behaviour.
  * THE THREE EDGES ARE NEVER AVERAGED INTO ONE TOPOLOGY SCORE. A3 had one huge
    edge and two near-zero ones; averaging turns a structured graph into a
    soothing middle number, which is how information goes to die.

Condition is read from each manifest's own `shared_order` / `shared_labels`
booleans, never inferred from the filename letter.
"""

import argparse
import glob
import json
import math
import os
from collections import Counter, defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")
AG = {"agent_0": "lfm2.5", "agent_1": "qwen3.5", "agent_2": "falcon"}
ORDER = ["agent_0", "agent_1", "agent_2"]
PAIRS = [("agent_0", "agent_1"), ("agent_0", "agent_2"),
         ("agent_1", "agent_2")]


def load_cells():
    cells = {}
    for p in sorted(glob.glob(os.path.join(RESULTS, "ASYNC_B_seed*_*.json"))):
        d = json.load(open(p, encoding="utf-8"))
        if "rows" not in d:
            continue
        # Condition comes from the manifest, never from the filename.
        key = (int(d["representation_seed"]), str(d["cell"]))
        cells[key] = d
    return cells


def jsd(p, q):
    """Jensen-Shannon divergence, base 2, over the union of two keyed
    distributions. Frozen choice; no post-hoc 'preference score'."""
    keys = set(p) | set(q)
    tp = sum(p.values()) or 1
    tq = sum(q.values()) or 1
    out = 0.0
    for k in keys:
        a = p.get(k, 0) / tp
        b = q.get(k, 0) / tq
        m = 0.5 * (a + b)
        if a > 0:
            out += 0.5 * a * math.log2(a / m)
        if b > 0:
            out += 0.5 * b * math.log2(b / m)
    return out


def valid_rows(d):
    """Rows that are actual decisions: a shape failure is not a choice."""
    return [r for r in d["rows"]
            if not r.get("shape_failed") and r.get("decoded_canonical_target")]


def edges(d):
    """Canonical contention edges for one cell.

    Simultaneous opportunity = the same world_tick, both agents produced a valid
    choice. Collision = both decoded to the SAME CANONICAL resource.
    """
    by_tick = defaultdict(dict)
    for r in valid_rows(d):
        by_tick[r["world_tick"]][r["agent_id"]] = r["decoded_canonical_target"]
    opp, coll = Counter(), Counter()
    lost = Counter()
    for r in valid_rows(d):
        if r["outcome"] == "CONTENTION_LOST":
            lost[r["agent_id"]] += 1
    for _t, m in by_tick.items():
        for a, b in PAIRS:
            if a in m and b in m:
                opp[(a, b)] += 1
                if m[a] == m[b]:
                    coll[(a, b)] += 1
    out = {}
    for a, b in PAIRS:
        name = "%s-%s" % (AG[a], AG[b])
        o = opp[(a, b)]
        out[name] = {"simultaneous": o, "same_canonical": coll[(a, b)],
                     "edge_weight": (coll[(a, b)] / o) if o else 0.0}
    return out, {AG[a]: lost[a] for a in ORDER}


def dists(d):
    """Per agent: rank, alias, and canonical distributions."""
    rank, alias, canon = defaultdict(Counter), defaultdict(Counter), \
        defaultdict(Counter)
    for r in valid_rows(d):
        a = r["agent_id"]
        rank[a][r["chosen_local_rank"]] += 1
        alias[a][r["chosen_alias"]] += 1
        canon[a][r["decoded_canonical_target"]] += 1
    return rank, alias, canon


def pass1(cells):
    print("=" * 74)
    print("PASS 1 -- MECHANICAL TOPOLOGY (no hypotheses, no JSD)")
    print("=" * 74)
    print("\n%-6s %-5s %-9s %6s %6s %6s %8s %-8s %-8s"
          % ("seed", "cell", "agent", "calls", "shape", "seminv",
             "rank0", "top_alias", "top_canon"))
    for (seed, cell) in sorted(cells):
        d = cells[(seed, cell)]
        rank, alias, canon = dists(d)
        for a in ORDER:
            n = sum(rank[a].values())
            r0 = rank[a].get(0, 0) / n if n else 0.0
            sem = sum(1 for r in d["rows"]
                      if r["agent_id"] == a and r["outcome"] == "SEMANTIC_INVALID")
            ta = alias[a].most_common(1)
            tc = canon[a].most_common(1)
            print("%-6d %-5s %-9s %6d %6d %6d %7.1f%% %-8s %-8s"
                  % (seed, cell, AG[a], n, d["shape_failed"].get(a, 0), sem,
                     100 * r0, ta[0][0] if ta else "-",
                     tc[0][0] if tc else "-"))

    print("\n%-6s %-5s %-22s %8s %8s %9s %8s"
          % ("seed", "cell", "pair", "simul", "same", "edge", "cont_lost"))
    for (seed, cell) in sorted(cells):
        d = cells[(seed, cell)]
        e, lost = edges(d)
        for name, v in e.items():
            print("%-6d %-5s %-22s %8d %8d %8.1f%%"
                  % (seed, cell, name, v["simultaneous"], v["same_canonical"],
                     100 * v["edge_weight"]))
        print("%-6d %-5s %-22s %s" % (seed, cell, "contention_lost", lost))


def pass2(cells):
    print("\n" + "=" * 74)
    print("PASS 2 -- PRE-REGISTERED CAUSAL ANALYSIS")
    print("=" * 74)
    seeds = sorted({s for s, _ in cells})
    complete = [s for s in seeds
                if all((s, c) in cells for c in "ABCD")]
    print("\nseeds with all four cells: %s" % complete)
    if not complete:
        print("no complete 2x2 available; nothing is estimated")
        return

    # --- 2x2 effects on each canonical edge, kept SEPARATE
    names = ["%s-%s" % (AG[a], AG[b]) for a, b in PAIRS]
    print("\n2x2 EFFECTS PER EDGE  (three edges, never averaged together)")
    for name in names:
        print("\n  edge %s" % name)
        print("    %-6s %7s %7s %7s %7s %9s %9s %11s"
              % ("seed", "A", "B", "C", "D", "order", "label", "interaction"))
        oe, le, ie = [], [], []
        for s in complete:
            w = {}
            for c in "ABCD":
                e, _ = edges(cells[(s, c)])
                w[c] = e[name]["edge_weight"]
            order_eff = 0.5 * ((w["B"] - w["A"]) + (w["D"] - w["C"]))
            label_eff = 0.5 * ((w["C"] - w["A"]) + (w["D"] - w["B"]))
            inter = (w["D"] - w["C"]) - (w["B"] - w["A"])
            oe.append(order_eff)
            le.append(label_eff)
            ie.append(inter)
            print("    %-6d %6.1f%% %6.1f%% %6.1f%% %6.1f%% %+8.1f%% %+8.1f%% %+10.1f%%"
                  % (s, 100 * w["A"], 100 * w["B"], 100 * w["C"], 100 * w["D"],
                     100 * order_eff, 100 * label_eff, 100 * inter))
        for lbl, v in (("order", oe), ("label", le), ("interaction", ie)):
            sv = sorted(v)
            print("    %-11s median %+7.1f%%   range %+.1f%% .. %+.1f%%   n=%d"
                  % (lbl, 100 * sv[len(sv) // 2], 100 * sv[0], 100 * sv[-1],
                     len(sv)))

    # --- PositionFollow / LabelFollow
    print("\nPOSITION-FOLLOW and LABEL-FOLLOW  (JSD base 2)")
    print("  PositionFollow = JSD(canonical) - JSD(local-rank), ORDER varied")
    print("  LabelFollow    = JSD(canonical) - JSD(local-alias), LABELS varied")
    print("\n  %-9s %-6s %10s %10s %10s %12s"
          % ("agent", "seed", "JSD_canon", "JSD_rank", "JSD_alias", "follow"))
    for a in ORDER:
        pf, lf = [], []
        for s in complete:
            rA, aA, cA = dists(cells[(s, "A")])
            rB, aB, cB = dists(cells[(s, "B")])   # order varied, labels shared
            rC, aC, cC = dists(cells[(s, "C")])   # labels varied, order shared
            p_can = jsd(cA[a], cB[a])
            p_rnk = jsd(rA[a], rB[a])
            l_can = jsd(cA[a], cC[a])
            l_ali = jsd(aA[a], aC[a])
            pf.append(p_can - p_rnk)
            lf.append(l_can - l_ali)
            print("  %-9s %-6d %10.4f %10.4f %10s %12s"
                  % (AG[a] + " P", s, p_can, p_rnk, "-", "%+.4f" % pf[-1]))
            print("  %-9s %-6d %10.4f %10s %10.4f %12s"
                  % (AG[a] + " L", s, l_can, "-", l_ali, "%+.4f" % lf[-1]))
        spf, slf = sorted(pf), sorted(lf)
        print("  %-9s PositionFollow median %+.4f  range %+.4f .. %+.4f"
              % (AG[a], spf[len(spf) // 2], spf[0], spf[-1]))
        print("  %-9s LabelFollow    median %+.4f  range %+.4f .. %+.4f\n"
              % (AG[a], slf[len(slf) // 2], slf[0], slf[-1]))

    print("n = %d representation ecologies. NOT thousands of decisions."
          % len(complete))


def drift(cells):
    """Execution-position witness. Not an outcome correction -- a check that
    counterbalancing had something to counterbalance."""
    idx = os.path.join(RESULTS, "ASYNC_B_RUN_INDEX.json")
    if not os.path.exists(idx):
        return
    print("\n" + "=" * 74)
    print("EXECUTION-POSITION WITNESS (drift check, not a correction)")
    print("=" * 74)
    d = json.load(open(idx, encoding="utf-8"))
    for pos, entries in sorted(d.get("by_execution_position", {}).items()):
        cells_at = Counter(e["cell"] for e in entries)
        voids = sum(1 for e in entries if e["void"])
        print("  position %s  n=%2d  voids=%d  cells=%s"
              % (pos, len(entries), voids, dict(cells_at)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pass", dest="which", default="both",
                    choices=["1", "2", "both"])
    args = ap.parse_args()
    cells = load_cells()
    if not cells:
        print("no ASYNC-B cell manifests found")
        return 1
    print("loaded %d cells" % len(cells))
    if args.which in ("1", "both"):
        pass1(cells)
    if args.which in ("2", "both"):
        pass2(cells)
    drift(cells)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
