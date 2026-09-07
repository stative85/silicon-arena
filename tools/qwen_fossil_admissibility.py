"""Evaluate whether the quarantined qwen3.5 block may become a DIAGNOSTIC
sensitivity fossil. Fails closed.

    python tools/qwen_fossil_admissibility.py

This never makes the block causal evidence again. `causal_evidence_eligible` is
permanently false: dead causal evidence is not resurrected. The only status this
can grant is `diagnostic_sensitivity_eligible`, which is weaker and separate.

The criterion was frozen BEFORE any RUNTIME-MEMORY outcome existed. Criterion 9
is checkable rather than assertable: the commit that froze the criterion must
predate the commit that introduced the RUNTIME-MEMORY results.
"""

import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LABEL = os.path.join(REPO, "docs", "results", "RC_RUN1_QWEN_BLOCK.json")
RM_RESULTS = os.path.join(REPO, "docs", "results", "RUNTIME_MEMORY_RESULTS.json")


def first_commit_touching(path):
    rel = os.path.relpath(path, REPO).replace("\\", "/")
    out = subprocess.run(["git", "log", "--reverse", "--format=%H", "--", rel],
                         cwd=REPO, capture_output=True, text=True).stdout.strip()
    return out.splitlines()[0] if out else None


def commit_time(sha):
    if not sha:
        return None
    out = subprocess.run(["git", "show", "-s", "--format=%ct", sha],
                         cwd=REPO, capture_output=True, text=True).stdout.strip()
    return int(out) if out.isdigit() else None


def main():
    label = json.load(open(LABEL, encoding="utf-8"))
    crit = label["admissibility_criterion"]
    print("=== qwen fossil admissibility ===")
    print("causal_evidence_eligible: %s (permanent: %s)"
          % (label["causal_evidence_eligible"],
             label.get("causal_evidence_eligible_permanent")))
    print("evaluating for: %s\n" % crit["target_status"])

    if not os.path.exists(RM_RESULTS):
        print("RUNTIME-MEMORY results do not exist yet.")
        print("FAILS CLOSED -> diagnostic_sensitivity_eligible = false")
        return 1

    rm = json.load(open(RM_RESULTS, encoding="utf-8"))
    checks = []

    checks.append(("1 preregistered independently",
                   bool(rm.get("preregistered_independently"))))
    checks.append(("2 regime reproduces RC workload mechanics",
                   bool(rm.get("reproduces_rc_workload_mechanics"))))
    checks.append(("3 host RAM above the 2048 MB floor throughout",
                   int(rm.get("min_host_free_mb", -1)) > 2048))
    checks.append(("4 no transport/runtime failures",
                   int(rm.get("transport_failures", -1)) == 0))
    checks.append(("5 exact residency count map preserved",
                   bool(rm.get("residency_counts_preserved"))))
    checks.append(("6 no unscheduled recovery",
                   int(rm.get("unscheduled_recoveries", -1)) == 0))
    checks.append(("7 stable over a horizon >= 20 windows",
                   bool(rm.get("stable")) and
                   int(rm.get("stable_horizon_windows", 0)) >= 20))
    checks.append(("8 stable interval begins before the qwen block",
                   bool(rm.get("stable_interval_precedes_qwen_block"))))

    # 9 is structural: the criterion must predate the results in git history.
    c_label = commit_time(first_commit_touching(LABEL))
    c_rm = commit_time(first_commit_touching(RM_RESULTS))
    frozen_first = bool(c_label and c_rm and c_label < c_rm)
    checks.append(("9 criterion frozen before results existed", frozen_first))

    for name, ok in checks:
        print("  %-46s %s" % (name, "PASS" if ok else "FAIL"))

    admissible = all(ok for _, ok in checks)
    print("\ndiagnostic_sensitivity_eligible = %s" % admissible)
    if admissible:
        print("The block may be used as a POST HOC SENSITIVITY FOSSIL only.")
        print("causal_evidence_eligible remains false.")
    else:
        print("Not admissible. The block stays quarantined.")
    return 0 if admissible else 1


if __name__ == "__main__":
    sys.exit(main())
