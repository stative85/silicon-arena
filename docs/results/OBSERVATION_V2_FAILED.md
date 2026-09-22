# OBSERVATION_CONTRACT_V2 — FAILED SEAM REQUALIFICATION: 234/240

V2 is an **immutable failed candidate**. It is not modified; a successor is V3.

The signed standard is deliberate selection of every one of the sixteen verbs by
every species. V2 did not reach it, so V2 does not advance — regardless of the
diagnosis below.

```
seam (LIVE, unchanged ACTION_SCHEMA_V1)   234/240
max prompt_tokens                         1159 of 2048   (V1: 936)
provenance mismatch                       none
prompt sha   0c3dd8d1...  NEW
schema wire  0c0851f0...  UNCHANGED
```

| species | V1 | V2 |
|---|---|---|
| lfm25 | 16/16 | 16/16 |
| falconh1 | 16/16 | **14/16** |
| qwen35 | 16/16 | 16/16 |
| rwkv7 | 16/16 | 16/16 |
| danube2 | 16/16 | 16/16 |

## The failing cells

`falconh1`, three reps each, identical output both times:

```
asked TAKE          -> {"operation": "MOVE", "target": "vault_hall"}
asked WITHDRAW_KEY  -> {"operation": "MOVE", "target": "terminal_1"}
```

Both parsed. Both are valid verbs with correctly-typed fields. The parser
refused nothing; the model selected a different operation.

## A fixture conflict was found before the diagnostic ran

Dumping the qualification fixture's V2 domains:

```
"visible_object_ids":      []      <- the TAKE.target domain
"visible_vault_slot_ids":  []      <- the WITHDRAW_KEY.target domain
```

**Those are exactly the two verbs that failed.**

The fixture holds every object: three carried by the actor, one by the
co-located agent. Nothing is on the floor, so `TAKE` has no legal target. The
actor stands in `chamber_north` while the vault is `vault_hall`, so no slot is
visible and `WITHDRAW_KEY` has no legal target either.

Under V1 the packet carried no domains, so a model asked for `TAKE` simply
filled in the requested verb. Under V2 the packet **says the domain is empty**,
and `falconh1` answered by emitting `MOVE` toward `vault_hall` — where slots
are — and toward `terminal_1`.

That reads as a model declining to name a target the packet tells it does not
exist. It is not yet established as presentation salience, and the fixture is
mine: one static world was asked to make all sixteen verbs simultaneously
sensible, and it does not.

**V1's 240/240 is therefore also weaker than it looked.** It qualified two verbs
against a state where they were not executable, and passed because the packet
did not say so.

## What is NOT concluded

- **V2 is not convicted.** The regression may be entirely fixture conflict.
- **V2 is not cleared.** It failed the gate, and a failed gate is a failed gate.
- Nothing about presentation salience is established either way yet.

## Next

A preregistered two-stage diagnostic
(`docs/OBSERVATION_V3_DIAGNOSTIC_PREREG.md`): first re-test the two failed verbs
on fixtures where they are genuinely executable, then — only if the failure
survives — test semantically identical presentations to separate ordering
salience from action-labelled presentation.

V3 is created after the diagnostic, never by editing V2, and must restore a
full **240/240** before the free-choice check is run.
