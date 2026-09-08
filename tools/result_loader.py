"""Fail-closed result loader. Refuses ineligible evidence mechanically.

    python tools/result_loader.py --selftest
    python tools/result_loader.py --check RUNTIME_MEMORY_IDLE.json ...

Cross-arm comparison is REFUSED unless every requested artifact is
`integrity_qualified == true`. Rejection is the default; admission must be
earned by the artifact carrying its own proof.

REJECTED, always:
    integrity_status  UNKNOWN        -- never silently upgraded to PASS
    integrity_status  VOID
    status            QUARANTINED
    run_kind          QUALIFICATION  -- qualification is not evidence
    evidence_eligible false
    causal_evidence_eligible false   -- when causal analysis is requested
    missing eligibility fields       -- an artifact that cannot prove its own
                                        status is not admitted on the benefit
                                        of the doubt

This exists because eligibility that lives only in prose gets overridden by
whoever is reading at 2 a.m. with a deadline. Here it is a return code.
"""

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS = os.path.join(REPO, "docs", "results")


class Rejected(Exception):
    pass


def assess(doc, name="<artifact>", causal=False):
    """Return a list of rejection reasons. Empty means admissible."""
    bad = []

    # An artifact that cannot describe its own eligibility is not admitted.
    if "integrity_qualified" not in doc and "causal_evidence_eligible" not in doc:
        bad.append("no eligibility fields; artifact cannot prove its status")
        return bad

    status = str(doc.get("integrity_status", "")).upper()
    if status in ("UNKNOWN", ""):
        bad.append("integrity_status=%s (UNKNOWN is never upgraded to PASS)"
                   % (status or "absent"))
    elif status == "VOID":
        bad.append("integrity_status=VOID")
    elif status == "QUARANTINED":
        bad.append("integrity_status=QUARANTINED")

    if str(doc.get("status", "")).upper() == "QUARANTINED":
        bad.append("status=QUARANTINED")

    if doc.get("integrity_qualified") is not True and status not in ("VOID",
                                                                     "QUARANTINED"):
        bad.append("integrity_qualified is not true")

    if str(doc.get("run_kind", "")).upper() == "QUALIFICATION":
        bad.append("run_kind=QUALIFICATION (qualification is not evidence)")

    if doc.get("evidence_eligible") is False:
        bad.append("evidence_eligible=false")

    if causal and doc.get("causal_evidence_eligible") is not True:
        bad.append("causal analysis requested but causal_evidence_eligible "
                   "is not true")

    return bad


def load_for_comparison(paths, causal=False):
    """Load artifacts for cross-arm comparison, or raise Rejected."""
    docs, problems = {}, {}
    for p in paths:
        full = p if os.path.isabs(p) else os.path.join(RESULTS, p)
        name = os.path.basename(full)
        if not os.path.exists(full):
            problems[name] = ["artifact does not exist"]
            continue
        d = json.load(open(full, encoding="utf-8"))
        bad = assess(d, name, causal)
        if bad:
            problems[name] = bad
        else:
            docs[name] = d
    if problems:
        raise Rejected(problems)
    return docs


# --------------------------------------------------------------- self-test

def selftest():
    n = f = 0

    def ck(label, cond, detail=""):
        nonlocal n, f
        n += 1
        if cond:
            print("  ok   %s" % label)
        else:
            f += 1
            print("  FAIL %s %s" % (label, detail))

    good = {"integrity_status": "QUALIFIED", "integrity_qualified": True,
            "causal_evidence_eligible": True, "run_kind": "EXPERIMENT"}

    print("=== result loader rejection branches ===\n")
    ck("admits a fully qualified artifact", assess(dict(good)) == [],
       str(assess(dict(good))))
    ck("admits it for causal analysis too",
       assess(dict(good), causal=True) == [])

    d = dict(good); d["integrity_status"] = "UNKNOWN"; d["integrity_qualified"] = False
    r = assess(d)
    ck("REJECTS UNKNOWN", any("UNKNOWN" in x for x in r), str(r))

    d = dict(good); d["integrity_status"] = "VOID"; d["integrity_qualified"] = False
    ck("REJECTS VOID", any("VOID" in x for x in assess(d)))

    d = dict(good); d["integrity_status"] = "QUARANTINED"; d["integrity_qualified"] = False
    ck("REJECTS QUARANTINED via integrity_status",
       any("QUARANTINED" in x for x in assess(d)))

    d = dict(good); d["status"] = "QUARANTINED"
    ck("REJECTS QUARANTINED via status field",
       any("status=QUARANTINED" in x for x in assess(d)))

    d = dict(good); d["run_kind"] = "QUALIFICATION"
    ck("REJECTS qualification data",
       any("QUALIFICATION" in x for x in assess(d)))

    d = dict(good); d["evidence_eligible"] = False
    ck("REJECTS evidence_eligible=false",
       any("evidence_eligible=false" in x for x in assess(d)))

    d = dict(good); d["causal_evidence_eligible"] = False
    ck("REJECTS causal request when causal_evidence_eligible=false",
       any("causal" in x for x in assess(d, causal=True)))
    ck("...but permits the same artifact for NON-causal inspection",
       assess(d, causal=False) == [], str(assess(d, causal=False)))

    ck("REJECTS an artifact with no eligibility fields at all",
       assess({"arm": "IDLE"}) == ["no eligibility fields; artifact cannot "
                                   "prove its status"])

    d = dict(good); d.pop("integrity_qualified")
    ck("REJECTS integrity_qualified absent",
       any("integrity_qualified is not true" in x for x in assess(d)))

    # end-to-end refusal, mixed batch
    try:
        load_for_comparison(["__does_not_exist__.json"])
        ck("raises Rejected on a missing artifact", False)
    except Rejected as e:
        ck("raises Rejected on a missing artifact",
           "does not exist" in str(e.args[0]))

    # the real completed arms must currently be refused
    real = ["RUNTIME_MEMORY_IDLE.json", "RUNTIME_MEMORY_CONTROL_WORKLOAD.json",
            "RUNTIME_MEMORY_RECOVERY_ONLY.json", "RUNTIME_MEMORY_FULL_WINDOW.json"]
    present = [r for r in real if os.path.exists(os.path.join(RESULTS, r))]
    if present:
        try:
            load_for_comparison(present)
            ck("REFUSES the completed RUNTIME-MEMORY arms (no eligibility yet)",
               False, "loader admitted them")
        except Rejected as e:
            ck("REFUSES the completed RUNTIME-MEMORY arms (no eligibility yet)",
               len(e.args[0]) == len(present),
               "%d of %d refused" % (len(e.args[0]), len(present)))

    # the quarantined qwen block must be refused for causal use
    qb = os.path.join(RESULTS, "RC_RUN1_QWEN_BLOCK.json")
    if os.path.exists(qb):
        d = json.load(open(qb, encoding="utf-8"))
        r = assess(d, causal=True)
        ck("REFUSES the quarantined qwen block for causal analysis", bool(r),
           str(r))

    print("\nchecks %d, failures %d" % (n, f))
    print("LOADER GREEN" if f == 0 else "LOADER RED")
    return 0 if f == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--check", nargs="*", default=[])
    ap.add_argument("--causal", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.check:
        try:
            docs = load_for_comparison(a.check, a.causal)
            print("ADMITTED %d artifact(s)" % len(docs))
            return 0
        except Rejected as e:
            print("REFUSED -- cross-arm comparison not permitted")
            for name, reasons in e.args[0].items():
                print("  %s" % name)
                for r in reasons:
                    print("      %s" % r)
            return 1
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
