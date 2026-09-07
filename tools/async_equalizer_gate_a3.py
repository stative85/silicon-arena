"""ASYNC-A3 equalizer qualification. COLD START INCLUDED.

    python tools/async_equalizer_gate_a3.py

WHAT WAS WRONG WITH THE A2 GATE. `tools/async_equalizer_check.gd` fired a
warmup burst and discarded it before collecting its 200 bursts:

    # Warmup, discarded.
    for mid in _models:
        await _one(mid)
    _burst.clear()

The live runner has no warmup. Tick 0 is measured. So the gate excluded, by
construction, the exact runtime state that later voided the EQUALIZED arm --
three agents observing simultaneously and submitting into a cold bridge whose
`max_active = 2` makes the third wait for a slot.

The repair is to remove the warmup from the QUALIFICATION, not to add a warmup
to the experiment. Cold start is part of the run as currently defined, so the
feasibility gate must reproduce it.

HOW. Each trial is a FRESH PROCESS running the REAL runner for a few ticks.
Not a reimplementation of the submission path -- the actual `async_a_run.gd`,
the actual bridge, the actual payload, the actual clock. Between trials the
baseline is identical: models stay resident, and every trial gets a brand new
engine, a brand new bridge, and a brand new set of connections.

    fresh process -> real runner, 8 ticks -> record the tick-0 burst -> repeat

Then the existing FIRST-PASSING rule is applied to that corpus. Accept the
first declared candidate that survives; stop; do not look for a prettier
number. If 1000 ms survives, EQUALIZED_DELAY_TICKS stays 4.

NOTE ON WHAT THIS MEASURES NOW. A2's tick-0 breaches were caused by the world
clock never being anchored (`_run_start_ms` stayed 0, so tick 0's deadline sat
~410 ms before the run began). That is fixed in the runner. This gate therefore
measures the cold-start cost that is genuinely there -- queueing behind
`max_active` on a cold bridge -- rather than a measurement artifact.
"""

import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")

# Declared before any output.
CANDIDATES = [750, 1000, 1250, 1500, 2000]
TRIALS = 40
CYCLES = 8          # enough for the tick-0 burst to be released and applied
TICK_MS = 250
EXP = "EQG"
ARM = "EQUALIZED"
OUT = os.path.join(REPO, "docs", "results", "ASYNC_A3_EQUALIZER.json")


def trial(i):
    """One fresh-process first burst. Returns the tick-0 observation->completion
    times in ms, or None if the trial did not produce a usable burst."""
    cmd = [GODOT, "--headless", "--path", REPO, "--script",
           "tools/async_a_run.gd", "--",
           "--arm=%s" % ARM, "--exp=%s" % EXP, "--cycles=%d" % CYCLES]
    subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                   encoding="utf-8", errors="replace", timeout=180)
    man = os.path.join(REPO, "docs", "results",
                       "ASYNC_%s_%s_r0.json" % (EXP, ARM))
    cor = os.path.join(REPO, "docs", "results",
                       "ASYNC_%s_%s_r0_corpus.json" % (EXP, ARM))
    if not (os.path.exists(man) and os.path.exists(cor)):
        return None
    m = json.load(open(man, encoding="utf-8"))
    rows = json.load(open(cor, encoding="utf-8"))["corpus"]
    run_start = m.get("run_start_ms")
    if run_start is None:
        print("  trial %d: manifest has no run_start_ms; runner is stale" % i)
        return None
    first = [r for r in rows if r["observed_tick"] == 0]
    if not first:
        return None
    return [{"agent": r["agent_id"],
             "obs_to_completion_ms": r["completed_ms"] - run_start,
             "submit_offset_ms": r["submitted_ms"] - run_start,
             "service_ms": r["completed_ms"] - r["submitted_ms"]}
            for r in first]


def main():
    print("=== ASYNC-A3 equalizer qualification (cold start included) ===")
    print("No warmup. Every trial is a fresh process running the real runner.\n")
    print("candidates  %s ms" % CANDIDATES)
    print("trials      %d fresh starts, %d ticks each\n" % (TRIALS, CYCLES))

    bursts, samples = [], []
    t0 = time.time()
    for i in range(TRIALS):
        b = trial(i)
        if b is None:
            print("  trial %2d  no burst" % i)
            continue
        bursts.append(b)
        samples.extend(x["obs_to_completion_ms"] for x in b)
        print("  trial %2d  %s   (submit offset %d ms)"
              % (i, [x["obs_to_completion_ms"] for x in b],
                 b[0]["submit_offset_ms"]))
    print("\n%d first bursts, %d completions, %.0f s"
          % (len(bursts), len(samples), time.time() - t0))

    if not samples:
        print("NO DATA. Gate cannot decide; it does not guess.")
        return 1

    s = sorted(samples)
    n = len(s)
    print("\ntick-0 observation -> completion, cold:")
    print("  median %d   p95 %d   max %d"
          % (s[n // 2], s[min(int(n * 0.95), n - 1)], s[-1]))
    print("  top six: %s" % s[-6:])

    print("\nfirst candidate delay with zero breaches wins; no further search\n")
    print("  %-9s %9s  %s" % ("delay_ms", "breaches", ""))
    chosen = -1
    for cand in CANDIDATES:
        br = sum(1 for x in s if x > cand)
        mark = "<- PASS, taken" if br == 0 else "%d cold completions exceed it" % br
        print("  %-9d %9d  %s" % (cand, br, mark))
        if br == 0:
            chosen = cand
            break

    print("")
    if chosen < 0:
        print("NO CANDIDATE PASSED. The candidate list is NOT extended to")
        print("manufacture feasibility. EQUALIZED is not feasible at this")
        print("cold-start cost and that is the reportable result.")
    else:
        ticks = chosen // TICK_MS
        print("FROZEN EQUALIZER DELAY: %d ms = %d ticks" % (chosen, ticks))
        if chosen == 1000:
            print("  UNCHANGED -- 1000 ms survives cold start; "
                  "EQUALIZED_DELAY_TICKS stays 4")
        else:
            print("  CHANGED from 1000 ms. EQUALIZED_DELAY_TICKS becomes %d"
                  % ticks)

    json.dump({"candidates": CANDIDATES, "trials": TRIALS,
               "cycles_per_trial": CYCLES, "warmup": "NONE, deliberately",
               "bursts": len(bursts), "completions": len(samples),
               "median_ms": s[n // 2], "max_ms": s[-1],
               "chosen_delay_ms": chosen,
               "chosen_delay_ticks": (chosen // TICK_MS) if chosen > 0 else -1,
               "raw_bursts": bursts},
              open(OUT, "w", encoding="utf-8"), indent=2)
    print("\nwrote %s" % os.path.relpath(OUT, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
