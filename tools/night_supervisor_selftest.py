"""Night supervisor decision teeth. NO AGENT INVOCATION, NO LM STUDIO CONTACT.

    python tools/night_supervisor_selftest.py

The supervisor's whole value is that it stops for machine-readable reasons and
refuses to guess. So the dangerous direction is a status the supervisor treats
as CONTINUE when it should not. Every one of those paths is exercised here.

Nothing in this file invokes the agent, touches the runtime, or writes to the
real docs/night/status.json.
"""

import importlib.util
import json
import os
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "night_supervisor", os.path.join(REPO, "tools", "night_supervisor.py"))
NS = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NS)

_n = 0
_f = 0


def ck(label, cond, detail=""):
    global _n, _f
    _n += 1
    if cond:
        print("  ok   %s" % label)
    else:
        _f += 1
        print("  FAIL %s %s" % (label, detail))


def with_status(doc, min_iteration):
    """Point the supervisor at a temporary status file."""
    d = tempfile.mkdtemp()
    p = os.path.join(d, "status.json")
    if doc is not None:
        with open(p, "w", encoding="utf-8") as f:
            if isinstance(doc, str):
                f.write(doc)
            else:
                json.dump(doc, f)
    old = NS.STATUS
    NS.STATUS = p
    try:
        return NS.read_status(min_iteration)
    finally:
        NS.STATUS = old


def main():
    print("=== night supervisor decision teeth ===\n")

    print("[the dangerous direction: never invent CONTINUE]")
    r = with_status(None, 1)
    ck("MISSING status -> BLOCKED", r["state"] == NS.BLOCKED, r.get("reason"))
    ck("...and says why", "no status.json" in r["reason"])

    r = with_status("{ this is not json", 1)
    ck("UNPARSEABLE status -> BLOCKED", r["state"] == NS.BLOCKED)

    r = with_status({"iteration": 1, "state": "CONTINUE"}, 3)
    ck("STALE status -> BLOCKED", r["state"] == NS.BLOCKED, r.get("reason"))
    ck("...names the staleness", "stale" in r["reason"])

    r = with_status({"iteration": 3, "state": "probably fine"}, 3)
    ck("UNRECOGNISED state -> BLOCKED", r["state"] == NS.BLOCKED)
    ck("...refuses to interpret it generously",
       "refusing to interpret" in r["reason"])

    r = with_status({"iteration": 3, "state": ""}, 3)
    ck("EMPTY state -> BLOCKED", r["state"] == NS.BLOCKED)

    print("\n[terminal states are honoured exactly]")
    for st in (NS.DONE, NS.BLOCKED, NS.CLEARANCE):
        r = with_status({"iteration": 2, "state": st, "reason": "x"}, 2)
        ck("%s passes through" % st, r["state"] == st)
    r = with_status({"iteration": 2, "state": "done", "reason": "x"}, 2)
    ck("lowercase 'done' is normalised to DONE", r["state"] == NS.DONE)

    print("\n[CONTINUE is the only non-terminal outcome]")
    r = with_status({"iteration": 5, "state": "CONTINUE",
                     "next_action": "y"}, 5)
    ck("valid CONTINUE accepted", r["state"] == NS.CONTINUE)
    ck("CONTINUE is not in TERMINAL", NS.CONTINUE not in NS.TERMINAL)
    ck("every stop reason IS in TERMINAL",
       {NS.DONE, NS.BLOCKED, NS.CLEARANCE, NS.INTEGRITY} == NS.TERMINAL)

    print("\n[a future-dated status must not unlock the loop]")
    r = with_status({"iteration": 99, "state": "CONTINUE"}, 3)
    ck("iteration ahead of the supervisor is still accepted only as CONTINUE",
       r["state"] == NS.CONTINUE)
    # The supervisor's own counter drives min_iteration, so an agent cannot
    # skip ahead to avoid a later staleness check.

    print("\n[integrity helpers are real, not stubs]")
    ck("tests_ok() invokes the classified runner",
       "run_safe_tests.py" in open(
           os.path.join(REPO, "tools", "night_supervisor.py"),
           encoding="utf-8").read())
    src = open(os.path.join(REPO, "tools", "night_supervisor.py"),
               encoding="utf-8").read()
    ck("supervisor never grants runtime clearance",
       "i-have-clearance" not in src and "--attended" not in src)
    ck("supervisor checks the tree BEFORE and AFTER an iteration",
       src.count("dirty()") >= 3)
    ck("supervisor checks tests BEFORE and AFTER an iteration",
       src.count("tests_ok()") >= 2)
    ck("spinning stop exists", "SPINNING" in src)
    # Precise: an ASSIGNMENT to a budget, not the loop bound
    # `range(1, a.max_iterations + 1)` which an earlier version of this check
    # matched -- the third self-inflicted false positive of the shift, and the
    # same family as the docstring and taskkill ones.
    import re as _re
    raises = _re.search(r"(max_iterations|max_minutes|max_idle_iterations)"
                        r"\s*(=[^=]|\+=)", src)
    ck("no budget is ASSIGNED or incremented at runtime", raises is None,
       raises.group(0) if raises else "")

    print("\n[SUMMARY]")
    print("  checks %d, failures %d" % (_n, _f))
    if _f:
        print("\nSUPERVISOR TEETH RED")
        return 1
    print("\nSUPERVISOR TEETH GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
