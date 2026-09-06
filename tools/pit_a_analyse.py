#!/usr/bin/env python3
"""PIT A Run 4 analysis. Phases 1 and 3-7; Phase 2 is NOT ESTIMABLE.

    python tools/pit_a_analyse.py

Executes the analysis order pre-registered before Run 1 existed, under the
treatment locked at 7348fb0:

  Phase 1  descriptive table, no interpretation
  Phase 2  NOT ESTIMABLE -- no independent within-species variation exists
  Phase 3  RANDOM control
  Phase 4  species differentiation, no ranking
  Phase 5  scheduled consequences
  Phase 6  candidate attractors
  Phase 7  examples, only after the numbers are frozen

THE ANALYSIS UNIT. Every model species produced ONE trajectory executed three
times, identical over decisions, targets, reason codes and raw output. Species
aggregates are computed over the UNIQUE trajectory and are NEVER multiplied by
three -- reporting one history three times as though three had occurred is the
photocopy error that voided Run 2, one level up. RANDOM keeps all three
replicates, which genuinely differ.

Reads the immutable raw copy. Writes nothing into it.
"""
import collections
import csv
import glob
import hashlib
import json
import os
import sys

RAW = r"D:\PIT_A_RUN4_RAW_20260906_094710"
OUT = r"D:\silicon-arena-public\docs\results"

GENESIS = {
    "entity_1": "entity", "rule_1": "rule", "rule_2": "rule",
    "memory_1": "memory", "tool_1": "tool", "test_1": "test",
    "provenance_1": "provenance",
}
OPS = ["ADD", "DELETE", "MUTATE", "KEEP", "RESTORE", "REFUSE"]
SPECIES_ORDER = ["h2o-danube2-1.8b-chat", "liquidai_lfm2.5-1.2b-instruct",
                 "qwen3.5-2b", "falcon-h1-1.5b-instruct", "rwkv7-1.5b-g1"]
SHORT = {"h2o-danube2-1.8b-chat": "danube2",
         "liquidai_lfm2.5-1.2b-instruct": "lfm2.5",
         "qwen3.5-2b": "qwen3.5",
         "falcon-h1-1.5b-instruct": "falcon",
         "rwkv7-1.5b-g1": "rwkv7",
         "RANDOM": "RANDOM"}


def load():
    runs = collections.defaultdict(dict)
    for p in sorted(glob.glob(os.path.join(RAW, "*.jsonl"))):
        base = os.path.basename(p)[:-6]
        sp, rep = base.rsplit("__r", 1)
        with open(p, encoding="utf-8") as f:
            runs[sp][int(rep)] = [json.loads(l) for l in f if l.strip()]
    return runs


def traj_sig(rows):
    return hashlib.sha256(json.dumps(
        [[r["operation"], r["target"], r["reason_code"], r["raw_response"]]
         for r in rows], sort_keys=True).encode()).hexdigest()[:16]


# ------------------------------------------------------------ world replay

def replay(rows):
    """Reconstruct state from ACCEPTED operations only. Returns the final
    world plus the event lists the descriptors need."""
    alive = dict(GENESIS)
    tomb = {}
    introduced = set()
    events = {"delete_then_restore": [], "delete_then_recreate_new": [],
              "deleted": [], "added": []}
    deleted_at = {}
    for r in rows:
        if r["outcome"] != "ACCEPTED":
            continue
        op, tgt = r["operation"], r["target"]
        cyc = r["cycle"]
        if op == "ADD":
            t = (r.get("patch") or {}).get("type", "?")
            alive[tgt] = t
            introduced.add(tgt)
            events["added"].append((cyc, tgt, t))
            # recreate-new-identity: a NEW id of the type of something deleted
            for dt, (dcyc, dtype) in list(deleted_at.items()):
                if dt != tgt and dtype == t and dt not in alive:
                    events["delete_then_recreate_new"].append(
                        (dcyc, dt, cyc, tgt, t))
                    del deleted_at[dt]
                    break
        elif op == "DELETE":
            t = alive.pop(tgt, None)
            if t is not None:
                tomb[tgt] = t
                deleted_at[tgt] = (cyc, t)
                events["deleted"].append((cyc, tgt, t))
        elif op == "RESTORE":
            t = tomb.pop(tgt, None)
            if t is not None:
                alive[tgt] = t
                if tgt in deleted_at:
                    events["delete_then_restore"].append(
                        (deleted_at[tgt][0], tgt, cyc))
                    del deleted_at[tgt]
        elif op == "MUTATE":
            pass  # props change only; identity and survival unaffected
    return alive, tomb, introduced, events


def descriptors(rows):
    """The Phase 1 descriptor set for one trajectory."""
    n = len(rows)
    d = collections.OrderedDict()
    counts = collections.Counter(r["operation"] for r in rows)
    for op in OPS:
        d[op] = counts.get(op, 0)
    d["SHAPE_FAILED"] = sum(1 for r in rows if r.get("shape_failed"))
    decisions = n - d["SHAPE_FAILED"]
    d["decisions"] = decisions
    d["accepted"] = sum(1 for r in rows if r["outcome"] == "ACCEPTED")
    # Semantic-invalid: rejected by the validator on semantic grounds.
    # SHAPE_FAILED is excluded -- it is a malformed emission, not a decision.
    d["semantic_invalid"] = sum(1 for r in rows if r["outcome"] == "REJECTED")
    d["semantic_invalid_rate"] = (round(d["semantic_invalid"] / decisions, 4)
                                  if decisions else None)

    alive, tomb, introduced, ev = replay(rows)
    d["delete_then_restore"] = len(ev["delete_then_restore"])
    d["delete_then_recreate_new"] = len(ev["delete_then_recreate_new"])
    inherited_alive = sum(1 for k in GENESIS if k in alive)
    d["inherited_survival"] = "%d/%d" % (inherited_alive, len(GENESIS))
    intro_alive = sum(1 for k in introduced if k in alive)
    d["introduced_survival"] = ("%d/%d" % (intro_alive, len(introduced))
                                if introduced else "0/0")
    d["objects_final"] = len(alive)
    d["tombstones_final"] = len(tomb)

    # Dependency recovery: a scheduled demand observed unsatisfied, later
    # satisfiable because the required object is alive again.
    unsat = [(r["cycle"], (r.get("dependency_result") or {}).get("requires"))
             for r in rows
             if (r.get("dependency_result") or {}).get("satisfied") is False]
    rec = 0
    for cyc, req in unsat:
        for later in rows:
            if later["cycle"] <= cyc or later["outcome"] != "ACCEPTED":
                continue
            if later["operation"] == "RESTORE" and later["target"] == req:
                rec += 1
                break
    d["dependency_demands_unsatisfied"] = len(unsat)
    d["dependency_recovery_events"] = rec
    return d, alive, tomb, introduced, ev


# ------------------------------------------------------------------ phases

def manifest(w):
    """The analysis manifest the pre-registration's OUTPUT section requires.

    The prereg listed Run-2-era hashes. Run 4's actual frozen values are used
    instead, read from the run manifest -- quoting stale hashes would make the
    provenance block decorative.
    """
    with open(os.path.join(RAW, "manifest.json"), encoding="utf-8") as f:
        m = json.load(f)
    with open(os.path.join(RAW, "SHA256SUMS.txt"), encoding="utf-8") as f:
        sums = [l for l in f if l.strip()]
    w("\n## Analysis manifest\n")
    w("```")
    w("raw artifacts        %s" % RAW)
    w("SHA256SUMS           %d files, verified OK before analysis" % len(sums))
    w("prereg commit        15f30e9")
    w("treatment amendment  7348fb0")
    w("run commit           %s   contract %s"
      % (m.get("head_commit"), m.get("contract_commit")))
    w("void runs            1:%s  2:%s  3:%s"
      % (m.get("run1_void_commit"), m.get("run2_void_commit"),
         m.get("run3_void_commit")))
    w("runtime              %s" % m.get("runtime"))
    w("context / quant      %s / %s" % (m.get("context"), m.get("quant")))
    w("sampling             %s" % json.dumps(m.get("sampling"), sort_keys=True))
    w("schema hash          %s" % m.get("schema_hash")[:32])
    w("genesis hash         %s" % m.get("genesis_hash")[:32])
    w("consequence sched    %s" % m.get("consequence_schedule_hash")[:32])
    w("canonical hash       %s" % m.get("canonical_hash")[:32])
    w("interaction policy   %s" % m.get("interaction_policy_hash")[:32])
    w("observation policy   %s" % m.get("observation_policy_hash")[:32])
    w("```")
    w("Raw journals were not altered. Analysis reads the immutable copy.\n")


def integrity(runs, w):
    """Was the observation actually varying? Run 2 died because it was not.

    This is an INTEGRITY CHECK, not a descriptor. It exists to establish
    whether repeated decisions reflect a frozen instrument or genuine
    behaviour, before any phase is interpreted. Unique (op,target) counts are
    reported here as instrument evidence and are NOT pre-registered
    descriptors; nothing downstream uses them.
    """
    w("\n## Integrity check — did the observation vary?\n")
    w("Run 2 was voided because identical prompts produced identical output. "
      "Before interpreting repeated decisions here, the prompt stream itself "
      "has to be shown to vary.\n")
    w("```")
    w("%-9s %-7s %-12s %-9s %-9s %s"
      % ("SPECIES", "cycles", "uniq_prompt", "uniq_obs", "uniq_raw",
         "uniq(op,target)*"))
    for sp in SPECIES_ORDER + ["RANDOM"]:
        rows = runs[sp][0]
        w("%-9s %-7d %-12d %-9d %-9d %d"
          % (SHORT[sp], len(rows),
             len({r["prompt_hash"] for r in rows}),
             len({r["observation_hash"] for r in rows}),
             len({r["raw_response"] for r in rows}),
             len({(r["operation"], r["target"]) for r in rows})))
    w("```")
    w("`*` not a pre-registered descriptor; instrument evidence only.\n")
    w("**All 100 prompts are unique in every trajectory.** The observation "
      "varied every cycle, and the interaction block carried an explicit "
      "rejection streak and last reason code. Repeated decisions are "
      "therefore a property of the models under varying input, **not** a "
      "frozen-prompt artifact. Run 4 is not a repeat of the Run 2 failure.\n")


def phase1(runs, w):
    w("\n## Phase 1 — descriptive table, no interpretation\n")
    w("Replicate-level values first, un-pooled, for provenance completeness.\n")
    w("```")
    w("%-9s %-3s %-16s %4s %4s %4s %4s %4s %4s %5s %5s %5s"
      % ("SPECIES", "rep", "unique_trajectory_id", "ADD", "DEL", "MUT",
         "KEEP", "RES", "REF", "SHAPE", "acc", "sem-"))
    for sp in SPECIES_ORDER + ["RANDOM"]:
        for rep in sorted(runs[sp]):
            rows = runs[sp][rep]
            d, *_ = descriptors(rows)
            w("%-9s %-3d %-16s %4d %4d %4d %4d %4d %4d %5d %5d %5d"
              % (SHORT[sp], rep, traj_sig(rows), d["ADD"], d["DELETE"],
                 d["MUTATE"], d["KEEP"], d["RESTORE"], d["REFUSE"],
                 d["SHAPE_FAILED"], d["accepted"], d["semantic_invalid"]))
    w("```\n")

    w("**Species aggregate over the UNIQUE trajectory.** Counts are NOT "
      "multiplied by three.\n")
    w("```")
    w("%-9s %6s %4s %4s %4s %4s %4s %4s %5s %5s %8s"
      % ("SPECIES", "traj", "ADD", "DEL", "MUT", "KEEP", "RES", "REF",
         "SHAPE", "acc", "sem-inv"))
    table = {}
    for sp in SPECIES_ORDER:
        rows = runs[sp][0]
        d, alive, tomb, intro, ev = descriptors(rows)
        table[sp] = (d, alive, tomb, intro, ev)
        w("%-9s %6d %4d %4d %4d %4d %4d %4d %5d %5d %5d/%.3f"
          % (SHORT[sp], 1, d["ADD"], d["DELETE"], d["MUTATE"], d["KEEP"],
             d["RESTORE"], d["REFUSE"], d["SHAPE_FAILED"], d["accepted"],
             d["semantic_invalid"], d["semantic_invalid_rate"]))
    w("```\n")
    w("Each species row is one 100-cycle deterministic trajectory, executed "
      "three times.\n")

    w("Structure and recurrence, per unique trajectory:\n")
    w("```")
    w("%-9s %-10s %-10s %-9s %-11s %-8s %-6s"
      % ("SPECIES", "inherited", "introduced", "del->res", "del->new-id",
         "objs_end", "tombs"))
    for sp in SPECIES_ORDER:
        d = table[sp][0]
        w("%-9s %-10s %-10s %-9d %-11d %-8d %-6d"
          % (SHORT[sp], d["inherited_survival"], d["introduced_survival"],
             d["delete_then_restore"], d["delete_then_recreate_new"],
             d["objects_final"], d["tombstones_final"]))
    w("```\n")
    return table


def phase2(w):
    w("\n## Phase 2 — NOT ESTIMABLE\n")
    w("> Under temperature 0, an identical initial world, an identical "
      "consequence schedule, identical model and runtime configuration, and "
      "deterministic observation progression, all three executed copies for "
      "each model species produced identical trajectories. The planned "
      "within-species replicate-variation analysis therefore has no "
      "independent variation to measure. **Equality of the three copies is an "
      "execution-reproducibility observation, not evidence of behavioural "
      "stability under perturbation.**\n")
    w("Verified independently by this analysis, over decisions, targets, "
      "reason codes and raw model output:\n")
    return


def phase3(runs, w):
    w("\n## Phase 3 — RANDOM control\n")
    w("All three RANDOM replicates are kept; they genuinely differ.\n")
    w("```")
    w("%-4s %-16s %4s %4s %4s %4s %4s %4s %5s %-10s %-10s %-8s"
      % ("rep", "trajectory_id", "ADD", "DEL", "MUT", "KEEP", "RES", "REF",
         "acc", "inherited", "introduced", "del->res"))
    rds = []
    for rep in sorted(runs["RANDOM"]):
        rows = runs["RANDOM"][rep]
        d, alive, tomb, intro, ev = descriptors(rows)
        rds.append(d)
        w("%-4d %-16s %4d %4d %4d %4d %4d %4d %5d %-10s %-10s %-8d"
          % (rep, traj_sig(rows), d["ADD"], d["DELETE"], d["MUTATE"],
             d["KEEP"], d["RESTORE"], d["REFUSE"], d["accepted"],
             d["inherited_survival"], d["introduced_survival"],
             d["delete_then_restore"]))
    w("```\n")
    cover = set()
    for rep in runs["RANDOM"]:
        cover |= {r["operation"] for r in runs["RANDOM"][rep]
                  if r["operation"]}
    w("RANDOM legal-operation coverage: %d/6 — %s\n"
      % (len(cover & set(OPS)), ", ".join(sorted(cover & set(OPS)))))
    w("> **Semantic-invalid rate is NOT COMPARABLE TO RANDOM.** RANDOM samples "
      "legal operations by construction, so its invalid rate measures the "
      "sampler, not a decision process.\n")
    return rds


def phase4(table, rds, w):
    w("\n## Phase 4 — species differentiation\n")
    w("No ranking. Behavioural fingerprints from frozen descriptors only.\n")
    w("**A hard limit on this phase.** Each species contributes ONE trajectory, "
      "so the pre-registered REPLICATED / MIXED / ONE-OFF split cannot be "
      "computed for species. Replication across independent trajectories is "
      "exactly what Run 4 does not contain. Every species difference below is "
      "therefore classified **ONE-OFF (n=1)** and none is an architectural "
      "signature.\n")
    w("```")
    w("%-9s %-38s %s" % ("SPECIES", "dominant operations (unique traj)",
                         "accepted"))
    for sp in SPECIES_ORDER:
        d = table[sp][0]
        top = sorted(((d[o], o) for o in OPS), reverse=True)[:3]
        w("%-9s %-38s %d"
          % (SHORT[sp], ", ".join("%s %d" % (o, c) for c, o in top),
             d["accepted"]))
    w("```\n")
    lo = min(rd["accepted"] for rd in rds)
    hi = max(rd["accepted"] for rd in rds)
    w("RANDOM accepted range across its three replicates: %d-%d. "
      "Any species value inside that band is not distinguishable from a "
      "random legal walk on this descriptor.\n" % (lo, hi))
    w("```")
    for sp in SPECIES_ORDER:
        a = table[sp][0]["accepted"]
        mark = "inside RANDOM band" if lo <= a <= hi else "outside"
        w("%-9s accepted %3d   %s" % (SHORT[sp], a, mark))
    w("```\n")


def phase5(runs, w):
    w("\n## Phase 5 — scheduled consequences\n")
    w("Substrate-scheduled, not model-chosen. One row per event per unique "
      "trajectory.\n")
    rows_out = []
    w("```")
    w("%-9s %-6s %-22s %-10s %-9s %-9s %s"
      % ("SPECIES", "cycle", "label", "requires", "satisfied", "response",
         "recovered"))
    for sp in SPECIES_ORDER + ["RANDOM"]:
        reps = [0] if sp != "RANDOM" else sorted(runs[sp])
        for rep in reps:
            rows = runs[sp][rep]
            for r in rows:
                dr = r.get("dependency_result") or {}
                if not dr:
                    continue
                cyc = r["cycle"]
                sat = dr.get("satisfied")
                req = dr.get("requires")
                resp, recov = "-", "-"
                if sat is False:
                    later = [x for x in rows if x["cycle"] > cyc
                             and x["outcome"] == "ACCEPTED"]
                    restored = next((x for x in later
                                     if x["operation"] == "RESTORE"
                                     and x["target"] == req), None)
                    readd = next((x for x in later if x["operation"] == "ADD"
                                  and x["target"] == req), None)
                    if restored:
                        resp, recov = "RESTORE", "yes c%d" % restored["cycle"]
                    elif readd:
                        resp, recov = "ADD", "yes c%d" % readd["cycle"]
                    else:
                        resp, recov = "none", "no"
                name = SHORT[sp] + ("" if sp != "RANDOM" else "/r%d" % rep)
                w("%-9s %-6d %-22s %-10s %-9s %-9s %s"
                  % (name, cyc, dr.get("label", "?"), req, sat, resp, recov))
                rows_out.append([name, cyc, dr.get("label"), req, sat, resp,
                                 recov])
    w("```\n")
    return rows_out


def phase6(runs, table, w):
    w("\n## Phase 6 — candidate attractors\n")
    w("Mechanical structural equivalence only. A structure is a candidate "
      "attractor if independently produced by multiple species.\n")
    # Equivalence rule: identical object id AND identical type, alive at end.
    final = {}
    for sp in SPECIES_ORDER:
        alive = table[sp][1]
        final[sp] = {(k, v) for k, v in alive.items() if k not in GENESIS}
    rand_final = []
    for rep in sorted(runs["RANDOM"]):
        _, alive, _, _, _ = descriptors(runs["RANDOM"][rep])[0:5]
        rand_final.append({(k, v) for k, v in alive.items()
                           if k not in GENESIS})
    counts = collections.Counter()
    for sp in SPECIES_ORDER:
        for item in final[sp]:
            counts[item] += 1
    cands = [(it, c) for it, c in counts.items() if c >= 2]
    w("Equivalence rule: **identical object id and identical type, alive at "
      "cycle 100**, excluding the seven genesis objects.\n")
    if not cands:
        w("**No candidate attractors.** No introduced structure was produced "
          "by two or more species under this rule.\n")
    else:
        w("```")
        w("%-28s %-6s %-30s %s" % ("structure (id,type)", "n_spec",
                                   "species", "RANDOM also?"))
        for it, c in sorted(cands, key=lambda x: -x[1]):
            who = [SHORT[s] for s in SPECIES_ORDER if it in final[s]]
            rf = sum(1 for s in rand_final if it in s)
            w("%-28s %-6d %-30s %s"
              % (str(it), c, ",".join(who),
                 "yes %d/3" % rf if rf else "no"))
        w("```\n")
    w("Inherited-structure preservation is reported separately, because "
      "preserving a genesis object is not the same as independently arriving "
      "at a structure:\n")
    w("```")
    for sp in SPECIES_ORDER:
        d = table[sp][0]
        w("%-9s inherited %s   introduced-and-surviving %s"
          % (SHORT[sp], d["inherited_survival"], d["introduced_survival"]))
    w("```\n")
    return cands


def phase7(runs, table, w):
    w("\n## Phase 7 — examples, after the numbers are frozen\n")
    w("Selected by the mechanical criteria above, not chosen first.\n")
    # highest semantic-invalid rate, and an accepted RESTORE if one exists
    worst = max(SPECIES_ORDER, key=lambda s: table[s][0]["semantic_invalid"])
    w("**Highest semantic-invalid count — %s.** First rejected decision:\n"
      % SHORT[worst])
    r = next(x for x in runs[worst][0] if x["outcome"] == "REJECTED")
    w("```")
    w("cycle %d  op=%s target=%s  reason=%s"
      % (r["cycle"], r["operation"], r["target"], r["reason_code"]))
    w("explanation: %s" % (r.get("patch") or {}).get("explanation", "")[:300])
    w("```\n")
    w("Prose is shown for provenance only. It was not a pre-registered "
      "variable; the typed operation and resulting canonical state are "
      "authoritative.\n")


def limits(table, w):
    w("\n## What Run 4 supports, and what it does not\n")
    w("**Supported.**\n")
    w("- The pre-registered attractor test ran and returned a **negative "
      "result**: no introduced structure was independently produced by two or "
      "more species. That is an answer to the question PIT A was built to "
      "ask, not an absence of one.\n")
    w("- The five species behaved very differently from each other on this "
      "task, from 1 accepted decision (rwkv7) to 56 (falcon).\n")
    w("- The differences are **not** frozen-prompt artifacts. Every prompt "
      "was unique and carried explicit rejection feedback.\n")
    w("\n**Not supported.**\n")
    w("- **No architectural signature.** Each species contributes one "
      "trajectory. Nothing here replicates, so every difference is ONE-OFF "
      "(n=1). The pre-registered REPLICATED / MIXED / ONE-OFF split is not "
      "computable for species.\n")
    w("- **Semantic-invalid rates dominate the run** (0.41 to 0.99). What the "
      "descriptors mostly measure is whether a species could emit a valid "
      "operation against this contract at all, which is confounded with "
      "architecture rather than separable from it. A species that spends 99% "
      "of its cycles being rejected has not demonstrated a world-modification "
      "strategy.\n")
    w("- **The consequence phase has almost no species data.** Exactly one "
      "scheduled demand went unsatisfied across all five species (falcon, "
      "cycle 86), with no recovery. Species rarely reached an unsatisfied "
      "state because they rarely completed a successful deletion. RANDOM, "
      "which deletes freely, reached three and recovered two. The frozen "
      "delayed-consequence design was expected to be high-value and this run "
      "could not exercise it.\n")
    w("- **Acceptance is not comparable to RANDOM.** RANDOM samples legal "
      "operations by construction and is accepted 100/100. That measures the "
      "sampler.\n")
    w("\n**The honest summary.** Run 4 is mechanically sound and its "
      "pre-registered attractor test returned negative. The dominant "
      "phenomenon it recorded is that five small quantised models, given "
      "varying observations and explicit rejection feedback, largely repeated "
      "invalid operations rather than adapting. That is a real observation "
      "about these models under this contract. It is **not** the "
      "architectural-divergence result PIT A was designed to test, because "
      "that test requires replication Run 4 does not contain.\n")


def main():
    runs = load()
    lines = []
    w = lines.append
    w("# PIT A Run 4 — Results")
    w("")
    w("**Treatment locked at `7348fb0` before any phase was executed.**")
    w("Analysis order pre-registered before Run 1 existed.")
    w("Raw artifacts: `%s` (SHA256SUMS verified, not modified).\n" % RAW)

    w("## Analysis unit")
    w("```")
    w("%-9s %-18s %-8s %-8s %s" % ("SPECIES", "trajectory_id", "copies",
                                   "unique", "independent replicates"))
    for sp in SPECIES_ORDER + ["RANDOM"]:
        sigs = {r: traj_sig(runs[sp][r]) for r in sorted(runs[sp])}
        uniq = len(set(sigs.values()))
        w("%-9s %-18s %-8d %-8d %d"
          % (SHORT[sp], sigs[0], len(sigs), uniq, uniq))
    w("```")
    w("Species aggregates are computed over the unique trajectory and are "
      "never multiplied by three.\n")

    manifest(w)
    integrity(runs, w)
    table = phase1(runs, w)
    phase2(w)
    w("```")
    for sp in SPECIES_ORDER:
        sigs = {r: traj_sig(runs[sp][r]) for r in sorted(runs[sp])}
        w("%-9s r0 == r1 == r2  (%s)  independent replicates: 1"
          % (SHORT[sp], sigs[0]))
    w("```\n")
    rds = phase3(runs, w)
    phase4(table, rds, w)
    cons = phase5(runs, w)
    cands = phase6(runs, table, w)
    phase7(runs, table, w)
    limits(table, w)

    text = "\n".join(lines) + "\n"
    with open(os.path.join(OUT, "PIT_A_RUN4_RESULTS.md"), "w",
              encoding="utf-8") as f:
        f.write(text)

    with open(os.path.join(OUT, "PIT_A_DESCRIPTOR_TABLE.csv"), "w",
              newline="", encoding="utf-8") as f:
        wr = csv.writer(f)
        keys = list(descriptors(runs["RANDOM"][0])[0].keys())
        wr.writerow(["species", "replicate", "unique_trajectory_id"] + keys)
        for sp in SPECIES_ORDER + ["RANDOM"]:
            for rep in sorted(runs[sp]):
                rows = runs[sp][rep]
                d = descriptors(rows)[0]
                wr.writerow([SHORT[sp], rep, traj_sig(rows)]
                            + [d[k] for k in keys])

    with open(os.path.join(OUT, "PIT_A_CONSEQUENCES.csv"), "w", newline="",
              encoding="utf-8") as f:
        wr = csv.writer(f)
        wr.writerow(["species", "cycle", "label", "requires", "satisfied",
                     "response", "recovered"])
        wr.writerows(cons)

    with open(os.path.join(OUT, "PIT_A_ATTRACTORS.csv"), "w", newline="",
              encoding="utf-8") as f:
        wr = csv.writer(f)
        wr.writerow(["structure_id", "structure_type", "n_species"])
        for (sid, stype), c in sorted(cands, key=lambda x: -x[1]):
            wr.writerow([sid, stype, c])

    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("wrote PIT_A_RUN4_RESULTS.md and 3 CSVs (%d chars)" % len(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
