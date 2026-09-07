"""RECOVERY-COUPLING step 1: the window scheduler. TOUCHES NOTHING.

    python tools/recovery_schedule.py            # emit + verify
    python tools/recovery_schedule.py --verify   # verify an existing schedule

No LM Studio contact, no HTTP, no inference, no residency call, no recovery.
This emits the frozen window plan and then checks it mechanically, so the
schedule is a reviewable artifact BEFORE any recovery logic exists.

The plan is deterministic: same inputs, same schedule, verifiable by hash.
"""

import argparse
import hashlib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "results", "RC_SCHEDULE.json")

MODELS = ["liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
          "falcon-h1-1.5b-instruct"]
SHORT = {"liquidai/lfm2.5-1.2b-instruct": "lfm2.5",
         "qwen3.5-2b": "qwen3.5",
         "falcon-h1-1.5b-instruct": "falcon"}

# Frozen in the prereg: minimum 10 treatment and 10 control windows per rotation
# position, alternating so slow host drift cannot align with condition.
WINDOWS_PER_CONDITION = 10
PRE_MS = 10000        # probe before the recovery instant
POST_MS = 30000       # probe after it; observed reloads ran 13-14 s
WINDOW_MS = PRE_MS + POST_MS
PROBE_LIST_LEN = 10   # fixed size, so the denominator cannot move


def build():
    """Rotation x condition, alternating T/C within each rotation position."""
    windows = []
    wid = 0
    for recovered in MODELS:
        neighbours = [m for m in MODELS if m != recovered]
        for i in range(WINDOWS_PER_CONDITION):
            for cond in ("TREATMENT", "CONTROL") if i % 2 == 0 \
                    else ("CONTROL", "TREATMENT"):
                windows.append({
                    "window_id": wid,
                    "recovered_model": recovered,
                    "neighbours": neighbours,
                    "condition": cond,
                    "pair_index": i,
                    "pre_ms": PRE_MS,
                    "post_ms": POST_MS,
                    "recovery_at_ms": PRE_MS if cond == "TREATMENT" else -1,
                    "probe_list_len": PROBE_LIST_LEN,
                })
                wid += 1
    return windows


def schedule_hash(windows):
    body = json.dumps(windows, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(body.encode("utf-8")).hexdigest()[:16]


def verify(windows):
    """Mechanical checks. Every one must pass before recovery logic exists."""
    fails = []

    # counts per rotation position and condition
    for m in MODELS:
        for cond in ("TREATMENT", "CONTROL"):
            n = sum(1 for w in windows
                    if w["recovered_model"] == m and w["condition"] == cond)
            if n != WINDOWS_PER_CONDITION:
                fails.append("rotation %s %s has %d windows, wanted %d"
                             % (SHORT[m], cond, n, WINDOWS_PER_CONDITION))

    # a recovered model is never its own neighbour
    for w in windows:
        if w["recovered_model"] in w["neighbours"]:
            fails.append("window %d probes the recovered model" % w["window_id"])
        if len(w["neighbours"]) != 2:
            fails.append("window %d has %d neighbours"
                         % (w["window_id"], len(w["neighbours"])))

    # alternation: no rotation position may run 3+ of the same condition in a row
    for m in MODELS:
        seq = [w["condition"] for w in windows if w["recovered_model"] == m]
        run = 1
        for i in range(1, len(seq)):
            run = run + 1 if seq[i] == seq[i - 1] else 1
            if run >= 3:
                fails.append("rotation %s has a run of %d identical conditions"
                             % (SHORT[m], run))
                break

    # CONTROL windows must carry no recovery instant
    for w in windows:
        if w["condition"] == "CONTROL" and w["recovery_at_ms"] != -1:
            fails.append("window %d is CONTROL but schedules a recovery"
                         % w["window_id"])
        if w["condition"] == "TREATMENT" and w["recovery_at_ms"] != PRE_MS:
            fails.append("window %d is TREATMENT with a bad recovery instant"
                         % w["window_id"])

    # ids contiguous
    ids = [w["window_id"] for w in windows]
    if ids != list(range(len(windows))):
        fails.append("window ids are not contiguous")

    # determinism
    if schedule_hash(windows) != schedule_hash(build()):
        fails.append("schedule is not deterministic")

    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true",
                    help="verify the existing schedule instead of rebuilding")
    args = ap.parse_args()

    if args.verify:
        if not os.path.exists(OUT):
            print("FAIL no schedule at %s" % OUT)
            return 1
        doc = json.load(open(OUT, encoding="utf-8"))
        windows = doc["windows"]
    else:
        windows = build()
        doc = {
            "models": MODELS, "windows_per_condition": WINDOWS_PER_CONDITION,
            "pre_ms": PRE_MS, "post_ms": POST_MS, "window_ms": WINDOW_MS,
            "probe_list_len": PROBE_LIST_LEN,
            "schedule_hash": schedule_hash(windows),
            "windows": windows,
        }

    print("=== RECOVERY-COUPLING schedule ===")
    print("NO LM Studio contact. Plan only.\n")
    print("rotation positions   %d" % len(MODELS))
    print("windows per cond     %d" % WINDOWS_PER_CONDITION)
    print("total windows        %d" % len(windows))
    print("window               %d ms pre + %d ms post = %d ms"
          % (PRE_MS, POST_MS, WINDOW_MS))
    print("probe list length    %d (fixed)" % PROBE_LIST_LEN)
    print("schedule hash        %s\n" % schedule_hash(windows))

    print("first 8 windows:")
    print("  %-4s %-9s %-11s %-24s" % ("id", "recovered", "condition",
                                       "neighbours"))
    for w in windows[:8]:
        print("  %-4d %-9s %-11s %-24s"
              % (w["window_id"], SHORT[w["recovered_model"]], w["condition"],
                 ",".join(SHORT[n] for n in w["neighbours"])))

    fails = verify(windows)
    print("\n[VERIFY]")
    if fails:
        for f in fails:
            print("  FAIL %s" % f)
        print("\nSCHEDULE REJECTED")
        return 1
    print("  counts per rotation x condition   OK")
    print("  recovered model never probed      OK")
    print("  two neighbours per window         OK")
    print("  no run of 3 identical conditions  OK")
    print("  CONTROL carries no recovery       OK")
    print("  ids contiguous, plan deterministic OK")

    if not args.verify:
        json.dump(doc, open(OUT, "w", encoding="utf-8"), indent=2)
        print("\nwrote %s" % os.path.relpath(OUT, REPO))
    print("\nSCHEDULE ACCEPTED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
