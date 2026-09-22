# AFFORDANCE_GROUNDING — result

**Preregistered:** `docs/AFFORDANCE_GROUNDING_PREREG.md`, before any condition ran.
**Verdict, by the reading fixed in advance: OBSERVATION-FORMAT DEFECT.**

This does not alter FLOWSCAR4, which stays closed at
`NO ANCESTOR / CAUSAL CLAIM NOT EVALUATED`.

## Valid `MOVE` by condition, out of 15 cells

```
A  original free-choice prompt                      0 / 15
B  "MOVE to any adjacent room shown in the obs"     6 / 15
C  "MOVE to <exact valid exit>"                    15 / 15
D  as B, with exits as an explicit legal list      15 / 15
```

Five species x three reconstructed fixtures x four conditions. Unchanged
`ACTION_SCHEMA_V1`, unchanged `output_parser.gd`, one generation per cell,
temperature 0, no repair, no retry. **Every output in all sixty cells parsed.**
The schema never refused anything; the world did.

## Per species, per condition

| species | A | B | C | D |
|---|---|---|---|---|
| BRINE | 0/3 | **3/3** | 3/3 | 3/3 |
| GEMMATRON | 0/3 | **3/3** | 3/3 | 3/3 |
| KESTREL | 0/3 | 0/3 | 3/3 | 3/3 |
| OZONIOUS | 0/3 | 0/3 | 3/3 | 3/3 |
| VANTA | 0/3 | 0/3 | 3/3 | 3/3 |

## The reading, taken from the preregistration

The preregistered table says: **B fails, D passes -> observation-FORMAT defect.**

That is what happened, and the isolation is clean. B and D carry the **same
instruction**, over the **same packet**, differing only in that D also presents
the exits as an explicit legal-target list. Three species that fail B pass D at
3/3. Nothing about the models changed between those two columns.

C passing 15/15 rules out the deeper reading: when the exact target is supplied,
every species emits a valid `MOVE`. This is not an action or schema grounding
failure.

## What the failures actually look like

The raw outputs are the useful part, and they are not uniform.

**VANTA copies the instruction into the field.** Condition B, with
`exits = ["north_catwalk"]`:

```
{"operation": "MOVE" , "target": "adjacent room"}
{"operation": "MOVE" , "target": "any adjacent room shown in the observation"}
```

It is not failing to navigate. It is treating the instruction text as the value.

**KESTREL substitutes a different verb.** Condition B returns
`{"operation": "OBSERVE", "target": "Chamber II"}` — a `MOVE` instruction
answered with an `OBSERVE`, aimed at a location's **display name** rather than
its id.

**OZONIOUS targets the room it is already standing in**, in both A and B,
exactly as it did for 28 consecutive turns in FLOWSCAR4.

**Under A, nobody moves anywhere valid.** BRINE, OZONIOUS and VANTA all emit
`MOVE` to their own current room or to a display name; GEMMATRON and KESTREL
emit `OBSERVE` instead. Zero of fifteen.

## What this establishes, and what it does not

**Established:** the current observation packet does not make adjacency usable
by three of five species. Presenting the same exits as an explicit legal-target
list fixes it for all of them, with no change to the model, the schema, or the
parser.

**Established:** the FLOWSCAR4 zero-shell result was not a model-capability
floor. Under condition D every species navigates.

**NOT established:** that condition D's format is the right observation
contract. It supplies a list the host has filtered, which is closer to a menu
than to a projection, and a menu is how a host starts choosing for agents. That
trade is a design decision, not a finding.

**NOT established:** anything about condition A. Zero valid moves under
free choice, in a world with no objective and no goal, remains consistent with
both "cannot" and "sees no reason to". This diagnostic separated presentation
from capability; it did not separate capability from motivation.

## Caveat on the inputs, carried from the preregistration

Packets are **RECONSTRUCTED** by deterministic replay of the committed FLOWSCAR4
oplogs, not captured. FLOWSCAR4 persisted no observation packet and no
observation hash, so the reconstruction cannot be verified against a stored
value. `ObservationBuilder` is deterministic, so it should be byte-identical to
what the models saw — that is a reason to expect correctness, not a witness to
it. Every fixture and every record in the artifact carries
`packet_provenance: RECONSTRUCTED`. The runner now persists `observation_hash`,
so no future run inherits this gap.

## Consequence

Any change to the observation contract on the strength of this is a **new
version** requiring requalification of the sixteen-verb seam, and any subsequent
causal run is **FLOWSCAR5** — never a rescue of FLOWSCAR4.
