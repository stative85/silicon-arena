"""Test runner with an explicit LM Studio contact classification.

    python tools/run_safe_tests.py              # NO-CONTACT suites only
    python tools/run_safe_tests.py --list       # show the classification
    python tools/run_safe_tests.py --contact    # refuses without clearance

WHY THIS EXISTS. On 2026-09-07 a night shift under an explicit
"treat LM Studio as READ-ONLY / DO-NOT-CONTACT" boundary ran
`recovery_tooth_selftest.gd` as a routine regression check. That suite is not a
unit test: it performs real `lms unload` / `lms load` cycles and liveness
inference. Four recovery cycles and one model eviction happened before anyone
noticed.

Nothing in the repository distinguished a pure unit test from one that drives
the runtime. The suites all look alike from the outside -- same directory, same
`*_selftest.gd` naming, same green output. Classification lived only in the
head of whoever wrote them.

So contact is declared here, per suite, and the default run executes ONLY the
no-contact set. A contact suite requires explicit clearance and says exactly
what it will do to the runtime before it does it.
"""

import argparse
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")

# kind: "gd" runs under Godot, "py" runs under Python.
# contact: what the suite does to the live runtime. NONE means it is safe under
# a do-not-contact boundary.
SUITES = [
    {"name": "runtime_memory_selftest", "kind": "py", "contact": "NONE",
     "path": "tools/runtime_memory_selftest.py",
     "note": "static scan of the arm harness"},
    {"name": "backend_continuity", "kind": "py", "contact": "NONE",
     "path": "tools/backend_continuity.py", "args": ["--selftest"],
     "note": "pure function tests over synthetic PID samples"},
    {"name": "result_loader", "kind": "py", "contact": "NONE",
     "path": "tools/result_loader.py", "args": ["--selftest"],
     "note": "eligibility rejection branches"},
    {"name": "recovery_schedule", "kind": "py", "contact": "NONE",
     "path": "tools/recovery_schedule.py", "args": ["--verify"],
     "note": "schedule plan verification, touches nothing"},
    {"name": "qwen_fossil_admissibility", "kind": "py", "contact": "NONE",
     "path": "tools/qwen_fossil_admissibility.py",
     "note": "fails closed; reads artifacts only", "expect_nonzero": True},
    {"name": "detector_audit_selftest", "kind": "gd", "contact": "NONE",
     "path": "tools/detector_audit_selftest.gd",
     "note": "pure classify() logic"},
    {"name": "failure_path_selftest", "kind": "gd", "contact": "NONE",
     "path": "tools/failure_path_selftest.gd",
     "note": "pins the night-shift static-review fixes"},
    {"name": "recovery_probe_selftest", "kind": "gd", "contact": "NONE",
     "path": "tools/recovery_probe_selftest.gd",
     "note": "record construction and validation, no calls"},
    {"name": "async_b_witness", "kind": "gd", "contact": "NONE",
     "path": "tools/async_b_witness.gd",
     "note": "representation maps, no model calls"},

    # ---- CONTACT SUITES. Not run by default.
    {"name": "recovery_tooth_selftest", "kind": "gd",
     "contact": "UNLOAD_RELOAD_MODELS + INFERENCE",
     "path": "tools/recovery_tooth_selftest.gd",
     "note": "performs 4 real recovery cycles and liveness calls; "
             "temporarily evicts a neighbour model"},
    {"name": "gate4_sabotage", "kind": "py",
     "contact": "UNLOAD_RELOAD_MODELS + FULL REPLICATE",
     "path": "tools/gate4_sabotage.py",
     "note": "unloads a model mid-replicate and runs a live arm"},
]


def run_one(s):
    if s["kind"] == "py":
        cmd = [sys.executable, os.path.join(REPO, s["path"])] + s.get("args", [])
    else:
        cmd = [GODOT, "--headless", "--path", REPO, "--script", s["path"]]
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=900)
    out = (r.stdout or "") + (r.stderr or "")
    tail = [ln for ln in out.splitlines()
            if any(k in ln for k in ("checks", "GREEN", "RED", "FAIL",
                                     "ACCEPTED", "REJECTED", "FAILS CLOSED"))]
    ok = r.returncode == 0 or s.get("expect_nonzero", False)
    return ok, tail[-3:] if tail else out.splitlines()[-2:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--contact", action="store_true",
                    help="attempt the contact suites (requires clearance)")
    ap.add_argument("--i-have-clearance-to-contact-lm-studio",
                    action="store_true")
    a = ap.parse_args()

    if a.list:
        print("%-28s %-8s %-36s %s" % ("suite", "kind", "contact", "note"))
        for s in SUITES:
            print("%-28s %-8s %-36s %s"
                  % (s["name"], s["kind"], s["contact"], s["note"]))
        return 0

    if a.contact and not a.i_have_clearance_to_contact_lm_studio:
        print("The contact suites drive the live runtime:")
        for s in SUITES:
            if s["contact"] != "NONE":
                print("  %-28s %s" % (s["name"], s["contact"]))
                print("      %s" % s["note"])
        print("\nRefusing. Re-invoke with --i-have-clearance-to-contact-lm-studio")
        print("only when a human has cleared runtime contact.")
        return 1

    todo = [s for s in SUITES
            if s["contact"] == "NONE" or a.i_have_clearance_to_contact_lm_studio]
    skipped = [s for s in SUITES if s not in todo]

    print("=== running %d suite(s); %d contact suite(s) skipped ==="
          % (len(todo), len(skipped)))
    failed = []
    for s in todo:
        ok, tail = run_one(s)
        print("\n[%s] %s" % ("PASS" if ok else "FAIL", s["name"]))
        for ln in tail:
            print("    %s" % ln.strip())
        if not ok:
            failed.append(s["name"])
    for s in skipped:
        print("\n[SKIP] %-26s contact: %s" % (s["name"], s["contact"]))

    print("\n=== %d passed, %d failed, %d skipped ==="
          % (len(todo) - len(failed), len(failed), len(skipped)))
    if failed:
        print("FAILED: %s" % ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
