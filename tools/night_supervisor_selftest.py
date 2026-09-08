"""Night supervisor decision teeth. NO AGENT INVOCATION, NO LM STUDIO CONTACT.

    python tools/night_supervisor_selftest.py

The supervisor's entire value is that it stops for machine-readable reasons and
refuses to guess. The dangerous direction is therefore a receipt it treats as
CONTINUE when it should not, so every one of those paths is exercised here:

  * a receipt that is missing, unparseable, or carries an unrecognised state
  * a receipt that is NOT FROM THIS INVOCATION (wrong or absent nonce)
  * a receipt that describes a DIFFERENT REPOSITORY STATE (wrong objective
    hash, wrong starting or ending commit)
  * a CONTINUE that does not name the objective item it advanced

Nothing here invokes the agent, touches the runtime, or writes to the real
docs/night/status.json.
"""

import importlib.util
import json
import os
import re
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "night_supervisor", os.path.join(REPO, "tools", "night_supervisor.py"))
NS = importlib.util.module_from_spec(spec)
spec.loader.exec_module(NS)

NONCE = "abc123def4567890"
OBJH = "0f0f0f0f0f0f0f0f"
C0 = "aaaaaaa"
C1 = "bbbbbbb"

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


def good(**over):
    d = {"iteration": 3, "iteration_id": NONCE, "objective_hash": OBJH,
         "starting_commit": C0, "ending_commit": C1, "state": "CONTINUE",
         "reason": "did a thing", "advanced_item": "queue item 1"}
    d.update(over)
    return d


def with_status(doc, iteration=3, nonce=NONCE, objh=OBJH, c0=C0, c1=C1):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "status.json")
    if doc is not None:
        with open(p, "w", encoding="utf-8") as f:
            if isinstance(doc, str):
                f.write(doc)
            else:
                json.dump(doc, f)
    old_path = NS.STATUS
    NS.STATUS = p
    try:
        return NS.read_status(iteration, nonce, objh, c0, c1)
    finally:
        NS.STATUS = old_path


def main():
    print("=== night supervisor decision teeth ===")

    print("\n[the dangerous direction: never invent CONTINUE]")
    r = with_status(None)
    ck("MISSING status -> BLOCKED", r["state"] == NS.BLOCKED, r.get("reason"))
    ck("...and says why", "no status.json" in r["reason"])
    r = with_status("{ this is not json")
    ck("UNPARSEABLE status -> BLOCKED", r["state"] == NS.BLOCKED)
    r = with_status(good(state="probably fine"))
    ck("UNRECOGNISED state -> BLOCKED", r["state"] == NS.BLOCKED)
    ck("...refuses to interpret it generously",
       "refusing to interpret" in r["reason"])
    r = with_status(good(state=""))
    ck("EMPTY state -> BLOCKED", r["state"] == NS.BLOCKED)

    print("\n[a receipt must come from THIS invocation]")
    r = with_status(good(iteration_id="0000000000000000"))
    ck("WRONG nonce -> BLOCKED", r["state"] == NS.BLOCKED, r.get("reason"))
    ck("...names it as not from this turn", "not from this turn" in r["reason"])
    d = good()
    d.pop("iteration_id")
    ck("MISSING nonce -> BLOCKED", with_status(d)["state"] == NS.BLOCKED)
    ck("WRONG iteration -> BLOCKED",
       with_status(good(iteration=1))["state"] == NS.BLOCKED)

    print("\n[a receipt must describe THIS repository state]")
    r = with_status(good(objective_hash="deadbeefdeadbeef"))
    ck("WRONG objective_hash -> BLOCKED", r["state"] == NS.BLOCKED)
    ck("...names the objective mismatch", "different objective" in r["reason"])
    ck("WRONG starting_commit -> BLOCKED",
       with_status(good(starting_commit="zzzzzzz"))["state"] == NS.BLOCKED)
    r = with_status(good(ending_commit="zzzzzzz"))
    ck("WRONG ending_commit -> BLOCKED", r["state"] == NS.BLOCKED)
    ck("...compares against the HEAD the supervisor observed",
       "observed after invocation" in r["reason"])

    print("\n[PROGRESS is claimed, not scored]")
    r = with_status(good(advanced_item=""))
    ck("CONTINUE without naming an advanced item -> BLOCKED",
       r["state"] == NS.BLOCKED, r.get("reason"))
    ck("...whitespace does not count",
       with_status(good(advanced_item="   "))["state"] == NS.BLOCKED)
    r = with_status(good(advanced_item="queue item 2"))
    ck("CONTINUE naming an item is accepted", r["state"] == NS.CONTINUE)
    ck("the claim is carried through for audit",
       r.get("advanced_item") == "queue item 2")

    print("\n[terminal states are honoured exactly]")
    for st in (NS.DONE, NS.BLOCKED, NS.CLEARANCE):
        ck("%s passes through" % st, with_status(good(state=st))["state"] == st)
    ck("lowercase 'done' is normalised",
       with_status(good(state="done"))["state"] == NS.DONE)
    ck("DONE does not require an advanced item",
       with_status(good(state="DONE", advanced_item=""))["state"] == NS.DONE)

    print("\n[CONTINUE is the only non-terminal outcome]")
    ck("CONTINUE is not in TERMINAL", NS.CONTINUE not in NS.TERMINAL)
    ck("every stop reason IS in TERMINAL",
       {NS.DONE, NS.BLOCKED, NS.CLEARANCE, NS.INTEGRITY} == NS.TERMINAL)

    print("\n[structural properties of the supervisor itself]")
    src = open(os.path.join(REPO, "tools", "night_supervisor.py"),
               encoding="utf-8").read()
    ck("tests_ok() invokes the classified runner", "run_safe_tests.py" in src)
    ck("supervisor never grants runtime clearance",
       "i-have-clearance" not in src and "--attended" not in src)
    ck("tree checked BEFORE and AFTER an iteration", src.count("dirty()") >= 3)
    ck("tests checked BEFORE and AFTER an iteration",
       src.count("tests_ok()") >= 2)
    ck("spinning stop exists", "SPINNING" in src)
    ck("a fresh nonce is issued per iteration", "secrets.token_hex" in src)
    ck("supervisor owns the audit trail",
       "objective_snapshot.json" in src
       and "supervisor_events.jsonl" in src
       and "iteration_%03d_prompt.txt" in src)
    # Precise: an ASSIGNMENT to a budget, not the loop bound
    # `range(1, a.max_iterations + 1)`, which an earlier version of this check
    # matched -- the third self-inflicted false positive of the shift, after
    # the docstring scan and the taskkill marker.
    raises = re.search(r"(max_iterations|max_minutes|max_idle_iterations)"
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
