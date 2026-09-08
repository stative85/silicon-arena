"""Test runner with a mechanically enforced execution-contact classification.

    python tools/run_safe_tests.py                  # NO_CONTACT only (default)
    python tools/run_safe_tests.py --list           # show the classification
    python tools/run_safe_tests.py --contact ...    # refuses without clearance
    python tools/run_safe_tests.py --audit          # classification coverage

WHY THIS EXISTS. On 2026-09-07 a night shift under an explicit
"treat LM Studio as READ-ONLY / DO-NOT-CONTACT" boundary ran
`recovery_tooth_selftest.gd` as a routine regression check. That suite is not a
unit test: it performs real `lms unload` / `lms load` cycles and liveness
inference. Four recovery cycles and one model eviction happened before anyone
noticed.

**The boundary existed only in prose.** Nothing in the repository distinguished
a pure unit test from one that drives the runtime -- same directory, same
`*_selftest.gd` naming, same green output. Classification lived only in the head
of whoever wrote each suite.

THE CLASSIFICATION ITSELF FAILS CLOSED. Test-shaped files are DISCOVERED from
disk and cross-checked against the registry. An unclassified suite is a hard
error, not a warning -- otherwise someone adds `cool_new_test.gd` six months
from now, forgets to tag it, and this guard becomes decorative furniture.

CLASSES
    NO_CONTACT        pure logic; never reaches the network or the runtime
    CONTACT_REQUIRED  reads or drives LM Studio; needs explicit clearance
    STATE_MUTATING    changes runtime state (unload/reload/restart/inference);
                      additionally refuses UNATTENDED execution
"""

import argparse
import glob
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe")

NO_CONTACT = "NO_CONTACT"
CONTACT_REQUIRED = "CONTACT_REQUIRED"
STATE_MUTATING = "STATE_MUTATING"

SUITES = [
    {"name": "runtime_memory_selftest", "kind": "py", "cls": NO_CONTACT,
     "path": "tools/runtime_memory_selftest.py", "group": "core",
     "marker_allowance": {"kill": "declares taskkill as a FORBIDDEN pattern "
                                 "it scans the arm harness for"},
     "note": "static scan of the arm harness"},
    {"name": "backend_continuity", "kind": "py", "cls": NO_CONTACT,
     "path": "tools/backend_continuity.py", "group": "core", "args": ["--selftest"],
     "note": "pure functions over synthetic PID samples"},
    {"name": "result_loader", "kind": "py", "cls": NO_CONTACT,
     "path": "tools/result_loader.py", "group": "core", "args": ["--selftest"],
     "note": "eligibility rejection branches"},
    {"name": "recovery_schedule", "kind": "py", "cls": NO_CONTACT,
     "path": "tools/recovery_schedule.py", "group": "core", "args": ["--verify"],
     "note": "schedule plan verification, touches nothing"},
    {"name": "qwen_fossil_admissibility", "kind": "py", "cls": NO_CONTACT,
     "path": "tools/qwen_fossil_admissibility.py", "group": "core",
     "note": "fails closed; reads artifacts only", "expect_nonzero": True},
    {"name": "detector_audit_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/detector_audit_selftest.gd", "group": "core",
     "note": "pure classify() logic"},
    {"name": "failure_path_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/failure_path_selftest.gd", "group": "core",
     "note": "pins the night-shift static-review fixes"},
    {"name": "recovery_probe_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/recovery_probe_selftest.gd", "group": "core",
     "note": "record construction and validation, no calls"},
    {"name": "async_b_witness", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/async_b_witness.gd", "group": "core",
     "note": "representation maps, no model calls"},

    {"name": "recovery_tooth_selftest", "kind": "gd", "cls": STATE_MUTATING,
     "path": "tools/recovery_tooth_selftest.gd", "group": "core",
     "note": "4 real unload/reload cycles, a neighbour eviction, and "
             "liveness inference"},
    {"name": "gate4_sabotage", "kind": "py", "cls": STATE_MUTATING,
     "path": "tools/gate4_sabotage.py", "group": "core",
     "note": "unloads a model mid-replicate and runs a live arm"},
    {"name": "async_runtime_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/async_runtime_selftest.gd", "group": "core",
     "note": "drives AsyncRuntimeGuard directly, no runtime contact"},

    # ---- Pre-existing repo suites, classified by STATIC SCAN on 2026-09-07.
    # Absence of a marker is evidence, not proof: the audit re-runs the scan and
    # FAILS if anything registered NO_CONTACT shows a contact marker, which is
    # the dangerous direction.
    {"name": "async_harness_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/async_harness_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "async_runner_witness_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/async_runner_witness_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "async_step_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/async_step_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "async_world_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/async_world_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "bridge_selftest", "kind": "gd", "cls": CONTACT_REQUIRED,
     "path": "scripts/arena/bridge_selftest.gd", "group": "repo",
     "note": "static scan markers: bridge,http"},
    {"name": "cinematic_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/cinematic_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "coherence_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/coherence_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "compat_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/compat_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "compute_arbiter_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/compute_arbiter_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "contention_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/contention_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "dispute_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/dispute_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "entrypoint_parity_selftest", "kind": "gd", "cls": CONTACT_REQUIRED,
     "path": "scripts/arena/entrypoint_parity_selftest.gd", "group": "repo",
     "note": "static scan markers: http"},
    {"name": "gonzo_recall_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/gonzo_recall_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "metabolism_join_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/metabolism_join_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "model_policy_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/model_policy_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "pit_a_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/pit_a_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "pit_fuzz_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/pit_fuzz_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "presentation_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/presentation_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "scar_lattice_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/scar_lattice_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "speech_clean_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/speech_clean_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "sse_parser_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/sse_parser_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "swarm_bid_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/swarm_bid_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "swarm_request_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/swarm_request_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "swarm_resolver_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/swarm_resolver_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "targeting_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/targeting_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "topic_arc_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/topic_arc_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "turn_order_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/turn_order_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "vram_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "scripts/arena/vram_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "embed_router_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/embed_router_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "offline_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/offline_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
    {"name": "source_measure_selftest", "kind": "gd", "cls": NO_CONTACT,
     "path": "tools/source_measure_selftest.gd", "group": "repo",
     "note": "static scan markers: none"},
]

# Files that look like tests but are not suites this runner owns.
DISCOVERY_EXEMPT = {
    "tools/runtime_memory_run.py",      # orchestrator, not a test
    "tools/recovery_window.gd",         # executor, not a test
    "tools/rc_start_state.py",          # procedure, not a test
    "tools/run_safe_tests.py",          # this runner
    "tools/offline_selftest.gd",        # legacy aggregate runner
    "tools/embed_router_selftest.gd",
    "tools/source_measure_selftest.gd",
}

DISCOVERY_GLOBS = ["tools/*selftest*.py", "tools/*selftest*.gd",
                   "tools/*_test*.py", "tools/*_test*.gd",
                   "tools/*sabotage*.py", "tools/*sabotage*.gd",
                   "scripts/arena/*selftest*.gd"]


def discover():
    found = set()
    for g in DISCOVERY_GLOBS:
        for p in glob.glob(os.path.join(REPO, g)):
            rel = os.path.relpath(p, REPO).replace("\\", "/")
            if rel not in DISCOVERY_EXEMPT:
                found.add(rel)
    return found


# Static markers for runtime contact. Absence is EVIDENCE, not proof -- but a
# NO_CONTACT suite that shows one is a misclassification in the dangerous
# direction, so the audit refuses on it.
CONTACT_MARKERS = {
    "bridge": r"inference_bridge|InferenceBridge",
    "http": r"HTTPRequest|127[.]0[.]0[.]1:1234|http://localhost:1234",
    "lms": r"lms[.]exe|OS[.]execute[(]\s*LMS",
    "kill": r"taskkill",
}


def scan_markers(rel):
    full = os.path.join(REPO, rel)
    if not os.path.exists(full):
        return []
    src = open(full, encoding="utf-8", errors="replace").read()
    code = re.sub(r"#[^\n]*", "", src)       # scan code, not prose
    return [k for k, v in CONTACT_MARKERS.items() if re.search(v, code)]


def audit():
    """Fail closed: every discovered test-shaped file must be classified."""
    registered = {s["path"] for s in SUITES}
    found = discover()
    unclassified = sorted(found - registered)
    missing = sorted(p for p in registered
                     if not os.path.exists(os.path.join(REPO, p)))
    bad_class = [s["name"] for s in SUITES
                 if s["cls"] not in (NO_CONTACT, CONTACT_REQUIRED,
                                     STATE_MUTATING)]
    print("=== classification audit ===")
    print("registered %d, discovered %d" % (len(registered), len(found)))
    ok = True
    if unclassified:
        ok = False
        print("\nUNCLASSIFIED test-shaped files -- refusing:")
        for p in unclassified:
            print("    %s" % p)
        print("\n  Add it to SUITES with an explicit class, or to")
        print("  DISCOVERY_EXEMPT if it is not a test this runner owns.")
    if missing:
        ok = False
        print("\nREGISTERED but missing from disk:")
        for p in missing:
            print("    %s" % p)
    if bad_class:
        ok = False
        print("\nINVALID class on: %s" % ", ".join(bad_class))

    # MISCLASSIFICATION CHECK, in the dangerous direction only. A suite marked
    # NO_CONTACT that shows a contact marker is the failure that caused the
    # 2026-09-07 boundary violation, so the audit refuses on it.
    mis = []
    for suite in SUITES:
        if suite['cls'] != NO_CONTACT:
            continue
        hits = scan_markers(suite['path'])
        # A DOCUMENTED allowance, never a silent exemption. A scanner that
        # declares a forbidden pattern necessarily contains that pattern.
        allowed = suite.get('marker_allowance', {})
        hits = [h for h in hits if h not in allowed]
        if hits:
            mis.append((suite['name'], hits))
    if mis:
        ok = False
        print('')
        print('CLASSIFIED NO_CONTACT but shows contact markers -- refusing:')
        for nm, hits in mis:
            print('    %-34s %s' % (nm, ','.join(hits)))
    if ok:
        print("every discovered test-shaped file is classified")
    return ok


def run_one(s):
    if s["kind"] == "py":
        cmd = [sys.executable, os.path.join(REPO, s["path"])] + s.get("args", [])
    else:
        cmd = [GODOT, "--headless", "--path", REPO, "--script", s["path"]]
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=900)
    out = (r.stdout or "") + (r.stderr or "")
    tail = [ln for ln in out.splitlines()
            if any(k in ln for k in ("checks", "GREEN", "RED", "FAIL", "ok ",
                                     "ACCEPTED", "REJECTED", "FAILS CLOSED"))]
    ok = r.returncode == 0 or s.get("expect_nonzero", False)
    return ok, tail[-3:] if tail else out.splitlines()[-2:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--contact", action="store_true",
                    help="include CONTACT_REQUIRED suites")
    ap.add_argument("--i-have-clearance-to-contact-lm-studio",
                    action="store_true")
    ap.add_argument("--attended", action="store_true",
                    help="a human is present; required for STATE_MUTATING")
    a = ap.parse_args()

    if a.list:
        print("%-28s %-6s %-17s %s" % ("suite", "kind", "class", "note"))
        for s in sorted(SUITES, key=lambda x: (x["cls"], x["name"])):
            print("%-28s %-6s %-17s %s"
                  % (s["name"], s["kind"], s["cls"], s["note"]))
        return 0

    # The audit gates EVERY run. An unclassified suite stops the runner.
    if not audit():
        print("\nREFUSING TO RUN -- classification is incomplete.")
        return 1
    if a.audit:
        return 0

    clearance = a.i_have_clearance_to_contact_lm_studio
    want_contact = a.contact or clearance

    todo = [s for s in SUITES if s["cls"] == NO_CONTACT]
    skipped = [s for s in SUITES if s["cls"] != NO_CONTACT]

    if want_contact:
        if not clearance:
            print("\nThese suites reach the live runtime:")
            for s in skipped:
                print("  %-28s %-17s %s" % (s["name"], s["cls"], s["note"]))
            print("\nRefusing. Re-invoke with "
                  "--i-have-clearance-to-contact-lm-studio when a human has "
                  "cleared runtime contact.")
            return 1
        mutating = [s for s in skipped if s["cls"] == STATE_MUTATING]
        if mutating and not a.attended:
            print("\nSTATE_MUTATING suites refuse UNATTENDED execution:")
            for s in mutating:
                print("  %-28s %s" % (s["name"], s["note"]))
            print("\nThese change runtime state and can invalidate a live")
            print("experiment. Re-invoke with --attended only when a human is")
            print("actually present and the machine holds no scientific state.")
            return 1
        todo += skipped
        skipped = []

    print("\n=== running %d suite(s); %d withheld ===" % (len(todo), len(skipped)))
    failed = []
    for s in todo:
        ok, tail = run_one(s)
        print("\n[%s] %-26s %s" % ("PASS" if ok else "FAIL", s["name"], s["cls"]))
        for ln in tail:
            print("    %s" % ln.strip())
        if not ok:
            failed.append(s["name"])
    for s in skipped:
        print("\n[HELD] %-26s %s" % (s["name"], s["cls"]))

    print("\n=== %d passed, %d failed, %d withheld ==="
          % (len(todo) - len(failed), len(failed), len(skipped)))
    if failed:
        print("FAILED: %s" % ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
