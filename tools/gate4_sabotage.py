"""Gate 4 integration sabotage. THE LIVE RUNNER MUST VOID.

    python tools/gate4_sabotage.py

WHY THIS EXISTS. ASYNC-A2 shipped with `AsyncRuntimeGuard.on_residency_poll()`
and `finish()` fully implemented, covered by `async_runtime_selftest.gd`, and
never called by `tools/async_a_run.gd`. Every self-test passed. The live path
witnessed the resident pool once at R0 and never again.

A component test cannot catch that, because it drives the component directly.
This test refuses to touch the guard at all. It starts a real replicate, then
genuinely unloads a model out from under it with `lms unload` and loads it back
before the horizon, and asserts the RUNNER voided.

If someone later deletes the poll call from the tick loop, the guard's own
self-test still passes and this one fails. That is the whole point.
"""

import json
import os
import re
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")
EXP = "SAB"
ARM = "NATURAL"
CYCLES = 140          # 35 s at a 250 ms tick
CEILING_S = 540       # generous; a hang here is itself a finding
VICTIM = "qwen3.5-2b"
UNLOAD_AT_S = 8.0     # before the tick-40 poll at ~10 s
RELOAD_AT_S = 22.0    # after the tick-80 poll at ~20 s
MANIFEST = os.path.join(REPO, "docs", "results",
                        "ASYNC_%s_%s_r0.json" % (EXP, ARM))
LOGF = os.path.join(REPO, "docs", "results", "gate4_sabotage.log")


def lms(*args):
    return subprocess.run(["lms", *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=300)


def resident():
    out = lms("ps").stdout or ""
    return [ln.split()[0] for ln in out.splitlines()[2:] if ln.strip()]


def main():
    print("=== Gate 4 integration sabotage ===")
    print("The guard is never called directly. Only the runner is.\n")

    before = resident()
    print("resident before  %s" % before)
    if VICTIM not in before:
        print("FAIL victim %s is not resident; nothing to sabotage" % VICTIM)
        return 1

    if os.path.exists(MANIFEST):
        os.remove(MANIFEST)   # a SAB-namespaced artifact from a prior test run

    cmd = [GODOT, "--headless", "--path", REPO, "--script",
           "tools/async_a_run.gd", "--",
           "--arm=%s" % ARM, "--exp=%s" % EXP, "--cycles=%d" % CYCLES]
    print("launching  %s" % " ".join(cmd[-4:]))
    t0 = time.time()
    logh = open(LOGF, "w", encoding="utf-8")
    proc = subprocess.Popen(cmd, cwd=REPO, stdout=logh,
                            stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace")

    done_unload = done_reload = False
    while proc.poll() is None:
        el = time.time() - t0
        if not done_unload and el >= UNLOAD_AT_S:
            print("[%5.1fs] SABOTAGE: lms unload %s" % (el, VICTIM))
            print("          %s" % (lms("unload", VICTIM).returncode,))
            done_unload = True
        elif done_unload and not done_reload and el >= RELOAD_AT_S:
            print("[%5.1fs] RESTORE:  lms load %s" % (el, VICTIM))
            lms("load", VICTIM, "--gpu=max", "--context-length=8192", "-y")
            done_reload = True
        elif el > CEILING_S:
            proc.kill()
            print("FAIL runner did not finish within %d s" % CEILING_S)
            print("---- last runner output ----")
            for ln in (open(LOGF, encoding="utf-8", errors="replace")
                       .read().splitlines()[-25:]):
                print("  %s" % ln)
            return 1
        time.sleep(0.25)

    logh.close()
    log = open(LOGF, encoding="utf-8", errors="replace").read()
    rc = proc.returncode

    # Always put the pool back, pass or fail.
    if VICTIM not in resident():
        print("restoring %s" % VICTIM)
        lms("load", VICTIM, "--gpu=max", "--context-length=8192", "-y")

    print("\nrunner exit %d" % rc)
    for ln in log.splitlines():
        if re.search(r"VOID|FAIL|residency|teeth", ln):
            print("  %s" % ln.strip())

    if not os.path.exists(MANIFEST):
        print("\nFAIL no manifest written; cannot verify the guard ran")
        return 1
    m = json.load(open(MANIFEST, encoding="utf-8"))
    rt = m.get("runtime", {})
    reasons = m.get("void_reasons", [])
    polled = rt.get("observed_resident_hashes", [])
    end_set = rt.get("end_resident_set", [])

    print("\nvoid            %s" % m.get("void"))
    print("void_reasons    %s" % reasons)
    print("observed hashes %s" % polled)
    print("end_resident    %s" % end_set)

    ok = True
    if not m.get("void"):
        print("\nFAIL runner did NOT void while a model was absent")
        ok = False
    # The end witness must actually have run this time.
    if not end_set:
        print("FAIL end_resident_set empty -- finish() still not called")
        ok = False
    # More than one distinct residency hash proves the poll observed a change,
    # rather than the void coming only from the model-state signal path.
    if len(polled) < 2:
        print("NOTE only one residency hash observed; the void may have come")
        print("     from the model-state path rather than the poll")

    print("\n%s" % ("PASS -- the live runner voided" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
