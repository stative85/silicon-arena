"""ASYNC-A3 live run, frozen order, with the arm-boundary baseline.

    python tools/async_a3_run.py

Runs SERIAL, NATURAL, EQUALIZED, ORDER_REPLAY in that order. Before EVERY arm it
runs `tools/arm_baseline.py`, which verifies no stray runners, checks the
previous arm for an unresolved recovery, settles if that arm recovered a model,
restores the EXACT resident pool, checks the host-memory floor, and freezes a
resident-set witness.

If the baseline fails, the arm does not start. A voided arm does not get to hand
its recovery storm to the next arm as a starting condition.

Nothing here interprets anything. It runs the frozen order and preserves every
artifact.
"""

import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")
EXP = "A3"
ARMS = ["SERIAL", "NATURAL", "EQUALIZED", "ORDER_REPLAY"]
RESULTS = os.path.join(REPO, "docs", "results")


def manifest_path(arm):
    return os.path.join(RESULTS, "ASYNC_%s_%s_r0.json" % (EXP, arm))


def baseline(arm, prev_arm):
    cmd = [sys.executable, os.path.join(REPO, "tools", "arm_baseline.py"),
           "--witness", os.path.join(RESULTS, "A3_baseline_%s.json" % arm)]
    if prev_arm:
        cmd += ["--prev-manifest", manifest_path(prev_arm)]
    r = subprocess.run(cmd, cwd=REPO, text=True, encoding="utf-8",
                       errors="replace", capture_output=True)
    print(r.stdout, end="")
    if r.stderr:
        print(r.stderr, end="")
    return r.returncode == 0


def run_arm(arm):
    log = os.path.join(RESULTS, "async_a3_%s.log" % arm)
    with open(log, "w", encoding="utf-8") as fh:
        p = subprocess.run([GODOT, "--headless", "--path", REPO, "--script",
                            "tools/async_a_run.gd", "--",
                            "--arm=%s" % arm, "--exp=%s" % EXP],
                           cwd=REPO, stdout=fh, stderr=subprocess.STDOUT,
                           text=True, encoding="utf-8", errors="replace")
    out = open(log, encoding="utf-8", errors="replace").read()
    for ln in out.splitlines():
        if any(k in ln for k in ("outcomes", "actions ", "VOID", "teeth",
                                 "journal_hash", "final_world_hash",
                                 "shape_failed", "host free", "wrote ",
                                 "FAIL")):
            print("    %s" % ln.strip())
    return p.returncode


def main():
    print("=== ASYNC-A3 live run ===")
    print("frozen order: %s\n" % " -> ".join(ARMS))
    t0 = time.time()
    prev = None
    for arm in ARMS:
        print("\n########## %s ##########" % arm)
        if not baseline(arm, prev):
            print("\nBASELINE FAILED before %s. Stopping; the arm is not run."
                  % arm)
            return 1
        print("\n[arm %s]" % arm)
        rc = run_arm(arm)
        m = manifest_path(arm)
        if os.path.exists(m):
            d = json.load(open(m, encoding="utf-8"))
            print("    -> void=%s %s" % (d.get("void"), d.get("void_reasons")))
        else:
            print("    -> NO MANIFEST (exit %d)" % rc)
        prev = arm
    print("\nall arms complete in %.0f s" % (time.time() - t0))
    print("INTERPRET only after reviewing every artifact.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
