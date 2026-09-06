# PIT A, Run 1: VOID

**No architectural interpretation may be drawn from this run.** Phases 2 through
7 of the analysis plan were not performed and must not be performed on this data.
Operation frequencies, trajectories, recurrence, survival, dependency behaviour
and convergence from Run 1 are **instrument diagnostics**, never species results.

## Provenance

```
  prereg commit              15f30e9
  amendments in force        e4faf3e  (RANDOM control scope)
                             3adfb84  (LFM2.5 identifier)
  instrument commit          c1688d7
  probe/journal commit       673a750
  runner commit              91d8d1e
  load fix                   523ced8
  run commit (HEAD)          3adfb84
  runtime                    llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.14.0
  context / quant            8192 / Q4_K_M, all five species
  schema hash                a671fce77b5b0998...
  genesis hash               5e7a696d4176e40d...
  consequence schedule hash  39a34975b48d2658...
  started                    2026-09-05T23:40:41

  raw artifacts   D:\PIT_A_RAW_20260905_185125\
                  18 journals + manifest.json + SHA256SUMS.txt (19 entries)
                  IMMUTABLE. Preserved as evidence of the defect, not as data.
```

## Execution facts

```
  journals              18   (5 species + RANDOM) x 3 replicates
  cycles             1,800   100 each, none short
  REQUEST_FAILED         0
  chain breaks           0
  open half-cycles       0
  schema-valid JSON  1,500 / 1,500 model calls
```

All eleven startup gates passed against the live runtime. Every species loaded at
**8192 effective** context, not native. Five distinct architecture strings
confirmed by the runtime.

## Why it is void

**The frozen model-facing schema could not express the action space the
validator and the RANDOM arm could exercise.**

The schema exposed exactly three fields:

```
  operation   target   explanation
```

`PitValidator` requires `type` for ADD, and `props` for a meaningful ADD or
MUTATE. **Neither is expressible through the frozen schema.** Every ADD any
species proposed was therefore rejected `UNKNOWN_TYPE` before it could ever
reach the world — 1,167 of 1,500 model cycles, doomed at the contract boundary
rather than by any decision the model made.

`PitRandom.legal_operations()` constructs ADD patches **with** `type` and
`props`, using fields no model could emit. So the control and the treatment arms
did not share a proposal language:

```
  RANDOM action space   ADD DELETE MUTATE KEEP RESTORE REFUSE   all expressible
  model action space    DELETE MUTATE KEEP RESTORE REFUSE       ADD impossible
```

A control with a strictly larger action space than the treatment is not a
control. It is a different experiment.

**Second defect, independent of the first.** The schema required `target` but
permitted the empty string, so a proposal could be schema-valid and semantically
impossible for any target-dependent operation. LFM2.5 emitted
`{"operation":"DELETE","target":""}` on all 300 of its cycles — satisfying the
instrument and failing the validator every time.

## Instrument diagnostics, and nothing more

```
  SPECIES                          accepted   proposed operation mix
  RANDOM                            300/300   DELETE 93 MUTATE 78 RESTORE 56 ADD 54 KEEP 11 REFUSE 8
  falcon-h1-1.5b-instruct            30/300   ADD 270 KEEP 27 DELETE 3
  h2o-danube2-1.8b-chat               3/300   ADD 297 DELETE 3
  liquidai/lfm2.5-1.2b-instruct        0/300   DELETE 300
  qwen3.5-2b                           0/300   ADD 300
  rwkv7-1.5b-g1                        0/300   ADD 300

  reason codes
  RANDOM        OK 300
  falcon-h1     UNKNOWN_TYPE 270, OK 30
  danube2       UNKNOWN_TYPE 297, OK 3
  lfm2.5        MALFORMED_PATCH 300
  qwen3.5       UNKNOWN_TYPE 300
  rwkv7         UNKNOWN_TYPE 300
```

**Three of five species produced no state transition in 300 cycles each.** Their
final world hash is byte-identical to genesis. Nine hundred model cycles across
three architectures changed nothing, because the contract made their chosen
operation inexpressible — not because they chose to preserve anything.

> Reading "qwen3.5 and RWKV-7 always chose ADD" as a preference would be
> reporting which operation each model happened to guess against a schema that
> could never accept it. Reading "LFM2.5 always chose DELETE" the same way would
> be reporting an empty string.

## Why the reachability audit did not catch this

The audit proved every operation reachable **against hand-built validator
patches**, including `{"operation":"ADD","target":"n1","type":"rule","props":{}}`
— a shape no model could ever emit. It validated the validator and never
validated the path from the frozen schema *to* the validator.

That is the same failure class this project keeps paying for: a guard tested
against inputs written by its own author. It is the eighth such defect found in
this experiment, and the largest, because it survived long enough to consume
1,800 generations.

**The rule this earns, for CONTRIBUTING:**

> An action is not reachable because the validator accepts a hand-built example.
> It is reachable only if the experimental producer can express that example
> through its frozen interface. **Reachability must be end-to-end, not
> component-local.**

## What Run 1 does establish

Strictly one thing, and it is about plumbing rather than architecture:

> The execution, journal, checkpoint and runtime machinery completed 1,800
> cycles cleanly — every startup gate enforced, every cycle journalled and
> flushed, zero chain breaks, zero request failures, zero half-cycles, and all
> five architectures emitting schema-valid JSON on every call through one common
> constrained-output instrument.

**It provides no valid evidence for the PIT A architectural hypothesis.**

## Disposition

Run 1 journals are **immutable and preserved**. Nothing is deleted. Run 2 is a
distinct regime with a new schema hash, a fresh genesis, fresh journals and its
own manifest, and it may not be compared against Run 1 on any descriptor.
