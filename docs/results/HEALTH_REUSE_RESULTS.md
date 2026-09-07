# HEALTH-REUSE — results, and the frozen health diagnosis

Run at prereg `e592be8`. Two processes, counterbalanced order, 200 rounds per
condition, all three models probed simultaneously, shadow mode,
`ks=1.8 / kh=20 / n=3` untouched. 2,400 calls.

Both runs passed their teeth: **exercised = true** (10 distinct prompts in
CYCLING vs 200 in UNIQUE) and **zero prompt-token mismatches** between
conditions. A null here would have meant something; it isn't a null.

## Why counterbalancing was load-bearing

Read naively, the two runs disagree:

```text
qwen3.5 SUSPECT rate
  r0_cu (CYCLING first)   CYCLING 19.0%    UNIQUE 75.0%
  r0_uc (UNIQUE first)    UNIQUE  39.0%    CYCLING 46.5%
```

In the first run reuse looks decisive. In the second it looks absent, even
slightly reversed. The difference is **position**, not condition — the second
half of a process is worse than the first in both runs:

```text
within-process, 1st half -> 2nd half (qwen SUSPECT)
  r0_cu   19.0% -> 75.0%   (+56.0)
  r0_uc   39.0% -> 46.5%   (+7.5)
```

Controlling for position by comparing like slot against like slot:

```text
CYCLING minus UNIQUE, SUSPECT rate in percentage points
                 position 1   position 2      mean
lfm2.5              -2.5        -13.0         -7.8
qwen3.5            -20.0        -28.5        -24.2
falcon              +0.5         -1.5         -0.5
```

Consistent sign in both positions for qwen and lfm2.5. **falcon, the control,
does not move** — so the intervention is not changing general runtime behaviour.

## Verdict: reuse contributes, and does not explain

Prompt-set reuse has a real, repeatable, model-specific effect: roughly **24
percentage points** of qwen's SUSPECT rate and **8** of lfm2.5's.

But the pre-registered first reading required CYCLING to reproduce cell-A-like
health, and it does not:

```text
ASYNC-B cell A          ~0% (0 DEGRADED in ~1,600 calls)
HEALTH-REUSE CYCLING    19.0% best case, 46.5% at position 2
```

Reuse closes part of the gap and leaves most of it open. This lands on the
**mixed** branch: a specific interaction is isolated, the missing variable is
not fully identified, and **no repair may be designed from it.**

## The dominant finding, which was on nobody's list

```text
share of qwen3.5 residuals within +/-0.10 of ks = 1.8
  r0_cu   58.2%   (n = 400)
  r0_uc   61.5%   (n = 400)
```

**Qwen's residual distribution is centred almost exactly on the threshold.**
Around 60% of its calls land within a tenth of `ks`.

That single fact explains the entire confusing history:

- Why the same nominal condition produced 13% and 69% in HEALTH-DUTY.
- Why a ~0.1 shift in median residual moves SUSPECT rate by 50 points.
- Why cell A could sit at 0% without needing a large advantage — it only needed
  a small favourable shift.
- Why every diagnostic so far has looked unstable and contradictory.

**SUSPECT rate is an amplifier, not an effect-size measure, in this regime.**
It does measure threshold crossings, and it measures them correctly. It simply
becomes a wildly nonlinear proxy for the underlying residual when ~60% of the
mass sits within 0.10 of the boundary, so it cannot be read as a magnitude. Residual medians are far better behaved:
qwen moved only 1.73-1.86 across every condition in this experiment while its
SUSPECT rate swung from 19% to 75%.

The detector is not malfunctioning. Qwen simply lives on the line.

---

# FROZEN HEALTH DIAGNOSIS

No live repair was performed inside any diagnostic. `ks=1.8 / kh=20 / n=3`
remain exactly as frozen.

```text
1. LOW-END SLOPE ERROR            CONFIRMED x3
   lfm2.5 and qwen3.5 only; falcon's surface tracks correctly and is the
   control that makes the finding readable. Their TTFT is dominated by a
   fixed cost in this regime while the surface imposes a downward slope.

2. STREAK DETECTOR (n=3)          ACQUITTED
   Streaks follow from the SUSPECT base rate, not from autocorrelation.
   At p ~ 0.975 three in a row is inevitable with zero correlation. My own
   autocorrelation hypothesis was tested and refuted.

3. CLIENT SESSION STRUCTURE       NOT THE EXPLANATION
   CELL_LIKE produced the highest SUSPECT rate of three measurements.

4. PROMPT-PREFIX CONTINUITY       FALSIFIED WITHOUT A SINGLE CALL
   Production had none either: LCP median 25 chars = header only, and the
   first list item changed on 100% of rounds.

5. PROMPT-SET REUSE               REAL BUT PARTIAL
   -24.2 points for qwen, -7.8 for lfm2.5, -0.5 for falcon, position
   controlled. Does not reproduce cell A's ~0%.

6. THRESHOLD PROXIMITY            NEW, AND DOMINANT
   ~60% of qwen residuals sit within 0.10 of ks. SUSPECT rate is therefore
   an unstable statistic in this regime and a poor experimental outcome.

7. ABSOLUTE LEVEL OFFSET          STILL UNRESOLVED
8. ANCHOR CONTRADICTION           STILL UNEXPLAINED
```

## Consequences for any future repair

Two requirements this chain generated, recorded so a repair cannot quietly skip
them:

- A repair must **move qwen's median residual off the threshold**, not merely
  reduce the SUSPECT rate. Rate reductions in this regime can come from
  amplification alone.
- A repair must **not disturb falcon**, whose surface is demonstrated correct
  across five experiments and ~4,000 calls with zero SUSPECT verdicts.

And a methodological one: **stop using SUSPECT rate as a primary outcome for
qwen.** Report residual medians and distributions. The rate remains worth
reporting as the operational consequence, but not as the measurement.

Nothing fitted. No knot, threshold or contention-factor change. No
OUT_OF_PROFILE. No RECOVERY-COUPLING. No B2.
