# OBSERVATION V3 diagnostic — preregistration

**Status: PREREGISTERED, NOT RUN.** Written before any stage executes.

V2 is closed as `FAILED SEAM REQUALIFICATION: 234/240` and is immutable. This
diagnostic decides what V3 should be. It cannot revise V2.

## The question

`falconh1` failed `TAKE` and `WITHDRAW_KEY` under V2. Two explanations are live
and they are not distinguished by the evidence so far:

1. **Fixture conflict.** The shared qualification fixture makes those two verbs
   non-executable — `visible_object_ids` and `visible_vault_slot_ids` are both
   empty — and V2 says so where V1 did not. The model may be selecting `MOVE` as
   a prerequisite rather than failing to select the requested verb.
2. **Presentation salience.** V2's encoding makes `MOVE` more available to
   attention than the requested operation.

One static world rarely makes all sixteen verbs simultaneously sensible, so (1)
is not a rescue hypothesis invented after the fact — it was visible in the
fixture's own domains before this document was written.

## Stage 1 — executable fixtures

A separate boring fixture per failed verb, **keeping the exact V2 encoding**.
Nothing about presentation changes.

| verb | fixture |
|---|---|
| `TAKE` | a loose object on the floor here, present in `visible_object_ids` |
| `WITHDRAW_KEY` | actor at the vault, a genuinely withdrawable committed key, every prerequisite satisfied |

Both verbs are also re-run on the original shared fixture, unchanged, as the
control.

**Interpretation, fixed now:**

```
falcon returns 3/3 on both executable fixtures
    -> the shared fixture contradicted the requested action
    -> V2 is NOT convicted; the qualification fixture is the defect

falcon still chooses MOVE on executable fixtures
    -> presentation regression is real and survives Stage 1
    -> proceed to Stage 2
```

If Stage 1 clears V2, **Stage 2 is not run**, and V3's job is narrower: fix the
qualification fixtures, not the encoding.

## Stage 2 — semantically identical presentations

Run only if Stage 1 does not clear V2. Uses the executable fixtures. The same
visible information, three encodings, nothing else changed:

1. the current V2 encoding
2. neutral entity-type domains, with operation names **not** repeated in the
   dynamic packet
3. the same neutral data, ordering permuted

**Interpretation, fixed now:**

```
results move with ordering            -> serialization / order salience
neutral domains restore both verbs    -> action-labelled presentation made
                                         MOVE salient
all three fail                        -> V2's added information overwhelms the
                                         requested-operation instruction
only non-executable fixtures fail     -> prerequisite planning, not interface
                                         loss
```

## Likely V3 direction, recorded before the evidence

Stated now so it can be contradicted by the result rather than fitted to it:

- the dynamic packet carries only **neutral typed identifier sets**
- the **static contract** explains which field consumes which set
- operation names are not repeatedly attached to dynamic lists
- **every qualification cell uses a state where the requested operation is
  actually executable**

That last point is a change to the qualification method, not to the observation
contract, and it applies regardless of which way this diagnostic falls.

## Bar for advancing

V3 is created after this diagnostic, never by editing V2, and must restore a
complete **240/240** on the sixteen-verb seam. Only then is the free-choice V2
check run. No causal experiment resumes before that, and any causal experiment
that does resume is **FLOWSCAR5**.

## A consequence for V1 that must not be quietly dropped

V1 scored 240/240 while qualifying `TAKE` and `WITHDRAW_KEY` against a state
where neither was executable. It passed because the packet did not reveal the
contradiction. **V1's 240/240 is therefore weaker than it was reported to be**,
and that is a correction to an already-signed result, recorded here rather than
left implicit.
