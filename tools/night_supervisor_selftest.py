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

    print("\n[the sub-agent's permissions are a boundary, not a setting]")
    cmd = NS.agent_cmd("PROMPT BODY")
    flags = [x for x in cmd if x != "PROMPT BODY"]
    ck("agent is NEVER invoked with bypassPermissions",
       "bypassPermissions" not in flags,
       " ".join(flags))
    ck("agent runs under acceptEdits",
       flags[flags.index("--permission-mode") + 1] == "acceptEdits")
    ck("supervisor never grants runtime clearance in the invocation",
       not any("i-have-clearance" in x or "--attended" in x for x in flags))
    ck("agent is constrained by an explicit allowlist",
       "--allowedTools" in src and "AGENT_ALLOWED_TOOLS" in src)
    ck("the test runner is allowed EXACTLY, with no argument wildcard",
       "Bash(python tools/run_safe_tests.py)" in NS.AGENT_ALLOWED_TOOLS
       and not any(t.startswith("Bash(python tools/run_safe_tests.py:")
                   for t in NS.AGENT_ALLOWED_TOOLS))
    ck("no allowlist entry can reach the runtime",
       not any(w in t for t in NS.AGENT_ALLOWED_TOOLS
               for w in ("lms", "curl", "godot", "PowerShell")))
    for denied in ("Bash(lms:*)", "PowerShell", "Agent"):
        ck("%s is denied outright" % denied, denied in NS.AGENT_DENIED_TOOLS)
    ck("the denylist is actually passed to the agent",
       "--disallowedTools" in src)

    # ---------------------------------------------------------------------
    # INVOCATION OUTCOME
    #
    # Replays the real 2026-09-08 iteration-4 event and the four neighbours it
    # was confused with. The bug was not a wrong decision -- BLOCKED was right
    # -- it was a wrong STORY: a missing receipt reported as a mis-bound one.
    # ---------------------------------------------------------------------
    print("\n[invocation outcome: no receipt != a bad receipt]")

    QUOTA = "You've hit your session limit \u00b7 resets 12:30pm (America/Chicago)"

    def inv_case(pre, post_doc, nonce=NONCE, started=True, rc=0, out=""):
        """Classify against a temp status file. post_doc None = no file."""
        d = tempfile.mkdtemp()
        path = os.path.join(d, "status.json")
        old = NS.STATUS
        NS.STATUS = path
        try:
            if pre is not None:
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(pre, f)
            pre_fp = NS.status_fingerprint()
            if post_doc is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(post_doc, f)
            post_fp = NS.status_fingerprint()
            inv = NS.classify_invocation(pre_fp, post_fp, nonce, started, rc,
                                         out)
            st = NS.read_status(3, nonce, OBJH, C0, C1, inv)
            return inv, st
        finally:
            NS.STATUS = old

    # THE ACTUAL EVENT: iteration 4 wrote nothing; iteration 3's receipt stayed.
    prev = good(iteration_id="0289c831b7429824")
    inv, st = inv_case(prev, prev, out=QUOTA)
    ck("stale leftover receipt classifies STALE_STATUS_PRESENT",
       inv["outcome"] == NS.STALE_STATUS_PRESENT, inv["outcome"])
    ck("stale receipt is NOT called a receipt from another turn",
       "not from this turn" not in st["reason"], st["reason"])
    ck("stale receipt still BLOCKS", st["state"] == NS.BLOCKED)
    ck("status_file_changed is False when nothing was written",
       inv["status_file_changed"] is False)
    ck("the provider's own quota text is attached as external_cause",
       inv["external_cause"] == "PROVIDER_QUOTA", str(inv["external_cause"]))
    ck("external_cause reaches the operator-visible reason",
       "PROVIDER_QUOTA" in st["reason"])

    # No file at all, before or after.
    inv, st = inv_case(None, None)
    ck("no status file at all classifies NO_STATUS_PRODUCED",
       inv["outcome"] == NS.NO_STATUS_PRODUCED, inv["outcome"])
    ck("NO_STATUS_PRODUCED blocks", st["state"] == NS.BLOCKED)

    # The child never started.
    inv, st = inv_case(None, None, started=False, rc=None,
                       out="agent process failed to start: [Errno 2]")
    ck("a child that never started classifies INVOCATION_FAILED",
       inv["outcome"] == NS.INVOCATION_FAILED, inv["outcome"])
    ck("INVOCATION_FAILED records child_started False",
       inv["child_started"] is False)

    # A genuinely new receipt that does not bind: the ONLY case where the
    # original wording was ever correct.
    inv, st = inv_case(prev, good(iteration_id="ffffffffffffffff"))
    ck("a NEW but unbound receipt classifies UNBOUND_STATUS_WRITTEN",
       inv["outcome"] == NS.UNBOUND_STATUS_WRITTEN, inv["outcome"])
    ck("only the unbound case says the receipt is not from this turn",
       "not from this turn" in st["reason"], st["reason"])
    ck("UNBOUND_STATUS_WRITTEN blocks", st["state"] == NS.BLOCKED)

    # A fresh, bound receipt passes classification and faces every original
    # check unchanged.
    inv, st = inv_case(prev, good())
    ck("a fresh bound receipt classifies BOUND_STATUS_VALID",
       inv["outcome"] == NS.BOUND_STATUS_VALID, inv["outcome"])
    ck("a bound receipt still reaches CONTINUE", st["state"] == "CONTINUE")
    ck("a bound receipt is NOT annotated with a quota cause",
       inv["external_cause"] is None)

    # A bound receipt whose transcript happens to contain quota text must not
    # be annotated -- advisory evidence never decorates a green turn.
    inv, st = inv_case(prev, good(), out=QUOTA)
    ck("quota text in a green turn's transcript is ignored",
       inv["external_cause"] is None and st["state"] == "CONTINUE")

    # DIRECTION OF TRAVEL: nothing that previously stopped now continues.
    for outcome_doc, label in ((None, "no receipt"),
                               (prev, "stale receipt")):
        _, st2 = inv_case(prev, outcome_doc)
        ck("%s can never yield CONTINUE" % label, st2["state"] == NS.BLOCKED)

    # Fingerprint identity is CONTENT, not timestamp.
    d = tempfile.mkdtemp()
    path = os.path.join(d, "status.json")
    old = NS.STATUS
    NS.STATUS = path
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(prev, f)
        fp1 = NS.status_fingerprint()
        os.utime(path, (0, 0))          # move the clock, not the bytes
        fp2 = NS.status_fingerprint()
        ck("fingerprint ignores mtime: same bytes, same identity", fp1 == fp2)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(good(reason="different"), f)
        ck("fingerprint changes when the bytes change",
           NS.status_fingerprint() != fp1)
    finally:
        NS.STATUS = old

    # SABOTAGE: collapse STALE back into UNBOUND -- the pre-fix behaviour --
    # and prove the tooth goes RED. A tooth that cannot detect its own
    # regression is decoration.
    print("\n[sabotage: reintroduce the conflation]")
    real = NS.classify_invocation

    def conflating(pre_fp, post_fp, nonce, started, exit_code, out):
        inv = real(pre_fp, post_fp, nonce, started, exit_code, out)
        if inv["outcome"] == NS.STALE_STATUS_PRESENT:
            inv["outcome"] = NS.UNBOUND_STATUS_WRITTEN
            inv["reason"] = ("iteration_id does not match the nonce issued for "
                             "this invocation; the receipt is not from this turn")
        return inv

    NS.classify_invocation = conflating
    applied = NS.classify_invocation is not real
    ck("SABOTAGE APPLIED (classifier replaced before the assertion)", applied)
    if applied:
        _, st_sab = inv_case(prev, prev, out=QUOTA)
        ck("sabotage BITES: the misleading wording returns",
           "not from this turn" in st_sab["reason"])
        ck("sabotage did not flip the decision (it was never wrong)",
           st_sab["state"] == NS.BLOCKED)
    NS.classify_invocation = real
    ck("SABOTAGE REVERTED", NS.classify_invocation is real)
    _, st_rev = inv_case(prev, prev, out=QUOTA)
    ck("after revert the honest wording is back",
       "not from this turn" not in st_rev["reason"])

    print("\n[SUMMARY]")
    print("  checks %d, failures %d" % (_n, _f))
    if _f:
        print("\nSUPERVISOR TEETH RED")
        return 1
    print("\nSUPERVISOR TEETH GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
