# Step 1B, claim 2 — the seam, re-qualified against the changed observation

**Claim:** adding mass to the observation packet did not damage or bias the
decision seam.
**Why this run exists:** `ACTION_SCHEMA_V1` is byte-identical to the version
Section 0 was signed against — but mass added fields to the observation, and the
observation is half of what the model is actually asked. A seam qualified
against the old information surface is not qualified against this one.
**Regime:** `SOLO_RESIDENCY`, one species at a time, context 2048.

```
  lfm25      16/16
  falconh1   16/16
  qwen35     16/16
  rwkv7      16/16
  danube2    16/16
             ------
             240/240 accepted, zero parse failures, no provenance mismatch
```

## Provenance — what moved and what did not

```
live_schema_file_sha256   971592dd…   UNCHANGED   the file Section 0 was signed against
live_schema_wire_sha256   0c0851f0…   UNCHANGED   the bytes the models actually saw
prompt_contract_sha256    bc7d77d5…   NEW         the observation format changed
parser_sha256             ab202f64…   UNCHANGED
repair false   retry false   generations_per_cell 1
```

The schema hash holding still while the prompt hash moves is the whole record of
this step: same seam, different information surface. A single hash covering both
would have hidden exactly this.

## Context fit

```
measurements: { context_ceiling: 2048, max_prompt_tokens_observed: 936 }
```

Taken from the backend's own `usage.prompt_tokens`, never estimated from
character counts. Mass grew the packet from ~806 to 936 tokens across species
and leaves roughly 54% of the ceiling free. The 2048 ceiling Section 0 was
signed at survives the expansion.

## The fixture is encumbered on purpose

The packet is built by the real `ObservationBuilder` — not a hand-written
stand-in, which would qualify a surface the arena does not use. The actor
carries mass 7 against capacity 4, and a co-located agent carries a key, so
`carried_mass`, `move_cost`, per-object `mass` and `visible_carried_mass` are
all present and non-trivial in **every** cell. A fixture where the new fields
were zero or absent would have proven nothing about the new surface.

## No information leaked across rooms

Verified offline in `tools/mass_contract_selftest.gd`, as **bytes** rather than
as structure — a leak through some other field would slip past a structural
assertion:

```
  ok   an agent in another room is not in the packet
  ok   its name does not appear anywhere in the packet
  ok   its carried object does not appear anywhere in the packet
  ok   a co-located agent's carried mass IS exposed (1)
```

Mass is externally visible — you can see what someone is lugging — and it is
bounded by observability. Their energy and memory remain private, as before. A
mass field that crossed rooms would have handed every agent a free long-range
sensor the physics never gave it, and every later behavioural result would have
been about that sensor.

## The instrument caught a defect in itself

The first run returned `240/240` **and** flagged
`provenance_mismatch: [falconh1, qwen35, rwkv7, danube2]` — four of five species
recorded as measured under different instrument state.

The cross-check was right. `max_prompt_tokens_observed` had been placed inside
the provenance block, and it legitimately differs per species because it is a
**measurement**, not instrument identity. The artifact now separates them:

```
"measurements": { max_prompt_tokens_observed, context_ceiling }   what happened
"provenance":   { hashes, temperature, max_tokens,
                  generations_per_cell, repair, retry }           what was run
```

Provenance is identity; measurements are results. Mixing them is how a hash
stops being evidence — the same failure as the wire-versus-file hash corrected
before Section 0 was signed. The run above is the clean re-run, with the
mismatch field absent.

## What this does and does not establish

**Established:** with mass in the observation, all five species still select
every one of the sixteen canonical operations and fill its fields, one
generation each, no repair, no retry, at context 2048, through the unchanged
frozen schema.

**Not established:** anything about spontaneous usage. Every cell names the
operation to emit. Nothing here says whether a species would ever choose to
overload itself, shed weight, hand a burden to someone else, or walk into a room
it cannot walk out of. That is a behavioural claim and it needs its own witness.

**Not established:** that mass is *used well*. The seam is undamaged; whether
the physics is legible to a 1.2B model in play is a different question, and the
only honest way to answer it is to run the arena.
