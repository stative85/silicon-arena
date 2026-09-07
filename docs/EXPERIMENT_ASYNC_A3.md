# ASYNC-A3 — pre-registration

Same question, same world, same contract, same roster, same thresholds as
ASYNC-A2. **A3 exists to repair instrument defects, not to change the
experiment.** ASYNC-A2 is preserved exactly as it happened and is not re-run;
its classification stays NO CONFIRMATORY RESULT.

## What A3 changes, and nothing else

```text
A3 repairs ONLY:

1. live Gate-4 integration
2. cold-start-inclusive equalizer qualification
3. identical runtime re-baseline before every live arm
4. the world clock anchor            <- SEE "SCOPE QUESTION" BELOW

Everything else remains frozen.
No new world. No scarcity change. No new metric. No prompt tweak.
No threshold change. No "maybe 12 resources would be more exciting."
```

Unchanged and explicitly frozen: 16 resources, hold 4, 3 agents, 800
observation ticks, 250 ms tick, contract `{"target_id": "..."}` free string,
`ks = 1.8 / kh = 20 / n = 3`, roster lfm2.5 + qwen3.5 + falcon, the four arms
in the order SERIAL, NATURAL, EQUALIZED, ORDER_REPLAY, and every void condition.

---

## Repair 1 — live Gate 4 integration

**The defect.** `AsyncRuntimeGuard.on_residency_poll()` and `finish()` were
implemented, covered by `async_runtime_selftest.gd`, and never called by
`tools/async_a_run.gd`. The live path witnessed the pool once at R0 and never
again, so `end_resident_set` was empty in every A2 arm and a transient eviction
and restore would have gone unrecorded.

**The repair.**

- `RESIDENCY_POLL_TICKS = 40` (10 s at a 250 ms tick). The poll is started
  **without `await`**: `refresh_residency()` performs an HTTP round trip, and
  awaiting it inside the tick loop would inject that latency into world time.
- `_finish_guard()` runs after settle and before the manifest is built, so the
  end-of-replicate witness actually exists.

**The test.** `tools/gate4_sabotage.py`. It never touches the guard. It starts a
real replicate, genuinely unloads a model with `lms unload` mid-run, loads it
back before the horizon, and asserts **the runner voided**. A component test
could not have caught the original defect, because a component test drives the
component directly. If the poll call is ever deleted from the tick loop, the
guard's own self-test still passes and this one fails.

**Result, 2026-09-07.** PASS.

```
[  8.0s] SABOTAGE: lms unload qwen3.5-2b
[ 22.2s] RESTORE:  lms load qwen3.5-2b
runner exit 1
  VOID: 1 agent lifecycle(s) left open
  VOID: 1 cognition(s) never completed
  VOID: runtime: model qwen3.5-2b entered EVICTED during a measured replicate
observed hashes ['daadde8d4dd9cb37', '0f295e4a8322efb8']
end_resident    ['liquidai/lfm2.5-1.2b-instruct', 'falcon-h1-1.5b-instruct',
                 'qwen3.5-2b']
```

Two things in that output are the actual proof. **Two distinct residency
hashes** means the poll itself observed the pool change -- the void did not come
only from the model-state signal path that already worked in A2. And
**`end_resident` is populated** for the first time, so `finish()` ran.

Note on the run's duration: a replicate whose model vanishes takes well over
300 s to finish, because settle waits up to 120 s for in-flight cognition and
the reload adds more. That is the runner behaving correctly, not a hang; the
test's ceiling is 540 s for that reason.

**A2 is not revalidated by this.** Wiring the guard now and then calling
NATURAL valid would run the check against a replicate whose transient residency
events, if any, were never recorded. A missing check cannot be satisfied
retroactively.

---

## Repair 2 — cold-start-inclusive equalizer qualification

**The defect.** `tools/async_equalizer_check.gd` fired a warmup burst and
discarded it before collecting. The live runner has no warmup; tick 0 is
measured. The gate therefore excluded, by construction, the exact runtime state
that later voided the EQUALIZED arm.

**The repair.** Remove the warmup from the **qualification**, not add a warmup
to the experiment. Cold start is part of the run as currently defined, so the
feasibility gate reproduces it:

```text
fresh process -> real runner, 8 ticks -> record the tick-0 burst -> repeat
```

`tools/async_equalizer_gate_a3.py`, 40 fresh-start trials, 120 first-burst
completions. Each trial launches the **actual runner** rather than a
reimplementation of the submission path, so the payload, bridge, clock and
queueing are the ones the experiment uses.

**The decision rule is unchanged and pre-declared.** Candidates
`[750, 1000, 1250, 1500, 2000]` ms. Accept the **first** candidate with zero
breaches; stop; do not search for a prettier number. If 1000 ms survives,
`EQUALIZED_DELAY_TICKS` stays 4. If nothing passes, EQUALIZED is reported
infeasible at this cold-start cost and the candidate list is **not** extended.

**The 1000 ms constant is not disproven by A2.** The qualification procedure is.

**Result, 2026-09-07.** 40 fresh-start bursts, 120 cold completions, 93 s.

```
tick-0 observation -> completion, cold:
  median 648 ms   p95 702 ms   max 772 ms

  delay_ms   breaches
  750               1   1 cold completion exceeds it
  1000              0   <- PASS, taken

FROZEN EQUALIZER DELAY: 1000 ms = 4 ticks   (UNCHANGED)
```

`EQUALIZED_DELAY_TICKS` stays 4. The first-passing rule stopped at 1000 ms and
no further candidate was examined.

Two things worth recording from the corpus:

- **The clock anchor is confirmed empirically.** Submit offset from the run
  start is now 0-22 ms across all 120 completions, against the 407-418 ms A2
  measured with the clock unanchored. Repair 4 does what it claims.
- **The cold burst splits by model, not by queue position.** Per agent, median
  observation-to-completion is 254 ms / 667 ms / 664 ms. If `max_active = 2`
  queueing dominated, the third submitter would be slowest; instead one agent is
  consistently fast and two are consistently slow, which tracks the models
  rather than the slot order. Recorded, not investigated -- the gate's job is
  feasibility, not attribution.

---

## Repair 3 — identical runtime re-baseline before every live arm

**The defect.** A2's arms ran back to back. SERIAL voided on a health event
whose two recovery reloads changed host free memory from 4,676 MB to 15,410 MB
before NATURAL started. A voided arm was allowed to hand its recovery storm to
the next arm as a starting condition, and no arm-level check looked.

**The repair.** `tools/arm_baseline.py`, run at every arm boundary:

```text
ARM BOUNDARY
  verify no stray runner processes      (before any mutation)
  verify no recovery in progress        (from the previous arm's manifest)
  settle after a previous arm's recovery
  verify/restore the EXACT resident pool
  verify the host-memory floor
  freeze the resident-set witness
  then start the arm
```

Three deliberate choices:

- **No inference.** Nothing here sends a completion request. A probe would warm
  the model and the bridge, reintroducing exactly the blind spot repair 2 exists
  to remove. Residency is verified from the server's `/api/v0/models` state
  field.
- **Exact pool, not "at least".** The runner accepted any resident subset of
  `hot_set` with at least AGENTS members. An extra resident model changes
  contention for every model in the pool, and the health expectation surface is
  conditioned on load.
- **Strays checked first.** Loading or unloading while another runner is live
  would corrupt that run. This ordering was added after the tool, on its first
  smoke test, unloaded the whole pool during a live test — see the incident note
  in `tools/arm_baseline.py`.

**If an arm voids on runtime health: stop it, restore the baseline, then begin
the next arm.** A void does not cascade into the next arm's starting condition.

---

## Repair 4 — the world clock anchor (SCOPE QUESTION)

**This exceeds the three repairs named above and is flagged rather than
smuggled in.** It is implemented in the working tree and is the user's to accept
or revert before A3 runs.

**The defect.** `_run_start_ms` was declared, documented at its own declaration
as "set when the tick loop actually begins", and **never assigned**. It stayed
0, which anchors world time to *engine start*. Godot boot plus the bridge
residency handshake takes ~410 ms, so tick 0's deadline had already passed
before the first observation existed.

Measured directly in A2, `submitted_ms - tick*250`:

```
                tick 0        after tick 400
NATURAL         417-418 ms    6 ms
EQUALIZED       407-418 ms    7 ms
```

The clock silently resynchronised once real time caught up with it.

**Why it matters.** This is what voided the EQUALIZED arm. Its two breaches
completed **604 ms and 650 ms after they were submitted**, comfortably inside
the 1000 ms equalizer. They breached only because the deadline was measured from
a moment 410 ms before the run began.

```
agent    submitted   completed   from submission   from the unanchored clock
agent_0    407 ms      605 ms        198 ms              605 ms
agent_1    408 ms     1012 ms        604 ms             1012 ms   BREACH
agent_2    418 ms     1068 ms        650 ms             1068 ms   BREACH
```

**The repair.** `_run_start_ms = Time.get_ticks_msec()` at the top of
`_run_ticks()`, which is what the comment always said happened.

**It is the same species of defect as repair 1** — declared, documented,
implemented nowhere — and leaving it in place would make A3's EQUALIZED arm void
for the same non-reason. It is a missing assignment, not a parameter change:
no threshold, constant, or decision rule moves.

The manifest now also records `run_start_ms`, so this is externally checkable in
every future run. It is recorded in the **manifest only, not in `to_row()`** —
the envelope row feeds the corpus hash that arm 4 replays against, and changing
that schema would invalidate replay provenance.

---

## Order of operations

1. Repairs 1, 3 and 4 land and are committed.
2. `tools/gate4_sabotage.py` must PASS. The live runner must void when a model
   disappears.
3. Repair 2's gate runs and **freezes** the equalizer delay by the first-passing
   rule. Whatever it returns is used, including "infeasible".
4. Only then does A3 run, in the frozen arm order, with
   `tools/arm_baseline.py` at every boundary.
5. No interpretation until all four arms complete.

If a gate fires during A3, it wins. No amendments, no tuning, no quick fixes.

## What A3 cannot fix

A3 repairs the instrument. It does not make A2 confirmatory, and it does not
answer the recovery-neighbour coupling question — that is bridge mechanics with
its own pre-registration, tracked in `docs/results/RECOVERY_COUPLING.md`, and it
does not belong inside an ASYNC experiment.
