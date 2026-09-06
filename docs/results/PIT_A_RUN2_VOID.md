# PIT A, Run 2: VOID

**No architectural interpretation may be drawn from this run.** Phases 1 through
7 of the analysis plan were not performed and must not be performed on this data.

**The 1,500 model proposals collected here may be used for INSTRUMENT DESIGN
ONLY.** They are a producer-space sample — evidence about what five
architectures actually emit through a given interface. They are **never**
evidence for the PIT A architectural hypothesis, and no descriptor derived from
them may appear in a results document.

## Provenance

```
  prereg commit          15f30e9
  amendments             e4faf3e, 3adfb84, 0005e14 (Run 2 regime), 2f17256
  Run 1 VOID record      2750d17
  instrument commit      e9a074a  (PitProposalContract)
  run commit (HEAD)      e9a074a
  runtime                llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.14.0
  context / quant        8192 / Q4_K_M, all five species
  schema hash            96db47ebda531032...   (Run 1 was a671fce77b5b0998)
  genesis hash           5e7a696d4176e40d...   unchanged
  consequence sched      39a34975b48d2658...   unchanged
  started                2026-09-06T01:18:41

  raw artifacts   D:\PIT_A_RUN2_RAW_20260905_205044\
                  18 journals + manifest + console log + SHA256SUMS (20 entries)
                  IMMUTABLE.
```

## Execution facts

```
  journals              18        cycles          1,800
  chain breaks           0        REQUEST_FAILED      0
  open half-cycles       0        schema-valid JSON   1,500 / 1,500 model calls
```

All eleven startup gates passed. The manifest's schema hash matches the audited
contract exactly. The plumbing is not in question.

## Why it is void

```
  ARM                              accept    dominant reason code
  RANDOM                          300/300    OK
  falcon-h1-1.5b-instruct           0/300    TYPE_FORBIDDEN      (300)
  h2o-danube2-1.8b-chat             0/300    PROPS_FORBIDDEN     (300)
  liquidai/lfm2.5-1.2b-instruct     0/300    TARGET_FORBIDDEN    (300)
  qwen3.5-2b                        0/300    TARGET_REQUIRED     (300)
  rwkv7-1.5b-g1                     0/300    TARGET_EXISTS       (300)
```

**Every species scored zero. RANDOM scored 300/300. Five species, five different
failure codes, each 300 times.**

Run 1 failed because the schema could not express fields the validator required.
Run 2 fixed that and then failed on the **relationships between those fields**.
Ruling out `oneOf` while keeping cross-field rules in the validator moved the
coupling rather than removing it:

```
  KEEP    -> target MUST be "__NONE__"     schema permits any non-empty string
  DELETE  -> type   MUST be "none"         schema permits any enum value
  DELETE  -> props  MUST be empty          schema permits any object
  ADD     -> type   MUST NOT be "none"     schema permits "none"
```

A flat JSON Schema cannot state a conditional. So the interface silently
required five architectures to coordinate fields it never told them were
coupled, and each failed that coordination in its own way.

**The decisive detail is that several decisions were sound and died on an
irrelevant field:**

```
  falcon-h1   MUTATE rule_1, type="rule"          a real mutation, killed by `type`
  lfm2.5      KEEP,   target="object id"          a real KEEP, killed by `target`
  danube2     RESTORE "`entity_1`", props={...}   killed by `props`, and the
                                                  target carries backticks
  qwen3.5     MUTATE, target="__NONE__"           GENUINELY invalid: no target
  rwkv7       ADD entity_1 (already exists)       GENUINELY invalid: id in use
```

The first three are bureaucracy. The last two are real errors that must stay
errors. That separation is what makes the collected proposals worth keeping.

## Why the audit did not catch it

Every end-to-end witness was built by the contract's own constructors —
`K.add()`, `K.keep()`, `K.mutate()` — which set the coupled fields correctly **by
construction**. The audit proved *"a correctly-built proposal round-trips"*. It
never proved *"a schema-valid proposal a model might plausibly emit is
acceptable"*.

I tested the constructors, not the producers. That is the third time in this
experiment a component was validated against inputs its own author wrote, and it
is the second time that error cost 1,800 generations.

**The rules this earns, for CONTRIBUTING:**

> **Producer-space rule.** An experimental interface is validated against what
> the producer can actually emit, never merely against hand-constructed valid
> witnesses.

> **Corollary.** Fields irrelevant to an action must not be able to invalidate
> that action.

## What Run 2 establishes

Two things, both about the instrument:

1. The execution, journal, checkpoint, gate and runtime machinery completed
   1,800 cycles cleanly for the second time, under a fail-closed startup that
   pinned every element of the regime.
2. **The remaining defect is model-facing semantics, not JSON syntax and not
   plumbing.** RANDOM went 300/300 through the identical validator; all five
   species emitted 1,500/1,500 schema-valid documents. What failed sits strictly
   between "parses" and "means something".

**It provides no valid evidence for the PIT A architectural hypothesis.**

## Disposition

Run 1 and Run 2 journals are immutable and preserved. Nothing is deleted. Run 3
will be a distinct regime with its own schema and canonicalisation hash, a fresh
genesis, and its own manifest, and may not be compared against either prior run
on any descriptor.
