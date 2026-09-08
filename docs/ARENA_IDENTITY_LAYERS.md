# ARENA IDENTITY LAYERS — three layers, no inference between them

**Status: FROZEN BOUNDARY, 2026-09-08.**

> Display names may decorate identity, frozen membership defines population,
> runtime incarnation defines multiplicity, **and none may infer the others.**

Each layer answers exactly one question, owns exactly one file or fact, and is
never reconstructed from a neighbour. Smearing them together is how a roster
drifts, how a label becomes provenance, and how "we ran five models" quietly
turns into "we ran three models twice".

---

## The layers

```text
LAYER 3   DECORATION      what humans see
          config/arena-names.v1.json
          VANTA KESTREL GEMMATRON OZONIOUS BRINE
          authority: none. Decorates. Decides nothing.
                    |
                    | one-way: display_for(model_id)
                    v
LAYER 2   POPULATION      who is in the Arena
          config/arena-species.v1.json
          five model_ids, one instance each
          authority: total over membership
                    |
                    | membership is a DECISION, not an observation
                    v
LAYER 1   INCARNATION     how many of each are actually resident
          the live runtime: qwen3.5-2b, qwen3.5-2b:2, ...
          authority: total over multiplicity
          observed as a COUNT MAP, never set membership (Law 5)
```

## The forbidden inferences

Each of these has been either mechanically blocked or written as a refusal:

| # | forbidden | why | enforced by |
|---|---|---|---|
| I-1 | decoration → population | a name must never add or remove a member | sabotage: deleting `GEMMATRON` keeps the species; adding `INTERLOPER` adds nobody |
| I-2 | decoration → identity | a label in a provenance field re-points every artifact that resolved through it | `arena_names --audit`, 155 artifacts, plus a planted-name sabotage |
| I-3 | population → incarnation | declaring a species does not assert it is loaded | membership rejects instance suffixes; residency is measured, never assumed |
| I-4 | incarnation → population | two instances resident does not make two members | `instances_per_species` must be 1; duplicates refused with a preregistration message |
| I-5 | incarnation → decoration | `GEMMATRON` and `GEMMATRON:2` must stay visibly distinct | display carries the suffix; species_id does not |
| I-6 | population → decoration | an unnamed member renders as its raw id, never a derived one | `label()` falls back to the raw `model_id`; no title-casing |

I-6 is the one with a corpse already: `build_roster.gd` title-cased ids into
`"H 2o Danube 3 4B #1"` — an invented string presented with exactly the
confidence of a real one.

---

## Persona: a fourth thing, and the rule that keeps it honest

Persona is **not** a layer. It is a treatment bound to the agent slot, and with
one instance per species it is perfectly confounded with species. The correction
is not to rotate personas everywhere — rotation changes prompt identity, social
framing, contention and possibly memory formation, so it is *another treatment*,
not a neutralisation. Over-correcting here turns every run into a factorial
nightmare and buys nothing.

The rule is about **what the claim says**, not about how the run is configured:

```text
SYSTEM-LEVEL ECOLOGY CLAIM
  "This five-agent system, with these models and these frozen
   personas, produced X."
  -> frozen persona assignment is ALLOWED
  -> the claim attaches to the whole configured system
  -> persona and species may stay entangled, because nothing is being
     attributed to either one alone

SPECIES-ATTRIBUTION CLAIM
  "VANTA behaves differently BECAUSE it is LFM2.5."
  -> persona must be controlled EXPERIMENTALLY
  -> rotate / Latin square / neutralise / otherwise PREREGISTER
  -> without that control the claim is unsupportable, however clean
     the data looks
```

The trap is drift, not configuration. A run is designed as system-level, the
results are interesting, and the write-up reaches for the species explanation
because it is the more exciting sentence. **The moment a sentence attributes
behaviour to a model rather than to the system, it has silently switched claim
types and needs the control it never had.**

State the claim type in the preregistration, before the data exists.

---

## What is frozen here

- The three layers, their files, and their one-way direction.
- The six forbidden inferences.
- The persona claim-type rule.

## What is not decided here

- Whether any given experiment is system-level or species-attributing. That is
  per-experiment and belongs in its own preregistration.
- The multiplicity manipulation itself (5 distinct vs 3+duplicates vs 1×5). It
  is reserved, not designed. Note that every result predating 2026-09-08 was
  collected under a **3-species + duplicates** population — see
  `HISTORICAL_ROSTER_PROVENANCE.md` — so that arm has observational data and
  the other two do not.
