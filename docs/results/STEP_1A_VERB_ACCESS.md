# Step 1a — verb access qualification at context 2048

**Gate:** can each species emit each of the 16 agent-choosable operations through
the frozen interface, such that the real parser accepts it?
**Regime:** `SOLO_RESIDENCY` — one species loaded at a time, ~1.1 GiB resident,
peak 2,645 MiB including desktop
**Instrument:** `tools/verb_access_serial.py` driving
`tools/breach_verb_access.gd`
**Verdict source:** `scripts/breach/output_parser.gd`, unmodified (LAW 3)
**Context:** 2048 for all five, identical — the ceiling established by
`CONTEXT_SWEEP_BREACH0.md`

This measures **access under instruction**: every prompt names the operation to
emit. It is not a measure of what a model would choose, and no species is
compared against another. A species that can reach a verb and never picks it
has passed; one that cannot reach it makes every later difference
uninterpretable.

## Result

```
                FREE        SCHEMA
  lfm25          1/16        16/16
  falconh1      12/16        16/16
  qwen35         5/16        16/16
  rwkv7          5/16        16/16
  danube2       14/16        16/16
                             ------
  SCHEMA total              240/240 accepted, zero failures
```

**Under a grammar-constrained interface, all five species reach all sixteen
operations, three reps each, with no parse failure of any kind.** Step 1a is
satisfied at context 2048 — conditional on the arena using a constrained
decode.

## The FREE arm is not a finding. It is a measurement of my prompt.

Both runs of the free-form arm were contaminated by the contract wording, in
the same way, twice:

```
run 1   contract line:  MOVE  requires: target
        falcon-h1 emitted:  {"operation":"MOVE","requires":"target"}

run 2   contract line:  MOVE  (fields: target)
        qwen3.5 emitted:   {"operation":"TAKE","fields":{"target":"chamber_north"}}
```

I replaced one leaky word with another and the echo moved species. `qwen3.5`
went 16/16 to 5/16 between runs without anything about the model changing.
That is the instrument swinging, not the subject.

Free-form numbers are therefore **withdrawn**. They are recorded here only as
evidence that the free-form contract is not yet a valid instrument: any contract
noun that can be mistaken for a JSON key will be mistaken for one, by whichever
species happens to be susceptible to that phrasing.

Run 1 also carried two further instrument defects, both corrected before this
run: a single all-operations schema that pushed every species to answer `GIVE`
and `OFFER` with `text` where `object` belonged (a uniform failure across five
unrelated architectures — the signature of the instrument), and a 160-token
ceiling that truncated a verbose answer into `not_json`.

## What this decides, and what it hands back

**Decided:** the sixteen verbs are reachable by every member of the frozen
population at the 2048 ceiling. No species has to be dropped for inability to
speak the contract.

**Handed back, and it is a design decision rather than a measurement:** the
interface form is now load-bearing. `scripts/breach/decider.gd` describes the
live seam as sending the observation packet and taking raw text back unmodified
— the FREE path. On this evidence that path is not ready: the contract would
have to be phrased so that no word in it can be read as a key, and that property
would need its own test, because two attempts have now failed it.

A constrained decode gives 240/240 today. It also changes what the arena is
measuring: a model that cannot structure output is being helped by the harness,
and the help is uniform across species, which is the acceptable kind. The
alternative — free-form text — currently measures prompt phrasing.

**Not authorized:** Section 0 remains a human call. This is evidence for it.

## Regime note

`SOLO_RESIDENCY` is not the co-resident pool. Records carry the label and are
not merged with pool records. For this gate the distinction is tolerable: verb
access is a property of the model and the contract, not of neighbour VRAM
pressure. Residency changes speed, and speed is not what this gate measures —
a verb that parses solo and fails in-pool would be a placement problem, which
is the sweep's job and now has a detector.

Probe wall time per species, solo: lfm25 42s, falconh1 121s, qwen35 192s,
danube2 86s, rwkv7 569s. No claim is made from these; they are recorded so the
next run knows what to budget.
