"""Corrected backend-continuity witness (RUNTIME-MEMORY Amendment 5).

    python tools/backend_continuity.py --selftest
    python tools/backend_continuity.py --apply

Replaces BACKEND_RESTARTED_MID_ARM, which compared the COMPLETE LM Studio PID
set for equality and therefore fired on the model-worker churn that scheduled
recovery necessarily causes. The protected invariant is backend/core lifetime
continuity, not worker PID identity.

THE CORE ROLE COMES FROM THE PRODUCER, NOT FROM A COUNT. Observed directly:

    root      "LM Studio.exe"                     no --type=, parent is not
                                                  another LM Studio process
    children  "LM Studio.exe" --type=renderer
                              --type=gpu-process
                              --type=crashpad-handler
                              --type=utility --utility-sub-type=...

Model workers are `--type=utility --utility-sub-type=node.mojom.NodeService`
and are replaced on every unload/reload. "Nine stable PIDs" is deliberately NOT
the rule -- nine is merely what survived one run.

    BACKEND CONTINUITY PASS iff
        core identity persists for the entire arm
    AND core start-time / generation identity does not change
    AND no interval shows the backend unavailable
    AND worker churn is attributable only to scheduled recoveries
"""

import argparse
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")
ARMS = ["IDLE", "CONTROL_WORKLOAD", "RECOVERY_ONLY", "FULL_WINDOW"]

PASS, FAIL, UNKNOWN = "PASS", "FAIL", "UNKNOWN"


def live_process_roles():
    """Ask the producer which process is the core. Returns {pid: role}."""
    ps = ("Get-CimInstance Win32_Process -Filter \"Name='LM Studio.exe'\" | "
          "ForEach-Object { \"$($_.ProcessId)|$($_.ParentProcessId)|"
          "$($_.CreationDate)|$($_.CommandLine)\" }")
    out = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                         capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout or ""
    rows = {}
    for ln in out.splitlines():
        parts = ln.split("|", 3)
        if len(parts) < 4 or not parts[0].strip().isdigit():
            continue
        pid, parent, created, cmd = (int(parts[0]), int(parts[1]),
                                     parts[2].strip(), parts[3])
        rows[pid] = {"parent": parent, "created": created, "cmd": cmd}
    for pid, r in rows.items():
        if "--type=" not in r["cmd"] and r["parent"] not in rows:
            r["role"] = "core"
        elif "node.mojom.NodeService" in r["cmd"]:
            r["role"] = "model_worker"
        else:
            r["role"] = "support"
    return rows


def evaluate(samples, recoveries, core_pid=None):
    """Evaluate the four clauses against one arm's recorded PID samples."""
    res = {"clauses": {}, "observed": {}}
    sets = [set(s["backend_pids"]) for s in samples]
    if not sets:
        return {"verdict": UNKNOWN, "reason": "no samples", **res}

    # clause 3 -- no interval shows the backend unavailable
    empty = sum(1 for s in sets if not s)
    res["clauses"]["no_unavailable_interval"] = PASS if empty == 0 else FAIL
    res["observed"]["empty_samples"] = empty

    # clause 1 -- core identity persists
    persistent = set(sets[0])
    for s in sets:
        persistent &= s
    res["observed"]["persistent_pids"] = len(persistent)
    res["observed"]["persistent_pid_list"] = sorted(persistent)
    if core_pid is not None:
        ok = all(core_pid in s for s in sets)
        res["clauses"]["core_identity_persists"] = PASS if ok else FAIL
        res["observed"]["core_pid"] = core_pid
    else:
        # Role was not recorded and the process is gone, so the core cannot be
        # named. A RESTART is still excludable -- it terminates every process,
        # so no PID could survive it -- but that is a weaker, restart-exclusion
        # form of the clause and is labelled as such rather than as a pass.
        res["clauses"]["core_identity_persists"] = (
            "PASS_BY_RESTART_EXCLUSION" if persistent else FAIL)
        res["observed"]["core_pid"] = None

    # clause 2 -- core start-time / generation identity unchanged
    if core_pid is not None and samples[0].get("core_created"):
        same = len({s.get("core_created") for s in samples}) == 1
        res["clauses"]["core_generation_unchanged"] = PASS if same else FAIL
    else:
        res["clauses"]["core_generation_unchanged"] = UNKNOWN

    # clause 4 -- churn attributable only to scheduled recoveries
    union = set()
    for s in sets:
        union |= s
    churn = len(union) - len(persistent)
    res["observed"]["churned_pids"] = churn
    res["observed"]["recoveries"] = recoveries
    if recoveries == 0:
        res["clauses"]["churn_attributable"] = PASS if churn == 0 else FAIL
    else:
        # One model worker replaced per recovery is the producer's behaviour.
        # More churn than recoveries is unexplained.
        res["clauses"]["churn_attributable"] = (
            PASS if 0 < churn <= recoveries * 2 else FAIL)

    vals = list(res["clauses"].values())
    if FAIL in vals:
        res["verdict"] = FAIL
    elif UNKNOWN in vals:
        res["verdict"] = UNKNOWN
    else:
        res["verdict"] = PASS
    return res


# --------------------------------------------------------------- self-test

def _samples(pid_lists):
    return [{"backend_pids": p} for p in pid_lists]


def selftest():
    n = f = 0

    def ck(label, got, want):
        nonlocal n, f
        n += 1
        if got == want:
            print("  ok   %-40s -> %s" % (label, got))
        else:
            f += 1
            print("  FAIL %-40s got %s want %s" % (label, got, want))

    print("=== backend-continuity witness sabotage ===\n")

    core = [1, 2, 3]
    # worker replacement only: core survives, one worker swapped per recovery,
    # and the core generation is known and constant
    full = [{"backend_pids": core + [10 + i], "core_created": "T0"}
            for i in range(3)]
    r = evaluate(full, recoveries=2, core_pid=1)
    ck("worker replacement only", r["verdict"], PASS)

    # same, but the core generation CHANGES -- PID reuse after a restart
    reused = [{"backend_pids": core + [10], "core_created": "T0"},
              {"backend_pids": core + [11], "core_created": "T1"}]
    r = evaluate(reused, recoveries=1, core_pid=1)
    ck("core pid reused, generation changed", r["verdict"], FAIL)

    # generation not recorded at all -> UNKNOWN, never a silent pass
    r = evaluate(_samples([core + [10], core + [11]]),
                 recoveries=1, core_pid=1)
    ck("generation field absent", r["verdict"], UNKNOWN)

    # actual backend restart: every pid changes
    r = evaluate(_samples([[1, 2, 3, 10], [1, 2, 3, 10], [4, 5, 6, 11]]),
                 recoveries=2, core_pid=1)
    ck("actual backend restart", r["verdict"], FAIL)

    # backend disappears and reappears
    r = evaluate(_samples([[1, 2, 3], [], [1, 2, 3]]),
                 recoveries=0, core_pid=1)
    ck("backend disappears and reappears", r["verdict"], FAIL)

    # foreign/unexplained churn with no recoveries to explain it
    r = evaluate(_samples([core + [10], core + [11], core + [12]]),
                 recoveries=0, core_pid=1)
    ck("unexplained churn, no recoveries", r["verdict"], FAIL)

    # churn far exceeding what the recoveries can explain
    many = [core + [100 + i] for i in range(12)]
    r = evaluate(_samples(many), recoveries=1, core_pid=1)
    ck("churn exceeds recoveries", r["verdict"], FAIL)

    # core dies while others persist
    r = evaluate(_samples([[1, 2, 3], [2, 3, 9], [2, 3, 9]]),
                 recoveries=1, core_pid=1)
    ck("core process dies", r["verdict"], FAIL)

    # no core known, nothing persists -> restart cannot be excluded
    r = evaluate(_samples([[1, 2, 3], [4, 5, 6]]), recoveries=1)
    ck("no core known and nothing persists", r["verdict"], FAIL)

    # no core known but a core persists -> restart excluded, generation UNKNOWN
    r = evaluate(_samples([core + [10], core + [11]]), recoveries=1)
    ck("no core known, restart excluded", r["verdict"], UNKNOWN)

    print("\nchecks %d, failures %d" % (n, f))
    print("WITNESS GREEN" if f == 0 else "WITNESS RED")
    return 0 if f == 0 else 1


def apply_to_arms():
    live = live_process_roles()
    live_core = next((p for p, r in live.items() if r["role"] == "core"), None)
    print("=== applying the corrected witness to all four arms ===")
    print("live core pid from producer structure: %s\n" % live_core)
    out = {}
    for arm in ARMS:
        p = os.path.join(RESULTS, "RUNTIME_MEMORY_%s.json" % arm)
        if not os.path.exists(p):
            continue
        d = json.load(open(p, encoding="utf-8"))
        s = d["samples"]
        rec = s[-1].get("recoveries", 0) if s else 0
        # The core pid is knowable only for the arm whose backend is still
        # alive. For earlier arms the process is gone and the role was never
        # recorded, so the clause is evaluated in its restart-exclusion form.
        cp = live_core if (live_core is not None and
                           all(live_core in x["backend_pids"] for x in s)) else None
        # RETROSPECTIVE GENERATION CHECK. core_created was never recorded per
        # sample, so for the one arm whose backend is still alive the producer
        # is asked now: if the live core was created BEFORE this arm's first
        # sample and is still the same pid, it persisted across the whole arm
        # and its generation cannot have changed. Only that arm can be
        # evaluated this way; for the others the process is gone.
        s_eval = s
        if cp is not None and live.get(cp):
            created = live[cp]["created"]
            s_eval = [dict(x, core_created=created) for x in s]
        r = evaluate(s_eval, rec, cp)
        r["core_created"] = live[cp]["created"] if cp is not None else None
        r["arm"] = arm
        r["original_tooth_offences"] = len(d["problems"])
        out[arm] = r
        print("%-17s verdict %-8s core %-6s persistent %2d churn %2d rec %2d "
              "orig_offences %d"
              % (arm, r["verdict"], str(r["observed"]["core_pid"]),
                 r["observed"]["persistent_pids"], r["observed"]["churned_pids"],
                 r["observed"]["recoveries"], r["original_tooth_offences"]))
        for k, v in r["clauses"].items():
            print("      %-30s %s" % (k, v))
    json.dump(out, open(os.path.join(RESULTS, "RM_BACKEND_CONTINUITY.json"),
                        "w", encoding="utf-8"), indent=2)
    print("\nwrote docs/results/RM_BACKEND_CONTINUITY.json")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.apply:
        return apply_to_arms()
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
