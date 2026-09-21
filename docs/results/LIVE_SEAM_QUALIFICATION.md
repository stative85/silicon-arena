# The live decision seam, qualified — ACTION_SCHEMA_V1 at context 2048

**Gate:** can each species select the correct operation out of the full
sixteen-way union and fill that operation's fields, in one generation, with no
repair and no retry?
**Interface:** `config/action-schema.v1.json` — `ACTION_SCHEMA_V1`, the exact
grammar the Arena will constrain generation with
**Verdict source:** `scripts/breach/output_parser.gd`, unmodified (LAW 3)
**Regime:** `SOLO_RESIDENCY`, one species at a time, peak 2,646 MiB
**Context:** 2048 for all five, identical

```
                LIVE (union, verb not pinned)
  lfm25          16/16
  falconh1       16/16
  qwen35         16/16
  rwkv7          16/16
  danube2        16/16
                 ------
                 240/240 accepted, zero parse failures
```

Provenance recorded in every artifact:

```
live_schema_sha256       971592ddbf8f7c3d653a5a0d10ef5b4ee9281082ce01612ac392e4a92140e2d0
parser_sha256            ab202f64256338b4ec13f908a20332dfe849991828ae103768ce8b009bb58916
prompt_contract_sha256   d67fe24d9af17cd6c3fce7a2e9cc4514b72b5b0b7fdeaf5dda3d353808c8e88d
temperature 0.0   max_tokens 512   generations_per_cell 1   repair false   retry false
```

## Why the earlier 240/240 was not this

`STEP_1A_VERB_ACCESS.md` reported 240/240 under a per-operation schema whose
discriminator was `"enum": [op]` — the verb was **pinned by the grammar**. That
proved every species could fill a named operation's fields. It could not prove
selection, because selecting wrongly was structurally impossible.

`ACTION_SCHEMA_V1` is a sixteen-branch discriminated union: the model chooses
the verb, and the chosen branch then requires exactly that verb's fields,
`additionalProperties: false`. `NO_OP` is absent by design — it is host-authored,
and a seam that let an agent select it would let a model declare its own turn
void, which the parser refuses on purpose.

## The defect this found, which was in the harness

The first union run returned **14/16 for all five species**, failing exactly
`GIVE` and `OFFER` — the only two multi-field verbs. A uniform failure across
five unrelated architectures is the signature of the instrument, and it was.

The backend converts JSON Schema into a GBNF grammar in which the order of
`properties` **is the required emission order**. Godot's
`JSON.parse_string -> Dictionary -> JSON.stringify` round trip **reorders object
keys alphabetically**. `GIVE` therefore arrived as `object, operation, target`
and the grammar demanded `"object"` first. A model that correctly begins with
`"operation"` could only be inside a branch whose first property is
`operation` — the single-field verbs. `GIVE` and `OFFER` were unreachable and
`MOVE` fell out instead.

Isolated on the probe's own request body, model and prompt held constant:

```
properties as written (operation first)    -> {"operation":"GIVE","target":...,"object":...}
properties alphabetised (object first)     -> {"operation":"MOVE","target":...}
godot order, operation restored to first   -> {"operation":"GIVE","object":"target",...}
```

The third line is the proof: restoring only the discriminator recovers verb
selection while the remaining fields still fill in grammar order rather than in
meaning. Ruled out first, each with no effect: `minLength: 1` versus `1.0`, the
extra `$schema`/`title`/`description` keys, `anyOf` versus `oneOf`, and
two-branch versus sixteen-branch unions.

`h2o-danube2` had already said as much in its raw output, by cramming three
values into one permitted field:

```
{"operation": "OBSERVE", "target": "chamber_north, key_blue, requested=key_red"}
```

That is a model supplying fields the grammar would not let it write.

**This is a live-arena hazard, not only a probe bug.** When the seam is wired
into `LiveModelDecider`, any GDScript that builds the request by stringifying a
parsed schema Dictionary corrupts the grammar in the same silent way — and the
symptom is models appearing to prefer simple verbs, which is indistinguishable
from a behavioural finding. The seam is now read as text, validated by parsing,
and sent as bytes. The reason is written at the load site.

## The frozen file has a drift tooth

`config/action-schema.v1.json` is frozen and hashed into every artifact, which
is also how it would silently stop matching `canonical_operation.gd`.
`tools/action_schema_selftest.gd` checks membership, the absence of `NO_OP`,
and that every branch requires exactly its fields and permits nothing else.
It was sabotaged three ways and caught all three: a dropped verb (`UNLOCK`), an
agent-selectable `NO_OP`, and a dropped required field (`OFFER.requested`).

## What is now established

- Five species co-reside at 2048 with all five genuinely GPU-resident
  (`CONTEXT_SWEEP_BREACH0.md`)
- Every species reaches every verb through the pinned schema
  (`STEP_1A_VERB_ACCESS.md`)
- Every species **selects** the correct verb out of the full union and fills its
  fields, one generation, no repair, no retry — this document

Step 1a is satisfied at context 2048 under `ACTION_SCHEMA_V1`.

## What is not established

**Free-form emission remains withdrawn.** `scripts/breach/decider.gd` still
describes the live seam as raw text returned unmodified; on the evidence in
`STEP_1A_VERB_ACCESS.md` that path measures prompt wording. The decision to use
a constrained decode is a human one and it changes the claim surface: the
harness is helping models that cannot structure output. The help is uniform
across species, which is the acceptable kind, and it must be stated in any
species comparison rather than assumed away.

**Access is not usage.** Every cell here was produced under instruction naming
the operation. Nothing in this document says what any species would choose in a
world, and a later difference in what they choose is a behavioural result with
its own witness requirements.

**SOLO_RESIDENCY is not the pool.** Verb access is a property of the model and
the contract; speed is not what this gate measures. A verb that parses solo and
fails in-pool would be a placement problem, which has its own detector.
