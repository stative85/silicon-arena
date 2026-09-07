"""ASYNC-B orchestrator. 8 representation seeds x 4 cells, frozen Latin schedule.

    python tools/async_b_run.py [--seeds 0 1 2] [--cycles 200]

Execution structure is painfully explicit on purpose:

    for representation_seed in 0..7:
        for cell in frozen Latin order:
            run arm_baseline           (strays, prev-arm recovery, exact pool,
                                        memory floor, resident-set witness)
            run 200-tick SERIAL cell   (map hashes verified before and after,
                                        canonical-set invariant every tick)
            post-run                    zero stale, zero nonzero age, maps
                                        unchanged, runtime guard, seal journal

Artifacts are namespaced `ASYNC_B_seed00_A.json` and each manifest carries its
own `shared_order` / `shared_labels` booleans. **Analysis never infers the
condition from the filename letter.** Future software loves opportunities to
misunderstand us.
"""

import argparse
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")
RESULTS = os.path.join(REPO, "docs", "results")

# Frozen Latin rotation. Counterbalances execution position against condition so
# a drifting host cannot be mistaken for a representation effect.
SCHEDULE = {
    0: ["A", "B", "C", "D"], 1: ["B", "C", "D", "A"],
    2: ["C", "D", "A", "B"], 3: ["D", "A", "B", "C"],
    4: ["A", "B", "C", "D"], 5: ["B", "C", "D", "A"],
    6: ["C", "D", "A", "B"], 7: ["D", "A", "B", "C"],
}


def cell_path(seed, cell):
    return os.path.join(RESULTS, "ASYNC_B_seed%02d_%s.json" % (seed, cell))


def baseline(tag, prev):
    cmd = [sys.executable, os.path.join(REPO, "tools", "arm_baseline.py"),
           "--witness", os.path.join(RESULTS, "B_baseline_%s.json" % tag)]
    if prev:
        cmd += ["--prev-manifest", prev]
    r = subprocess.run(cmd, cwd=REPO, text=True, encoding="utf-8",
                       errors="replace", capture_output=True)
    tail = [ln for ln in (r.stdout or "").splitlines()
            if any(k in ln for k in ("FAIL", "BASELINE", "host free", "pool"))]
    for ln in tail:
        print("      %s" % ln.strip())
    return r.returncode == 0


def run_cell(seed, cell, cycles):
    log = os.path.join(RESULTS, "async_b_seed%02d_%s.log" % (seed, cell))
    with open(log, "w", encoding="utf-8") as fh:
        p = subprocess.run([GODOT, "--headless", "--path", REPO, "--script",
                            "tools/async_b_cell.gd", "--",
                            "--seed=%d" % seed, "--cell=%s" % cell,
                            "--cycles=%d" % cycles],
                           cwd=REPO, stdout=fh, stderr=subprocess.STDOUT,
                           text=True, encoding="utf-8", errors="replace")
    out = open(log, encoding="utf-8", errors="replace").read()
    for ln in out.splitlines():
        if any(k in ln for k in ("outcomes", "stale", "nonzero", "exercised",
                                 "VOID", "teeth", "FAIL", "host free")):
            print("      %s" % ln.strip())
    return p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="*",
                    default=list(range(8)))
    ap.add_argument("--cycles", type=int, default=200)
    args = ap.parse_args()

    print("=== ASYNC-B run ===")
    print("seeds  %s" % args.seeds)
    print("cycles %d per cell, SERIAL only\n" % args.cycles)

    t0 = time.time()
    prev = None
    position = {}          # execution position witness
    done, voided = 0, 0
    for seed in args.seeds:
        order = SCHEDULE[seed % 8]
        print("\n########## seed %02d   order %s ##########"
              % (seed, " ".join(order)))
        for pos, cell in enumerate(order, start=1):
            tag = "seed%02d_%s" % (seed, cell)
            print("\n  [%s]  execution position %d" % (tag, pos))
            if not baseline(tag, prev):
                print("  BASELINE FAILED before %s. Stopping." % tag)
                return 1
            rc = run_cell(seed, cell, args.cycles)
            p = cell_path(seed, cell)
            if os.path.exists(p):
                d = json.load(open(p, encoding="utf-8"))
                d_void = bool(d.get("void"))
                done += 1
                voided += 1 if d_void else 0
                print("      -> void=%s exercised=%s"
                      % (d_void, d.get("exercised")))
                position.setdefault(pos, []).append(
                    {"cell": cell, "seed": seed, "void": d_void})
            else:
                print("      -> NO MANIFEST (exit %d)" % rc)
            prev = p

    print("\n%d cells run, %d void, %.0f s" % (done, voided, time.time() - t0))
    json.dump({"schedule": SCHEDULE, "seeds": args.seeds,
               "cycles": args.cycles, "cells_run": done, "voided": voided,
               "by_execution_position": position},
              open(os.path.join(RESULTS, "ASYNC_B_RUN_INDEX.json"), "w",
                   encoding="utf-8"), indent=2)
    print("INTERPRET only after the mechanical topology pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
