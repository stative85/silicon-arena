# POPULATION REGIMES — what an Arena result was collected *from*

**Frozen 2026-09-08.** Every Arena result belongs to a population regime. The
regime is a property of the run, is never inferred from the write-up, and
**results from different regimes are never pooled.**

This exists because the boundary was nearly invisible. The canonical roster
looks like a naming and config change. It is a change of population
architecture.

---

## The regimes

```text
REGIME A -- 3 species, 5 agents, multiplicity 2+2+1
            stablelm-2-zephyr-1.6b   x2
            h2o-danube3-4b-chat      x2
            gemma-3-1b-it-fast-guff  x1
            roster: live-discovered by tools/build_roster.gd
            period: every Arena result up to and including 2026-09-08
            status: CLOSED -- the roster that produced it is superseded

REGIME B -- 5 species, 5 agents, multiplicity 1+1+1+1+1
            liquidai/lfm2.5-1.2b-instruct   VANTA
            falcon-h1-1.5b-instruct         KESTREL
            qwen3.5-2b                      GEMMATRON
            rwkv7-1.5b-g1                   OZONIOUS
            h2o-danube2-1.8b-chat           BRINE
            roster: frozen membership, tools/build_canonical_roster.py
            period: from 2026-09-08
            status: CURRENT
```

Not one model is shared between them. Regime A and Regime B have **zero species
overlap** — it is not a roster that grew or swapped a member, it is a disjoint
population.

## The rule

```text
A result is valid FOR THE POPULATION THAT PRODUCED IT.

Regime A results remain valid Regime A results, permanently. They are not
degraded, deprecated, or superseded by Regime B.

They are NEVER silently pooled with Regime B results, and any comparison
across the boundary is a comparison across a changed POPULATION
ARCHITECTURE -- not a changed condition, not a config difference, not a
checkpoint bump.
```

A cross-regime comparison is not forbidden. It is forbidden to make one
*without naming it as one*.

## Why this is not pedantry

Regime A conflates two factors that Regime B separates:

```text
Regime A asks:  what does a 5-agent system do?
                ...with 3 species and duplicated instances

Regime B asks:  what does a 5-agent system do?
                ...with 5 species and no duplication
```

Any Regime A → B difference has at least two candidate explanations —
heterogeneity increased, and duplication disappeared — and the design cannot
separate them. Attributing such a difference to heterogeneity alone is the
species-attribution error from `ARENA_IDENTITY_LAYERS.md`, one level up:
attributing a *system* difference to one of several simultaneously changed
factors.

## Regime A is observational data for a future experiment

The multiplicity manipulation reserved in `arena-species.v1.json`:

```text
5 distinct species          Regime B          data exists
3 species + duplicates      Regime A          data exists, NOT randomised
1 species x 5 instances     never run         no data
```

Regime A already occupies one corner of that design space. **It is
observational, not randomised**: nobody assigned that composition as a
condition, it was whatever `build_roster.gd` discovered on the machine that day.

So it may be used as:
- a description of what that population did, and
- a source of hypotheses and effect-size expectations for a designed run,

and may **not** be used as:
- a control arm for Regime B,
- evidence that multiplicity does or does not matter,
- one half of a two-condition comparison.

The distinction is the same one that quarantined the qwen3.5 block: a clean,
complete, real dataset that was never assigned as a condition does not become
causal evidence by being tidy.

## Enforcement

Every result artifact must be attributable to a regime, mechanically:

```text
python tools/population_regime.py --audit
```

- 151 artifacts predate the field. They are attributed to Regime A by the frozen
  snapshot `config/population-regime-a-legacy.json` — **never by editing the
  artifacts**. Adding a tag an artifact did not have when it was written
  falsifies provenance, however true the tag is.
- Any artifact NOT in that snapshot must declare `population_regime_id`, or it
  is **REFUSED**. Not warned about.
- An unknown regime value is refused. A frozen Regime A artifact claiming to be
  Regime B is refused.
- The snapshot is content-hashed and the hash is pinned in the tool. Appending a
  name to the legacy list — the obvious way to silence a refusal on a new
  untagged artifact — changes the hash and is refused. The escape hatch is
  deliberately noisy: edit the list AND update the pin, in a commit that says
  why.

## Provenance

Regime A's exact roster is recorded in `HISTORICAL_ROSTER_PROVENANCE.md`,
including the two honesty limits on the preserved bytes (`captured_at` UNKNOWN;
the sha256 is of a reconstruction, byte-identity UNVERIFIED). The composition
table there is the surviving authority if the local copy is lost.
