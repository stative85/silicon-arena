"""HEALTH-DUTY orchestrator.

    python tools/health_duty_run.py [--rounds 120]

Runs the frozen 3 x 2 design:

    LONG_CONTINUOUS   one process, all three regimes, run twice:
                      ascending 4,10,16 and descending 16,10,4
                      (counterbalances the length/elapsed-time confound that
                       HEALTH-SHORT had)

    CELL_LIKE         one FRESH client process per regime, arm_baseline before
                      each, exactly as an ASYNC-B cell is launched

CELL_LIKE resets the CLIENT only. LM Studio's process lifetime, caches and
resident duration persist -- no reload is performed to manufacture freshness,
because that would inject the recovery-coupling event into a Blocker 1
diagnostic.
"""

import argparse
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")
RESULTS = os.path.join(REPO, "docs", "results")
REGIMES = [16, 10, 4]


def baseline(tag):
    r = subprocess.run(
        [sys.executable, os.path.join(REPO, "tools", "arm_baseline.py"),
         "--witness", os.path.join(RESULTS, "HD_baseline_%s.json" % tag)],
        cwd=REPO, text=True, encoding="utf-8", errors="replace",
        capture_output=True)
    for ln in (r.stdout or "").splitlines():
        if any(k in ln for k in ("FAIL", "BASELINE", "host free")):
            print("      %s" % ln.strip())
    return r.returncode == 0


def run(args_list, tag, rounds):
    log = os.path.join(RESULTS, "health_duty_%s.log" % tag)
    with open(log, "w", encoding="utf-8") as fh:
        p = subprocess.run(
            [GODOT, "--headless", "--path", REPO, "--script",
             "tools/health_duty.gd", "--"] + args_list
            + ["--rounds=%d" % rounds, "--tag=%s" % tag],
            cwd=REPO, stdout=fh, stderr=subprocess.STDOUT, text=True,
            encoding="utf-8", errors="replace")
    out = open(log, encoding="utf-8", errors="replace").read()
    for ln in out.splitlines():
        if any(k in ln for k in ("FAIL", "PROBLEM", "wrote", "resident",
                                 "host free")):
            print("      %s" % ln.strip())
    return p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=120)
    args = ap.parse_args()

    print("=== HEALTH-DUTY ===")
    print("3 prompt regimes x 2 session structures, %d rounds each\n"
          % args.rounds)
    t0 = time.time()

    plan = [
        (["--arm=LONG", "--order=16,10,4"], "long_desc"),
        (["--arm=LONG", "--order=4,10,16"], "long_asc"),
    ] + [(["--arm=CELL", "--regime=%d" % n], "cell_%02d" % n)
         for n in REGIMES]

    for arglist, tag in plan:
        print("\n########## %s ##########" % tag)
        if not baseline(tag):
            print("BASELINE FAILED before %s. Stopping." % tag)
            return 1
        rc = run(arglist, tag, args.rounds)
        print("      exit %d" % rc)

    print("\nall runs complete in %.0f s" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
