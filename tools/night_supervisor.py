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
import secrets
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NIGHT = os.path.join(REPO, "docs", "night")
STATUS = os.path.join(NIGHT, "status.json")
LOG = os.path.join(NIGHT, "supervisor.log")
RUNS = os.path.join(NIGHT, "runs")

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


def read_status(iteration, nonce, obj_hash, start_commit, end_commit):
    """Fail closed, and bind the receipt to THIS invocation and THIS repo state.

    A fresh timestamp is not identity. Without a nonce an older process could
    write the file late and still look current, so the agent must echo the
    nonce the supervisor generated for this iteration. The receipt must also
    describe the repository the supervisor actually observed -- a CONTINUE that
    refers to some other commit or objective is refused rather than believed.
    """
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


def run_agent(prompt, timeout_s, model=None):
    cmd = ["claude", "-p", prompt, "--permission-mode", "acceptEdits",
           "--add-dir", REPO]
    if model:
        cmd += ["--model", model]
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout_s)
    return r.returncode, (r.stdout or "")[-4000:]


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
        try:
            rc, out = run_agent(prompt, a.agent_timeout, a.model)
        except subprocess.TimeoutExpired:
            log("STOP BLOCKED: agent exceeded %d s" % a.agent_timeout)
            event("stop", reason="agent_timeout", iteration=i)
            return 1
        artifact("iteration_%03d_output.txt" % i, out)
        log("agent exit %d" % rc)

        end_commit = head()
        st = read_status(i, nonce, obj_hash, start_commit, end_commit)
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
