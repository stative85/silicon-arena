"""ASYNC-A3 arm-boundary re-baseline. Run BETWEEN every live arm.

    python tools/arm_baseline.py --witness docs/results/A3_baseline_SERIAL.json

WHY. In ASYNC-A2 the arms were run back to back, and SERIAL voided on a runtime
health event whose two recovery reloads changed the host's memory state from
about 4.7 GB free to 15.4 GB before NATURAL started. NATURAL then inherited a
runtime regime that no arm-level check ever looked at. A voided arm must not be
allowed to silently mutate the conditions the next arm runs under.

THE CHECKLIST, in order:

    verify/restore the exact resident pool
    verify every model reports loaded
    verify no recovery is in progress
    verify the host-memory floor
    verify no stray runner processes
    freeze the resident-set witness
    then, and only then, start the arm

DELIBERATELY NO INFERENCE. Nothing here sends a completion request. A probe
would warm the model and the bridge, and cold start is part of the run as
defined -- warming it here would reintroduce exactly the blind spot that made
the A2 equalizer gate unable to predict its own experiment's void.

EXACT POOL, NOT "AT LEAST". The runner accepted any subset of `hot_set` that
was resident and had at least AGENTS members. The baseline requires the frozen
set exactly: an extra resident model changes contention for every model in the
pool, which the health expectation surface is conditioned on.
"""

import argparse
import ctypes
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_ENDPOINT = "http://127.0.0.1:1234/api/v0/models"
HOST_FLOOR_MB = 2048
CONTEXT = "8192"

# The frozen ASYNC-A2/A3 pool. Read from bridge_policy.gd so this file cannot
# drift away from what the runner actually uses.
POLICY = os.path.join(REPO, "scripts", "arena", "bridge_policy.gd")


def frozen_pool():
    """Parse hot_set out of bridge_policy.gd.

    The declaration is `var hot_set: Array[String] = [...]`, so scanning for the
    first "]" after the name finds the one in `Array[String]` and yields an
    EMPTY pool. An empty pool made this tool treat every resident model as
    "extra" and unload the entire arena. The list now starts at the "[" that
    follows "=", and main() refuses to touch residency if the parse looks wrong.
    """
    src = open(POLICY, encoding="utf-8").read()
    start = src.index("var hot_set")
    open_br = src.index("[", src.index("=", start))
    body = src[open_br:src.index("]", open_br)]
    return [ln.strip().strip('",	 ') for ln in body.splitlines()
            if ln.strip().startswith('"')]


def hash_set(ids):
    """Byte-identical to AsyncRuntimeGuard.hash_set()."""
    return hashlib.sha256("|".join(sorted(ids)).encode("utf-8")).hexdigest()[:16]


def lms(*args, timeout=300):
    return subprocess.run(["lms", *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def loaded_models():
    """Model ids the server reports as loaded. No inference."""
    try:
        with urllib.request.urlopen(MODELS_ENDPOINT, timeout=10) as r:
            data = json.loads(r.read().decode("utf-8"))
    except Exception as e:                       # noqa: BLE001
        print("  FAIL cannot reach %s: %s" % (MODELS_ENDPOINT, e))
        return None
    return [d.get("id", "") for d in data.get("data", [])
            if d.get("state", "not-loaded") != "not-loaded"]


def host_free_mb():
    class MS(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
    m = MS()
    m.dwLength = ctypes.sizeof(MS)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m.ullAvailPhys / (1024 * 1024)


def stray_runners():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Godot*"],
                         capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout or ""
    return [ln.split()[0] for ln in out.splitlines()
            if ln.lower().startswith("godot")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--witness", required=True,
                    help="path to write the frozen resident-set witness")
    ap.add_argument("--prev-manifest", default=None,
                    help="the arm that just finished, checked for unresolved "
                         "recovery")
    ap.add_argument("--settle-s", type=float, default=20.0,
                    help="quiet period after a previous arm's recovery")
    args = ap.parse_args()

    pool = frozen_pool()
    print("=== ASYNC-A3 arm boundary ===")
    print("frozen pool  %s\n" % pool)
    ok = True
    # A parse that yields an implausible pool must never reach the unload path.
    if len(pool) < 2:
        print("FAIL parsed %d models from bridge_policy.gd; refusing to touch"
              % len(pool))
        print("     residency on a pool this tool clearly failed to read")
        return 1

    # STRAYS FIRST. Loading or unloading while another runner is live would
    # corrupt that run, so this check precedes every mutation rather than
    # reporting the damage afterwards.
    stray = stray_runners()
    print("stray runners %s" % (stray if stray else "none"))
    if stray:
        print("  FAIL a runner is still alive; refusing to alter residency")
        return 1


    # 1. no recovery in progress, judged from the arm that just finished
    if args.prev_manifest and os.path.exists(args.prev_manifest):
        m = json.load(open(args.prev_manifest, encoding="utf-8"))
        evs = m.get("runtime", {}).get("runtime_events", [])
        recs = [e for e in evs if e.get("event_type") == "recovery"]
        unresolved = [e for e in evs
                      if e.get("state_after") == "RECOVERING"]
        finished = [e for e in evs if e.get("note") == "recovery succeeded"]
        print("previous arm  %s" % os.path.basename(args.prev_manifest))
        print("  recoveries %d, entered RECOVERING %d, completed %d"
              % (len(recs), len(unresolved), len(finished)))
        if len(unresolved) > len(finished):
            print("  FAIL a recovery was still in progress when the arm ended")
            ok = False
        if recs:
            print("  previous arm recovered a model; settling %.0f s"
                  % args.settle_s)
            time.sleep(args.settle_s)

    # 2. exact resident pool, restored if needed
    have = loaded_models()
    if have is None:
        return 1
    missing = [m for m in pool if m not in have]
    extra = [m for m in have if m not in pool]
    print("\nresident     %s" % sorted(have))
    if missing:
        print("  restoring missing: %s" % missing)
        for m in missing:
            lms("load", m, "--gpu=max", "--context-length=" + CONTEXT, "-y")
    if extra:
        print("  unloading extra:   %s" % extra)
        for m in extra:
            lms("unload", m)
    if missing or extra:
        time.sleep(3)
        have = loaded_models() or []
    if sorted(have) != sorted(pool):
        print("  FAIL pool is %s, wanted exactly %s" % (sorted(have), sorted(pool)))
        ok = False
    else:
        print("  pool exact")

    # 3. host memory floor
    free = host_free_mb()
    print("\nhost free    %.0f MB (floor %d MB)" % (free, HOST_FLOOR_MB))
    if free < HOST_FLOOR_MB:
        print("  FAIL below the frozen floor; the arm would risk an OOM void")
        ok = False

    # 5. freeze the witness
    w = {"frozen_pool": sorted(pool), "observed": sorted(have),
         "expected_resident_hash": hash_set(pool),
         "observed_resident_hash": hash_set(have),
         "host_free_mb": round(free),
         "host_floor_mb": HOST_FLOOR_MB,
         "stray_runners": stray,
         "baseline_ok": ok,
         "at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    os.makedirs(os.path.dirname(args.witness), exist_ok=True)
    json.dump(w, open(args.witness, "w", encoding="utf-8"), indent=2)
    print("\nwitness      %s  hash %s"
          % (os.path.relpath(args.witness, REPO), w["observed_resident_hash"]))
    print("\n%s" % ("BASELINE OK -- arm may start"
                    if ok else "BASELINE FAILED -- do not start the arm"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
