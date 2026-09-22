#!/usr/bin/env python3
"""Run the step 1a verb-access probe one species at a time.

    python tools/verb_access_serial.py --ctx 2048 --reps 3

WHY SERIAL. The pool form holds all five resident at ~7.6 GiB, which is
essentially the whole card, for as long as the probe runs. That is acceptable
for an unattended benchmark and unacceptable while the machine is in use. This
loads one species, probes it, unloads it, and moves on: ~1.1 GiB resident at
any moment.

WHAT IT COSTS. Solo residency is a DIFFERENT REGIME from the co-resident pool,
and the records say so (`residency_regime: SOLO_RESIDENCY`). The METABOLISM
correction established that two loading regimes on this box produce
opposite-looking results, so these records are never merged with pool records
as though they were the same measurement.

WHY THAT IS FINE FOR THIS GATE. Step 1a asks whether a species can REACH each
verb through the frozen interface. That is a property of the model and the
contract, not of how much VRAM its neighbours are using. What residency does
change is speed -- and speed is not what this gate measures. A verb that parses
solo and fails in-pool would be a placement problem, which is the sweep's job
and already has a detector.

No model-quality claims. No leaderboard.
"""
import argparse
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LMS = r"C:\Users\cleve\.lmstudio\bin\lms.exe"
SPECIES_FILE = os.path.join(REPO, "config", "arena-species.v1.json")
USERDATA = os.path.join(os.environ.get("APPDATA", ""), "Godot",
                        "app_userdata", "Silicon Arena")


def godot_bin():
    for env in ("GODOT_BIN", "GODOT"):
        p = os.environ.get(env, "")
        if p and os.path.isfile(p):
            return p
    guess = os.path.join(os.path.expanduser("~"), "OneDrive", "Documents",
                         "Documents", "Godot_v4.6-stable_win64.exe",
                         "Godot_v4.6-stable_win64.exe")
    return guess if os.path.isfile(guess) else "godot"


def roster():
    with open(SPECIES_FILE, encoding="utf-8") as f:
        return [(s["species_id"], s["model_id"])
                for s in json.load(f)["species"]]


def lms(*args, timeout=600):
    return subprocess.run([LMS] + list(args), capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def vram_mib():
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=20).stdout
        return int(out.strip().split()[0])
    except Exception:
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ctx", type=int, default=2048)
    ap.add_argument("--arms", default="LIVE",
                    help="comma separated: LIVE (the frozen union seam), "
                         "SCHEMA (per-operation, pins the verb), FREE "
                         "(unconstrained; currently measures prompt wording)")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--out", default=os.path.join(USERDATA,
                                                  "verb_access_serial.json"))
    a = ap.parse_args()

    gb = godot_bin()
    print("=== STEP 1a VERB ACCESS -- SOLO_RESIDENCY ===")
    print("one species resident at a time, context %d, %d reps"
          % (a.ctx, a.reps))
    print("godot: %s" % gb)
    print("idle VRAM before: %d MiB\n" % vram_mib())

    # Nothing else may be resident: a neighbour left loaded turns this into a
    # two-model regime that nothing would record.
    lms("unload", "--all")

    merged = {"gate": "STEP_1A_VERB_ACCESS", "residency_regime":
              "SOLO_RESIDENCY", "arms": a.arms.split(","),
              "context": a.ctx, "reps": a.reps,
              "per_species": {}, "matrix": {}, "records": []}
    failed_species = []

    for sid, mid in roster():
        print("[%s] loading %s at ctx %d" % (sid, mid, a.ctx))
        r = lms("load", mid, "--context-length", str(a.ctx), "--gpu", "max",
                "-y")
        if r.returncode != 0:
            print("  LOAD FAILED: %s" % (r.stderr or r.stdout)[:200])
            failed_species.append(sid)
            continue
        print("  resident, VRAM %d MiB -- probing 16 operations x 2 arms"
              % vram_mib())

        out_name = "verb_access_%s.json" % sid
        t0 = time.time()
        proc = subprocess.run(
            [gb, "--headless", "--path", REPO, "--script",
             "tools/breach_verb_access.gd", "--",
             "--ctx", str(a.ctx), "--reps", str(a.reps),
             "--arms", a.arms,
             "--only", sid, "--out", "user://" + out_name],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=5400)
        took = time.time() - t0

        for line in proc.stdout.splitlines():
            if "operations clean" in line or "ARM " in line:
                print("  " + line.strip())

        path = os.path.join(USERDATA, out_name)
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
            merged["matrix"].update(d.get("matrix", {}))
            merged["records"].extend(d.get("records", []))
            merged["per_species"][sid] = {"model_id": mid,
                                          "seconds": round(took, 1),
                                          "artifact": out_name}
            merged.setdefault("provenance", d.get("provenance", {}))
            m = d.get("measurements", {})
            prev = merged.setdefault("measurements", {"context_ceiling":
                                                     m.get("context_ceiling")})
            prev["max_prompt_tokens_observed"] = max(
                int(prev.get("max_prompt_tokens_observed", 0)),
                int(m.get("max_prompt_tokens_observed", 0)))
            if merged["provenance"] != d.get("provenance", {}):
                # Two species measured under different instrument state is not
                # one result. Record it rather than averaging over it.
                merged.setdefault("provenance_mismatch", []).append(sid)
        else:
            print("  NO ARTIFACT -- probe produced nothing")
            failed_species.append(sid)

        lms("unload", mid)
        print("  unloaded, VRAM %d MiB, %.0fs\n" % (vram_mib(), took))

    merged["species_without_result"] = failed_species
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=1)
    print("wrote %s" % a.out)
    print("idle VRAM after: %d MiB" % vram_mib())
    if failed_species:
        print("NO RESULT for: %s -- the matrix is PARTIAL"
              % ", ".join(failed_species))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
