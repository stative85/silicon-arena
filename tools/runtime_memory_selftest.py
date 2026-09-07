"""RUNTIME-MEMORY preflight teeth. NO LM STUDIO CONTACT, NO RESTART, NO CALLS.

    python tools/runtime_memory_selftest.py

Proves, before the first live arm and before the first of the four restarts:

  1. all four arms are declared and only the WORKLOAD differs
  2. every shared parameter is a CONSTANT in the arm script, not a per-arm knob
  3. the arm script CANNOT restart the backend -- no kill, no server start/stop,
     no unload-all, no LM Studio launch
  4. the arm script carries a live backend-PID witness and voids on change
  5. the client-disconnect phase is the ORCHESTRATOR's, measured, not cleanup
  6. the frozen preflight list is complete

Fails closed: any missing proof is a failure, not a warning.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARM = os.path.join(REPO, "tools", "runtime_memory.gd")
ORCH = os.path.join(REPO, "tools", "runtime_memory_run.py")

ARMS = ["IDLE", "CONTROL_WORKLOAD", "RECOVERY_ONLY", "FULL_WINDOW"]

# Things the ARM script must never be able to do. Backend lifetime belongs to
# the orchestrator and changes only at an arm boundary.
FORBIDDEN_IN_ARM = [
    (r"taskkill", "process kill"),
    (r"server\W+(start|stop)", "lms server start/stop"),
    (r"unload_all", "unload-all"),
    (r"LM Studio\.exe\"?\s*\]", "launching LM Studio"),
    (r"Program Files.*LM Studio", "LM Studio executable path"),
]

# Shared parameters that must be CONSTANTS in the arm script.
MUST_BE_CONST = ["WINDOW_MS", "SAMPLE_MS", "PROBE_LIST_LEN", "RECOVERY_AT_MS",
                 "POOL"]

FROZEN_PREFLIGHT = [
    "fresh backend required",
    "exact pool count map = 1/1/1",
    "same runtime/version",
    "same health surface",
    "same model load order",
    "same observation cadence",
    "same resource sampling cadence",
    "same duration / horizon",
    "same start-state witness schema",
    "same termination rules",
]

fails = []
checks = 0


def ck(label, cond, detail=""):
    global checks
    checks += 1
    if cond:
        print("  ok   %s" % label)
    else:
        fails.append(label)
        print("  FAIL %s %s" % (label, detail))


def main():
    if not os.path.exists(ARM):
        print("FAIL arm script missing")
        return 1
    arm_raw = open(ARM, encoding="utf-8").read()
    # SCAN CODE, NOT PROSE. The first version of this tooth matched the arm
    # script's own docstring saying "no server start/stop" and reported a
    # violation. A check that trips on its own documentation is a check that
    # will be silenced by whoever hits it next, so comments are stripped.
    arm_code = re.sub(r"#[^\n]*", "", arm_raw)
    arm = arm_raw
    orch = open(ORCH, encoding="utf-8").read() if os.path.exists(ORCH) else ""

    print("=== RUNTIME-MEMORY preflight ===")
    print("No LM Studio contact. No restart. No model calls.\n")

    print("[arms declared]")
    for a in ARMS:
        ck("arm %s declared" % a, ('"%s"' % a) in arm or ("%s :=" % a) in arm)

    print("\n[shared parameters are constants, not per-arm knobs]")
    for name in MUST_BE_CONST:
        ck("%s is const" % name,
           re.search(r"^const\s+%s" % name, arm, re.M) is not None)
    ck("only --arm and --windows are parsed",
       sorted(set(re.findall(r'begins_with\("(--[a-z-]+)=', arm)))
       == ["--arm", "--windows"],
       str(sorted(set(re.findall(r'begins_with\("(--[a-z-]+)=', arm)))))

    print("\n[the arm script CANNOT restart the backend]")
    for pat, what in FORBIDDEN_IN_ARM:
        found = re.search(pat, arm_code)
        ck("no %s in the arm script" % what, found is None,
           found.group(0) if found else "")

    print("\n[live backend-PID witness]")
    ck("captures backend pids at arm start", "_pids = _backend_pids()" in arm)
    ck("re-checks pids every sample", "_same_pids(pids, _pids)" in arm)
    ck("voids the arm on a mid-arm restart",
       "BACKEND_RESTARTED_MID_ARM" in arm)

    print("\n[client disconnect is a measured phase]")
    ck("arm takes a final live-client sample",
       '"final_live_client"' in arm)
    ck("arm does NOT claim to measure after its own exit",
       "cannot observe its own exit" in arm)
    ck("orchestrator exists", bool(orch), "tools/runtime_memory_run.py missing")
    if orch:
        ck("orchestrator samples after client exit",
           "post_disconnect" in orch)
        ck("orchestrator keeps the backend alive across that phase",
           "backend_alive_after_disconnect" in orch)
        ck("orchestrator restarts the backend ONLY at an arm boundary",
           orch.count("restart_backend(") <= 2,
           "%d call sites" % orch.count("restart_backend("))

    print("\n[frozen preflight list is complete]")
    for item in FROZEN_PREFLIGHT:
        ck("preflight declares: %s" % item,
           item.lower() in orch.lower() or item.lower() in arm.lower())

    print("\n[SUMMARY]")
    print("  checks %d, failures %d" % (checks, len(fails)))
    if fails:
        print("\nPREFLIGHT RED -- no live arm may run")
        return 1
    print("\nPREFLIGHT GREEN -- harness is built; running still requires")
    print("explicit clearance for the four backend restarts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
