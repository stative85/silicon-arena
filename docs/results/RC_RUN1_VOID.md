# RECOVERY-COUPLING Run 1 — VOID / TERMINATED

```text
VERDICT:          VOID / TERMINATED
CAUSE:            PREDEFINED RAM_FLOOR_EVENT, fired repeatedly
CAUSAL QUESTION:  UNANSWERED
NO RECOVERY-COUPLING INFERENCE
```

Terminated on a frozen integrity criterion after it fired repeatedly, **not** on
the causal outcome — the causal outcome never became interpretable. Start state
was witnessed healthy and frozen before window 0: fresh backend, counts 1/1/1,
17,308 MB host free, schedule hash `9c9dbd9ca0c45252`, health surface
`14536bd0e92f16ba`, `ks/kh/n = 1.8/20/3`, baseline PASS.

## A CORRECTION I OWE THE RECORD

While the run was live I reported, from the first eleven windows, that LM
Studio's memory grew **monotonically** and that the run would produce a
**near-total void record**. **Both statements were wrong**, and the decision to
terminate was taken partly on them.

The incremental-write change persisted 41 windows. What actually happened:

```text
CLEAN   23   (12 TREATMENT, 11 CONTROL)
VOID    18   ( 9 TREATMENT,  9 CONTROL)   all RAM_FLOOR_EVENT
```

RAM collapsed at window 2, stayed depressed through window 19, then **recovered
to 10,320 MB at window 21** and ran clean for twenty consecutive windows. It was
a transient block, not unbounded growth.

I extrapolated a monotone trend from a truncated view after stopping the monitor
that would have shown me otherwise. The termination remains defensible on the
frozen rule — nine consecutive predefined integrity failures — but the
supporting claim I gave for it was not true.

## What the run actually produced

```text
rotation     condition   CLEAN   VOID
lfm2.5       TREATMENT       1      9
lfm2.5       CONTROL         1      9
qwen3.5      TREATMENT      10      0
qwen3.5      CONTROL        10      0
falcon       TREATMENT       1      0
falcon       CONTROL         0      0

windows run: lfm2.5 20/20, qwen3.5 20/20, falcon 1/20
```

Host free RAM by window, showing the block structure:

```text
win 0-1     6337, 3598      CLEAN
win 2-19    1043 - 1726     VOID   (entire lfm2.5 rotation)
win 20      2630            CLEAN
win 21-40   10333 - 7584    CLEAN  (entire qwen3.5 rotation + 1 falcon)
```

The depression is **coincident with the lfm2.5 rotation block and released at
the rotation boundary.** Both conditions were hit equally — 9 TREATMENT and 9
CONTROL — so within that block the integrity failure did not differentially
delete one condition. That is a block/time effect, not a condition effect.

## Why the causal question is still unanswered

The design requires all three rotation positions. One is essentially void, one
is complete and clean, one barely started. The directed causal matrix cannot be
assembled:

```text
recover lfm2.5  -> lfm2.5 rotation is 18/20 void
recover qwen3.5 -> complete, clean
recover falcon  -> 1 of 20 windows run
```

**The qwen3.5 rotation is a complete, clean, 20-window block** (10 treatment, 10
control). Whether that constitutes evidence or a fossil is a protocol decision
and is deliberately **not made here**. Arguments both ways are recorded so the
decision is not made by whoever looks at the numbers first:

- *For:* it is a full preregistered rotation position, gate-clean throughout,
  with matched controls, and the voids in it are zero.
- *Against:* it ran immediately after eighteen windows of demonstrated runtime
  disturbance, so its runtime history is not the one the start-state witness
  certified. Analysing it is analysing the survivors of a nonstationary
  apparatus.

**No analysis of it has been performed.**

## Terminal-state observation, worth its own experiment

Killing the Godot client released roughly ten gigabytes:

```text
                    during run   after client death
host free RAM         1,402 MB          11,701 MB
LM Studio total RSS  21,884 MB          11,596 MB
```

Some of the accumulation was tied to the client connection rather than
permanently leaked. That is a mechanistic clue and is **untested**.

## What is NOT done

The 2 GB floor is not lowered. No periodic-restart patch. No shorter window
chosen because it happens to survive. Windows 0-1 are not analysed as a tiny
successful experiment.

## Next

`docs/EXPERIMENT_RUNTIME_MEMORY.md` — characterise what the runtime accumulates,
under what operation, and whether it plateaus, before RECOVERY-COUPLING is
attempted again.

## Broader result worth preserving

> A workload can begin inside a qualified resource envelope and deterministically
> leave that envelope through measurement-induced runtime accumulation.

The start witness was legitimately healthy at 17.3 GB free. The experiment drove
the host below its own safety floor within two windows, and back out again
nineteen windows later, without any external cause.
