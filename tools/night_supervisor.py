"""GONZO NIGHT SUPERVISOR — the loop that lives outside the model.

    python tools/night_supervisor.py --dry-run          # plan only, no agent
    python tools/night_supervisor.py --objective docs/night/objective.json
    python tools/night_supervisor.py --status            # read current state

WHY THIS EXISTS. A coding agent is turn-bounded. It can behave like an
autonomous worker *inside* a turn, but when the turn ends, control returns to
the human — and "keep going until the queue is empty" is an instruction, not a
mechanism. Background monitors do not fix this: a monitor is a diligent security
camera with no legs. It observes; it cannot decide or re-invoke.

That is ROBRUSTION Law 6 aimed at the agent loop itself:

    a boundary -- or an obligation -- that exists only as prose is weaker than
    one enforced by the execution path

So continuation lives here, in a process the model does not control, and
stopping requires a MACHINE-READABLE reason.

STOP CONDITIONS, all fail-closed:

    DONE                       queue exhausted, agent declared completion
    BLOCKED                    agent cannot proceed and said why
    HUMAN_CLEARANCE_REQUIRED   next action needs a human decision
    INTEGRITY_FAILURE          repo or tests are not in a verified state
    (missing/stale/invalid status)  treated as BLOCKED, never as CONTINUE

Anything else means CONTINUE.

ANTI-RUNAWAY. The supervisor stops on: an iteration cap, a wall-clock budget,
consecutive iterations producing no new commit (spinning), a dirty tree it did
not expect, and any failure of the no-contact test suite. It never raises a
budget to keep going.

CONTACT BOUNDARY. The supervisor runs the agent with the same do-not-contact
rule the night shift operated under, and verifies it by running
`tools/run_safe_tests.py` — whose classification is itself fail-closed — before
and after every iteration. It cannot grant runtime clearance; only a human can.
"""

import argparse
import hashlib
import json
import os
import re
import secrets
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NIGHT = os.path.join(REPO, "docs", "night")
STATUS = os.path.join(NIGHT, "status.json")
LOG = os.path.join(NIGHT, "supervisor.log")
RUNS = os.path.join(NIGHT, "runs")

## The run directory, status.json and supervisor.log are OPERATIONAL OUTPUT of
## a run, not repository content, and are gitignored. Without that the
## supervisor creates its own audit trail and then its own pre-flight dirty
## check refuses to start -- which is exactly what happened on the first
## qualification attempt. Archiving a run into git is a deliberate act, not a
## side effect of running one.
##
## THE SUPERVISOR OWNS THE AUDIT TRAIL. Every prompt, every raw agent output,
## every status receipt and every decision is written here by the supervisor
## itself. Depending on the agent to document the agent would be Law 6 wearing
## novelty glasses.
RUN_DIR = None

DONE = "DONE"
BLOCKED = "BLOCKED"
CLEARANCE = "HUMAN_CLEARANCE_REQUIRED"
INTEGRITY = "INTEGRITY_FAILURE"
CONTINUE = "CONTINUE"
TERMINAL = {DONE, BLOCKED, CLEARANCE, INTEGRITY}


def log(msg):
    line = "%s  %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    os.makedirs(NIGHT, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def event(kind, **fields):
    """Append one supervisor decision to the run's event log."""
    if RUN_DIR is None:
        return
    rec = {"at": time.strftime("%Y-%m-%dT%H:%M:%S"), "event": kind}
    rec.update(fields)
    with open(os.path.join(RUN_DIR, "supervisor_events.jsonl"), "a",
              encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def artifact(name, text):
    if RUN_DIR is None:
        return
    with open(os.path.join(RUN_DIR, name), "w", encoding="utf-8",
              errors="replace") as f:
        f.write(text)


def git(*args):
    return subprocess.run(["git", "-C", REPO] + list(args),
                          capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout.strip()


def head():
    return git("rev-parse", "--short", "HEAD")


def dirty():
    return [ln for ln in git("status", "--porcelain").splitlines() if ln.strip()]


def tests_ok():
    """The no-contact suite must pass. Its classification audit is fail-closed,
    so an unclassified test also stops the loop."""
    r = subprocess.run([sys.executable,
                        os.path.join(REPO, "tools", "run_safe_tests.py")],
                       cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=1800)
    tail = [ln for ln in (r.stdout or "").splitlines() if "passed" in ln]
    return r.returncode == 0, (tail[-1] if tail else "no summary line")


def objective_hash(objective):
    return hashlib.sha256(
        json.dumps(objective, sort_keys=True).encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------------------
# INVOCATION OUTCOME
#
# The 2026-09-08 shift stopped on iteration 4 with the reason "the receipt is
# not from this turn". That was mechanically defensible and semantically
# misleading. What actually happened: the model invocation hit a provider
# session limit, wrote no status.json at all, and the PREVIOUS turn's file was
# still sitting on disk. The nonce check compared against that leftover and
# reported it as though a receipt had been PRESENTED and had failed binding.
#
# Those are different events, and the supervisor must not conflate them:
#
#     no fresh receipt was produced     !=     a stale receipt was presented
#
# So the invocation is classified from evidence gathered around it, BEFORE the
# receipt is interpreted:
#
#     child_started        did the process start at all
#     child_exit_code      what it returned
#     stdout/stderr        captured verbatim
#     status_file_changed  fingerprinted before AND after -- identity, not mtime
#     bound_to_nonce       does the receipt echo THIS invocation
#
# None of this weakens any refusal. Every outcome except BOUND_STATUS_VALID
# still stops the loop. The only thing that changes is that the supervisor stops
# telling a true-sounding story about a model that never got to speak.
INVOCATION_FAILED = "INVOCATION_FAILED"
NO_STATUS_PRODUCED = "NO_STATUS_PRODUCED"
STALE_STATUS_PRESENT = "STALE_STATUS_PRESENT"
UNBOUND_STATUS_WRITTEN = "UNBOUND_STATUS_WRITTEN"
BOUND_STATUS_VALID = "BOUND_STATUS_VALID"

# Provider-authored text only. This is ADVISORY EVIDENCE attached to an outcome
# that has ALREADY been decided -- it never selects the outcome, never rescues a
# refusal, and is never treated as ground truth about a remote service. It
# exists so the operator reads "the provider said quota" instead of inferring it
# from a silent turn at 08:39.
PROVIDER_QUOTA_PATTERNS = (
    r"hit your (?:session|usage) limit",
    r"(?:usage|rate) limit (?:reached|exceeded)",
    r"exceeded your current quota",
    r"insufficient (?:quota|credit)",
    r"credit balance is too low",
)


def status_fingerprint():
    """Identity of the status file, or None if absent.

    sha256 of the bytes, deliberately NOT mtime. A file written twice in the
    same second carries the same timestamp, and a turn that rewrites a receipt
    byte-for-byte has produced no new information regardless of when it did so.
    Content is the only honest identity here.
    """
    try:
        with open(STATUS, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()[:16]
    except OSError:
        return None


def detect_external_cause(out):
    """Name a provider-reported cause, or None. Advisory, never decisive."""
    low = (out or "").lower()
    for pat in PROVIDER_QUOTA_PATTERNS:
        if re.search(pat, low):
            return "PROVIDER_QUOTA"
    return None


def classify_invocation(pre_fp, post_fp, nonce, started, exit_code, out):
    """Decide WHAT HAPPENED to the invocation, before reading what it said."""
    inv = {"child_started": bool(started), "child_exit_code": exit_code,
           "status_file_changed": (post_fp is not None and post_fp != pre_fp),
           "bound_to_nonce": False, "external_cause": None}

    if not started:
        inv["outcome"] = INVOCATION_FAILED
        inv["reason"] = ("the agent process never started (%s); no receipt was "
                         "possible" % (out or "no error text"))
    elif post_fp is None:
        inv["outcome"] = NO_STATUS_PRODUCED
        inv["reason"] = ("the agent produced no status.json and none was on "
                         "disk; refusing to assume progress")
    elif not inv["status_file_changed"]:
        inv["outcome"] = STALE_STATUS_PRESENT
        inv["reason"] = ("the agent wrote no status.json this turn; the file on "
                         "disk is byte-identical to the one left by the "
                         "previous iteration (%s). This is a MISSING receipt, "
                         "not a forged one" % pre_fp)
    else:
        try:
            d = json.load(open(STATUS, encoding="utf-8"))
            inv["bound_to_nonce"] = str(d.get("iteration_id", "")) == nonce
        except Exception:                                    # noqa: BLE001
            inv["bound_to_nonce"] = False
        if inv["bound_to_nonce"]:
            inv["outcome"] = BOUND_STATUS_VALID
            inv["reason"] = "a fresh receipt bound to this invocation"
        else:
            inv["outcome"] = UNBOUND_STATUS_WRITTEN
            inv["reason"] = ("a NEW status.json was written this turn but does "
                             "not echo the nonce issued for this invocation; "
                             "the receipt is not from this turn")

    # Attach the provider's own words only where no bound receipt exists. A
    # green turn is never annotated with a quota message that happened to appear
    # somewhere in the transcript.
    if inv["outcome"] != BOUND_STATUS_VALID:
        inv["external_cause"] = detect_external_cause(out)
    return inv


def read_status(iteration, nonce, obj_hash, start_commit, end_commit,
                inv=None):
    """Fail closed, and bind the receipt to THIS invocation and THIS repo state.

    A fresh timestamp is not identity. Without a nonce an older process could
    write the file late and still look current, so the agent must echo the
    nonce the supervisor generated for this iteration. The receipt must also
    describe the repository the supervisor actually observed -- a CONTINUE that
    refers to some other commit or objective is refused rather than believed.
    """
    # The invocation outcome, when the caller has one, decides the WORDING and is
    # strictly more informative than the checks below. It never admits anything
    # those checks would have refused: only BOUND_STATUS_VALID falls through,
    # and it then faces every original check unchanged.
    if inv is not None and inv.get("outcome") != BOUND_STATUS_VALID:
        reason = "%s: %s" % (inv["outcome"], inv["reason"])
        if inv.get("external_cause"):
            reason += (" [external_cause=%s, reported by the provider in the "
                       "agent transcript]" % inv["external_cause"])
        return {"state": BLOCKED, "reason": reason,
                "invocation_outcome": inv["outcome"],
                "external_cause": inv.get("external_cause")}

    if not os.path.exists(STATUS):
        return {"state": BLOCKED,
                "reason": "agent wrote no status.json; refusing to assume "
                          "progress"}
    try:
        d = json.load(open(STATUS, encoding="utf-8"))
    except Exception as e:                                   # noqa: BLE001
        return {"state": BLOCKED, "reason": "status.json unparseable: %s" % e}

    if str(d.get("iteration_id", "")) != nonce:
        return {"state": BLOCKED,
                "reason": "iteration_id %r does not match the nonce issued for "
                          "this invocation; the receipt is not from this turn"
                          % d.get("iteration_id")}
    if int(d.get("iteration", -1)) != iteration:
        return {"state": BLOCKED,
                "reason": "iteration %s != %d" % (d.get("iteration"), iteration)}
    if str(d.get("objective_hash", "")) != obj_hash:
        return {"state": BLOCKED,
                "reason": "objective_hash mismatch; the agent worked against a "
                          "different objective than the supervisor loaded"}
    if str(d.get("starting_commit", "")) != start_commit:
        return {"state": BLOCKED,
                "reason": "starting_commit %r != HEAD observed before "
                          "invocation (%s)"
                          % (d.get("starting_commit"), start_commit)}
    if str(d.get("ending_commit", "")) != end_commit:
        return {"state": BLOCKED,
                "reason": "ending_commit %r != HEAD observed after invocation "
                          "(%s)" % (d.get("ending_commit"), end_commit)}

    st = str(d.get("state", "")).upper()
    if st not in TERMINAL and st != CONTINUE:
        return {"state": BLOCKED,
                "reason": "unrecognised state %r; refusing to interpret it as "
                          "CONTINUE" % st}
    # PROGRESS is audit evidence, never a truth oracle. The agent must NAME the
    # objective item it claims to have advanced; the supervisor records the
    # claim and does not score it.
    if st == CONTINUE and not str(d.get("advanced_item", "")).strip():
        return {"state": BLOCKED,
                "reason": "CONTINUE without naming the objective item advanced"}
    d["state"] = st
    return d


def build_prompt(objective, iteration, last, nonce, obj_hash, start_commit):
    obj = json.dumps(objective, indent=2)
    prev = json.dumps(last, indent=2) if last else "none (first iteration)"
    return """You are iteration %d of a supervised night shift on %s.

A supervisor process outside you will re-invoke you until a machine-readable
stop condition is reached. You do NOT need to finish everything this turn.
Do the next highest-value unblocked item, verify it, commit it, and record state.

DURABLE OBJECTIVE
%s

PREVIOUS ITERATION STATUS
%s

HARD BOUNDARIES THIS SHIFT
- LM Studio is READ-ONLY / DO-NOT-CONTACT. No restart, no unload/load, no
  inference, no experiment runs.
- Run tests ONLY via: python tools/run_safe_tests.py
  Never invoke a suite directly; its classification is what enforces the
  boundary.
- Do not alter frozen preregistration history, quarantined evidence, or any
  threshold (ks=1.8, kh=20, n=3, the 2048 MB floor).
- Never commit a failing tree.

YOUR EXECUTABLE SURFACE IS AN ALLOWLIST, NOT A REQUEST
You may run exactly these, and nothing else:
    git add / commit / status / diff / log / show / rev-parse
    python tools/run_safe_tests.py      (no arguments -- the clearance flag is
                                         not yours to pass)
File edits are permitted. Every other command -- lms, curl, godot, taskkill,
PowerShell, web access, spawning another agent -- is refused by the execution
path, not merely forbidden by this prompt. Do not try to route around it; if a
task genuinely needs one, that is HUMAN_CLEARANCE_REQUIRED.

BEFORE YOU FINISH THIS TURN you MUST write docs/night/status.json:

{
  "iteration": %d,
  "iteration_id": "%s",
  "objective_hash": "%s",
  "starting_commit": "%s",
  "ending_commit": "<git rev-parse --short HEAD AFTER your last commit>",
  "state": "CONTINUE" | "DONE" | "BLOCKED" | "HUMAN_CLEARANCE_REQUIRED",
  "reason": "one sentence, specific",
  "advanced_item": "<the objective queue item you advanced; REQUIRED for CONTINUE>",
  "completed_this_turn": ["..."],
  "queue_remaining": ["..."],
  "next_action": "the single next thing",
  "tests_run": "<the summary line from tools/run_safe_tests.py>"
}

iteration_id, objective_hash and starting_commit MUST be copied EXACTLY as
given above. ending_commit must be the real HEAD after your final commit. A
receipt that does not match what the supervisor observed is refused.

If you cannot write it, the supervisor treats that as BLOCKED and stops.
Use DONE only when the queue is genuinely exhausted.
Use HUMAN_CLEARANCE_REQUIRED when the next action needs runtime contact or a
scientific judgement that is not yours to make.
""" % (iteration, REPO, obj, prev, iteration, nonce, obj_hash,
       start_commit)


# --- the sub-agent's permissions ARE part of the boundary ------------------
#
# Iteration 1 of the first qualification stopped BLOCKED because
# --permission-mode acceptEdits lets the agent write files but refuses every
# Bash call in a non-interactive session: it could author docs/night/README.md
# and could not commit it. The obvious repair is --permission-mode
# bypassPermissions. That repair is refused here.
#
# Law 6 (EXECUTION-BOUNDARY): a boundary that exists only as an instruction is
# weaker than a boundary enforced by the execution path. Under
# bypassPermissions the LM Studio DO-NOT-CONTACT rule is prose again -- an
# unattended agent at 3 a.m. could run `lms unload`, drive godot, or POST to
# the backend, and the only thing standing in the way would be a sentence in a
# prompt. The night shift already produced one boundary violation that way.
#
# So: acceptEdits for file writes, plus an EXPLICIT ALLOWLIST of the only shell
# commands an unattended documentation/analysis turn actually needs. Anything
# not named falls through to a permission prompt, and a prompt in a
# non-interactive session is a refusal. Fail-closed by construction rather than
# by instruction.
AGENT_ALLOWED_TOOLS = [
    "Bash(git add:*)",
    "Bash(git commit:*)",
    "Bash(git status:*)",
    "Bash(git diff:*)",
    "Bash(git log:*)",
    "Bash(git show:*)",
    "Bash(git rev-parse:*)",
    # Exact, deliberately NOT `Bash(python tools/run_safe_tests.py:*)`: the
    # wildcard form would let the agent append --i-have-clearance and run the
    # STATE_MUTATING suites that the classified runner exists to withhold.
    "Bash(python tools/run_safe_tests.py)",
]

# Redundant against the allowlist, which already refuses these by omission.
# Named anyway so that a future edit widening the allowlist -- or a shell form
# that slips past prefix matching -- still cannot reach the runtime.
AGENT_DENIED_TOOLS = [
    "Bash(lms:*)",
    "Bash(curl:*)",
    "Bash(godot:*)",
    "Bash(taskkill:*)",
    "PowerShell",
    "WebFetch",
    "WebSearch",
    # An unattended turn does not fan out; a spawned agent is a permission
    # surface the supervisor cannot see the receipts of.
    "Agent",
]


def agent_cmd(prompt, model=None):
    """The exact argv used to invoke the agent.

    Split out from run_agent so the self-test can assert on the COMMAND rather
    than on the source text. Scanning source for a forbidden token matches the
    shape of the forbidden thing, not the act: this file has to be able to
    NAME the flags it refuses to pass, in the comment above, without tripping
    its own teeth. Three false positives on that exact confusion were already
    paid for during the night shift.
    """
    cmd = ["claude", "-p", prompt, "--permission-mode", "acceptEdits",
           "--allowedTools"] + AGENT_ALLOWED_TOOLS + [
           "--disallowedTools"] + AGENT_DENIED_TOOLS + [
           "--add-dir", REPO]
    if model:
        cmd += ["--model", model]
    return cmd


def run_agent(prompt, timeout_s, model=None):
    """Returns (started, exit_code, output).

    "The child never started" and "the child ran and said nothing useful" are
    different failures with different remedies -- a missing binary versus an
    exhausted quota -- so the caller is TOLD which one it got instead of
    inferring it from an empty transcript. stderr is captured too: the provider
    quota notice on 2026-09-08 was the only evidence of why the turn died.
    """
    cmd = agent_cmd(prompt, model)
    try:
        r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                           encoding="utf-8", errors="replace",
                           timeout=timeout_s)
    except OSError as e:                                     # noqa: BLE001
        return False, None, "agent process failed to start: %s" % e
    out = ((r.stdout or "") + (r.stderr or ""))[-4000:]
    return True, r.returncode, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--objective",
                    default=os.path.join("docs", "night", "objective.json"))
    ap.add_argument("--max-iterations", type=int, default=12)
    ap.add_argument("--max-minutes", type=int, default=240)
    ap.add_argument("--max-idle-iterations", type=int, default=2,
                    help="consecutive iterations with no new commit before "
                         "stopping as SPINNING")
    ap.add_argument("--agent-timeout", type=int, default=1800)
    ap.add_argument("--model", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--status", action="store_true")
    a = ap.parse_args()

    if a.status:
        if os.path.exists(STATUS):
            print(open(STATUS, encoding="utf-8").read())
            return 0
        print("no status.json")
        return 1

    obj_path = a.objective if os.path.isabs(a.objective) \
        else os.path.join(REPO, a.objective)
    if not os.path.exists(obj_path):
        log("FAIL no objective at %s" % obj_path)
        return 1
    objective = json.load(open(obj_path, encoding="utf-8"))

    log("=== night supervisor ===")
    log("objective: %s" % objective.get("title", "<untitled>"))
    log("caps: %d iterations, %d minutes, %d idle"
        % (a.max_iterations, a.max_minutes, a.max_idle_iterations))

    global RUN_DIR
    run_id = time.strftime("%Y%m%d_%H%M%S")
    RUN_DIR = os.path.join(RUNS, run_id)
    os.makedirs(RUN_DIR, exist_ok=True)
    obj_hash = objective_hash(objective)
    artifact("objective_snapshot.json", json.dumps(objective, indent=2))
    log("run_id %s  objective_hash %s" % (run_id, obj_hash))
    event("run_start", run_id=run_id, objective_hash=obj_hash,
          caps={"iterations": a.max_iterations, "minutes": a.max_minutes,
                "idle": a.max_idle_iterations})

    started = time.time()
    last = None
    idle = 0
    prev_head = head()

    for i in range(1, a.max_iterations + 1):
        elapsed = (time.time() - started) / 60.0
        if elapsed > a.max_minutes:
            log("STOP wall-clock budget exhausted (%.0f min)" % elapsed)
            return 0

        # PRE-FLIGHT. A dirty tree or failing suite stops the loop; the
        # supervisor never "fixes" the repo to keep going.
        d = dirty()
        if d:
            log("STOP INTEGRITY_FAILURE: working tree dirty before iteration "
                "%d: %s" % (i, d[:5]))
            return 1
        ok, summary = tests_ok()
        log("pre-flight  head=%s tests: %s" % (head(), summary))
        if not ok:
            log("STOP INTEGRITY_FAILURE: no-contact suite not green")
            return 1

        nonce = secrets.token_hex(8)
        start_commit = head()
        prompt = build_prompt(objective, i, last, nonce, obj_hash, start_commit)
        artifact("iteration_%03d_prompt.txt" % i, prompt)
        event("iteration_start", iteration=i, nonce=nonce,
              starting_commit=start_commit)

        if a.dry_run:
            log("DRY RUN -- prompt written; would invoke the agent, then read "
                "and verify docs/night/status.json")
            event("dry_run_stop", iteration=i)
            return 0

        log("--- iteration %d: invoking agent (nonce %s) ---" % (i, nonce))
        # Fingerprint the receipt BEFORE the invocation. Without this the
        # supervisor cannot tell a file the agent just wrote from one the
        # previous iteration left behind, and reports a missing receipt as a
        # mis-bound one.
        pre_fp = status_fingerprint()
        try:
            started, rc, out = run_agent(prompt, a.agent_timeout, a.model)
        except subprocess.TimeoutExpired:
            log("STOP BLOCKED: agent exceeded %d s" % a.agent_timeout)
            event("stop", reason="agent_timeout", iteration=i)
            return 1
        artifact("iteration_%03d_output.txt" % i, out)
        log("agent started=%s exit=%s" % (started, rc))

        inv = classify_invocation(pre_fp, status_fingerprint(), nonce,
                                  started, rc, out)
        log("invocation: %s -- %s" % (inv["outcome"], inv["reason"]))
        if inv.get("external_cause"):
            log("external cause reported by provider: %s"
                % inv["external_cause"])
        event("invocation", iteration=i, outcome=inv["outcome"],
              child_started=inv["child_started"],
              child_exit_code=inv["child_exit_code"],
              status_file_changed=inv["status_file_changed"],
              bound_to_nonce=inv["bound_to_nonce"],
              external_cause=inv.get("external_cause"))

        end_commit = head()
        st = read_status(i, nonce, obj_hash, start_commit, end_commit, inv)
        if os.path.exists(STATUS):
            artifact("iteration_%03d_status.json" % i,
                     open(STATUS, encoding="utf-8").read())
        state = st["state"]
        log("state=%s  %s" % (state, st.get("reason", "")))
        if st.get("advanced_item"):
            log("claims advanced: %s" % st["advanced_item"])
        event("status", iteration=i, state=state, reason=st.get("reason", ""),
              advanced_item=st.get("advanced_item"),
              starting_commit=start_commit, ending_commit=end_commit)
        if st.get("next_action"):
            log("next_action: %s" % st["next_action"])

        # POST-FLIGHT integrity, regardless of what the agent claimed.
        ok, summary = tests_ok()
        log("post-flight tests: %s" % summary)
        if not ok:
            log("STOP INTEGRITY_FAILURE: suite not green after iteration %d" % i)
            event("stop", reason="tests_red_post", iteration=i)
            return 1
        d = dirty()
        if d:
            log("STOP INTEGRITY_FAILURE: agent left the tree dirty: %s" % d[:5])
            event("stop", reason="dirty_tree_post", iteration=i, dirty=d[:5])
            return 1

        new_head = head()
        if new_head == prev_head:
            idle += 1
            log("no new commit (idle %d/%d)" % (idle, a.max_idle_iterations))
            if idle >= a.max_idle_iterations:
                log("STOP SPINNING: %d consecutive iterations without a commit"
                    % idle)
                event("stop", reason="spinning", iteration=i)
                return 0
        else:
            idle = 0
            log("advanced %s -> %s" % (prev_head, new_head))
            prev_head = new_head

        if state in TERMINAL:
            log("STOP %s" % state)
            event("stop", reason=state, iteration=i)
            return 0
        last = st

    log("STOP iteration cap reached (%d)" % a.max_iterations)
    return 0


if __name__ == "__main__":
    sys.exit(main())
