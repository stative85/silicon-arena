#!/usr/bin/env python3
"""What does each model actually cost, and what resident sets fit a budget?

    python tools/vram_budget.py

WHY. Every VRAM figure in BENCH_RESIDENCY_RESULTS.md is `nvidia-smi
memory.used` -- total across ALL processes, desktop included. Sizing a bridge
budget against those numbers double-counts the desktop.

This measures:

  DESKTOP_BASELINE   VRAM held with zero models resident
  MARGINAL COST      the delta each model adds when loaded in sequence

Marginal cost is measured cumulatively, in load order, because that is how the
pool is actually built. It is NOT the same as a model's standalone footprint:
allocators reuse and economise, which is why five standalone footprints summing
to 10.4 GiB can co-reside in 7.7 GiB.

The budget is then:

    GPU_BUDGET = TOTAL - DESKTOP_RESERVE

where DESKTOP_RESERVE covers the desktop's PEAK, not its idle floor. An idle
Windows desktop sits near 0.6 GiB; a browser with hardware video decode and
compositing can take several times that. The reserve exists so the Arena never
claims memory the desktop is about to need.

No model quality claims. Does not modify PIT A, SWARM or METABOLISM.
"""
import builtins
import functools
import itertools
import json
import subprocess
import sys
import time
import urllib.request

print = functools.partial(builtins.print, flush=True)

BASE = "http://127.0.0.1:1234"
LMS = r"C:\Users\cleve\.lmstudio\bin\lms.exe"
CTX = 8192

MODELS = [
    "h2o-danube2-1.8b-chat",
    "liquidai/lfm2.5-1.2b-instruct",
    "qwen3.5-2b",
    "falcon-h1-1.5b-instruct",
    "rwkv7-1.5b-g1",
]
SHORT = {m: m.split("/")[-1].split("-")[0] for m in MODELS}

# Reserves to evaluate, MiB. 600 is roughly the measured idle desktop; the
# larger ones cover a browser with video decode and compositing.
RESERVES = [600, 1024, 1536, 2048]


def sh(args, timeout=600):
    return subprocess.run(args, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def vram():
    o = sh(["nvidia-smi", "--query-gpu=memory.used,memory.total",
            "--format=csv,noheader,nounits"], timeout=20)
    used, total = o.stdout.strip().split("\n")[0].split(",")
    return float(used.strip()), float(total.strip())


def resident():
    try:
        with urllib.request.urlopen(BASE + "/api/v0/models", timeout=30) as r:
            d = json.loads(r.read().decode())
        return sorted(m["id"] for m in d.get("data", [])
                      if m.get("state") != "not-loaded")
    except Exception:
        return []


def settle(seconds=3):
    time.sleep(seconds)


def main():
    print("=== VRAM budget: desktop baseline and marginal model cost ===\n")
    sh([LMS, "unload", "--all"], timeout=300)
    settle()
    if resident():
        print("models still resident after unload -- aborting")
        return 1

    baseline, total = vram()
    print("DESKTOP_BASELINE  %6.0f MiB   (zero models resident)" % baseline)
    print("TOTAL             %6.0f MiB\n" % total)
    print("NOTE: baseline is the desktop's current floor, not its peak. A")
    print("      browser with video decode will raise it substantially.\n")

    print("[MARGINAL COST] loading in sequence, delta per model")
    prev = baseline
    marginal = {}
    for m in MODELS:
        sh([LMS, "load", m, "--context-length", str(CTX), "--gpu", "max", "-y"])
        settle()
        used, _ = vram()
        delta = used - prev
        marginal[SHORT[m]] = delta
        print("   %-9s +%6.0f MiB   cumulative %6.0f MiB" % (SHORT[m], delta, used))
        prev = used

    pool_used = prev
    models_total = pool_used - baseline
    print("\n   models alone      %6.0f MiB   (pool %.0f - baseline %.0f)"
          % (models_total, pool_used, baseline))
    print("   free at full pool %6.0f MiB" % (total - pool_used))

    out = {"desktop_baseline_mib": baseline, "total_mib": total,
           "marginal_mib": marginal, "pool_used_mib": pool_used,
           "models_total_mib": models_total, "context": CTX, "sets": {}}

    print("\n[RESIDENT SETS] which combinations fit each reserve")
    print("   budget = total - reserve; a set fits if baseline + sum(marginal)")
    print("   <= budget. Marginal costs are order-dependent, so these are")
    print("   estimates to be confirmed by loading the chosen set.\n")

    for reserve in RESERVES:
        budget = total - reserve
        print("   reserve %4d MiB -> budget %6.0f MiB" % (reserve, budget))
        best = {}
        for size in (5, 4, 3, 2):
            fitting = []
            for combo in itertools.combinations(MODELS, size):
                cost = baseline + sum(marginal[SHORT[m]] for m in combo)
                if cost <= budget:
                    fitting.append(([SHORT[m] for m in combo], cost))
            fitting.sort(key=lambda x: x[1])
            if fitting:
                best[size] = fitting
                names, cost = fitting[0]
                print("      %d-model: %2d fit, cheapest %s = %.0f MiB"
                      % (size, len(fitting), "+".join(names), cost))
            else:
                print("      %d-model: none fit" % size)
        out["sets"][str(reserve)] = {
            str(k): [{"models": n, "mib": c} for n, c in v]
            for k, v in best.items()}

    with open("D:/vram_budget.json", "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    print("\nwrote D:/vram_budget.json")
    print("NOTE: this leaves all five loaded. Load the chosen set separately.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
