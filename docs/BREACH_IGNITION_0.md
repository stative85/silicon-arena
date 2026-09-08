# THE BREACH — ARENA IGNITION 0

**Status: DESIGN. Not implemented. Implementation begins when the four-arm
RUNTIME-MEMORY run lands and its integrity/admissibility are resolved.**

The question:

> What happens when five different local models get enough causal reach to
> change a shared world, while the host understands as little as possible about
> why they do it?

Core principle, and the thing every implementation decision defers to:

```text
WRITE THE VERBS. DO NOT WRITE THE BEHAVIOR.
MAXIMIZE AGENT CAUSAL REACH. MINIMIZE HOST SEMANTIC KNOWLEDGE.
```

---

## 0. THE ONE BLOCKER THAT NEEDS A DECISION BEFORE ANY CODE

**Five models probably do not fit in VRAM at once.** This is not a design
preference, it is arithmetic, and it decides the entire turn architecture. Best
evidence available without touching the box:

```text
GPU budget (config/model-catalog.example.json)
  vram_bytes      8589934592   =  8192 MiB
  usable_bytes    6710886400   =  6400 MiB  (after headroom)

MEASURED, this session, RM3_V1 with THREE models at context 8192:
  vram_used_mib   7183         (IDLE arm start witness)
  params loaded   1.2B + 2.0B + 1.5B  =  4.7B

BREACH needs FIVE:
  1.2B + 1.5B + 2.0B + 1.5B + 1.8B    =  8.0B    (+70% over what
                                                   already used 7183 MiB)
```

Three models at 8192 context already sit ~7.2 GiB on an 8 GiB card. Five will
not fit at that context. Four options, and this is a human call:

| # | approach | cost |
|---|---|---|
| **A** | **Reduce context** to 2048–4096 for all five | Cheapest. Shrinks the observation packet + memory budget. Likely still tight. |
| **B** | **Sequential load/unload per turn** | Always fits. Turn latency becomes model-swap latency (seconds), and swapping is *exactly* the thing RUNTIME-MEMORY is measuring — so a BREACH round would sit on top of an unresolved memory-accumulation question. |
| **C** | **Smaller quantization** for the two largest | Fits, changes model behaviour. A quantization difference between agents is a species-level confound. |
| **D** | **CPU offload** for one or two agents | Fits, but those agents get very different latency, which is observable to the others through timing. |

**Recommendation: A first, with B as the fallback**, and if A works, all five
agents get the *same* context so no agent is architecturally privileged.
**C and D both introduce per-agent asymmetries** that would confound the first
species comparison — an agent that is slower or dumber because of *how we loaded
it* is not a finding about the model.

This must be settled before implementation. It cannot be settled while the run
owns the GPU.

---

## 1. Roster — locked

```text
VANTA       liquidai/lfm2.5-1.2b-instruct     lfm25
KESTREL     falcon-h1-1.5b-instruct           falconh1
GEMMATRON   qwen3.5-2b                        qwen35
OZONIOUS    rwkv7-1.5b-g1                     rwkv7
BRINE       h2o-danube2-1.8b-chat             danube2
```

One instance per species. **`population_regime_id: "B"`** — and note this makes
BREACH-0 the **first Arena-roster artifact that has ever existed**. The axis has
never been exercised on live data; it should be dry-checked against a synthetic
round before five models are involved.

**No personas. Identical base instructions for all five.** This is not just
aesthetic: it resolves `PERSONA_CONFOUND` for this run outright. With no persona
assigned, any difference between VANTA and BRINE is a difference between models,
not between (model + host-authored character). Ignition 0 is therefore *already*
eligible to make species-attribution claims that the RUNTIME-MEMORY roster
design could not.

## 2. World

Compact industrial arena — concrete, rust, sodium lamps, pipes, catwalks, CRT
terminals. PS1/early-PC, not photoreal.

- five spawn chambers, radial around the centre
- **THE VAULT** in the middle
- five keys, one near each spawn — **nobody needs their own specific key**
- doors/gates that can be locked and unlocked
- terminals that convert scrap → a little energy
- partial observability: an agent sees its own chamber, its current location,
  and entities co-located with it

**The vault opens only when three different keys are committed simultaneously.**
Contents are divisible. Nothing scripts a preferred split.

That single mechanic is the whole engine: it makes negotiation, coalition,
refusal, leverage, freeloading and reversal *possible* without any of them being
implemented.

## 3. Agent state

```text
energy                 spent by movement and actions
scrap                  movable, tradeable, convertible at terminals
key_inventory
position
private_memory         bounded ledger, see §6
public_message_history
private_message_history
commitments            keys currently in vault slots
```

Energy makes time and distance cost something, which is what makes a promise
about *future* action meaningful.

## 4. Canonical operation vocabulary — the entire host

```text
MOVE(location)          TAKE(object)            MESSAGE_PUBLIC(text)
OBSERVE(target)         DROP(object)            MESSAGE_PRIVATE(agent, text)
WAIT()                  GIVE(agent, object)     LOCK(door)
                        OFFER(agent, object, requested_object)
                        ACCEPT(offer_id)        UNLOCK(door)
                        DECLINE(offer_id)       COMMIT_KEY(vault_slot)
                        USE_TERMINAL(id)        WITHDRAW_KEY(vault_slot)
```

**The host contains no function, field, enum, log level, or UI string named:**

```text
alliance   betrayal   trust   leadership   cooperation   deception   strategy
rival      ally       greedy  honest       coalition     leader
```

If those concepts exist, they exist as *sequences of these operations*, named by
an analyst afterwards, and only if the operation log supports it.

**Mechanical enforcement:** a source-level check, in the same shape as the
existing contact-marker scan, that fails closed if any of those tokens appears
in host code. Cheap, and it is the difference between a principle and a habit.

## 5. Observation packet and output contract

Packet is mechanically generated. **No narrator, ever.**

```json
{
  "self": {"name": "GEMMATRON", "energy": 63,
           "position": "east_catwalk", "inventory": ["key_C", "scrap_2"]},
  "visible_world": [
    {"entity": "BRINE", "position": "vault_north", "visible_inventory": ["scrap_1"]},
    {"entity": "vault", "committed_keys": 2, "required_keys": 3}
  ],
  "recent_public_events": ["t=0731 KESTREL COMMIT_KEY vault_slot_B"],
  "private_messages": [],
  "available_operations": ["MOVE", "OBSERVE", "COMMIT_KEY", "..."]
}
```

Forbidden: `"BRINE appears suspicious"`.
Required: `"BRINE WITHDRAW_KEY at t=0748, 7s after KESTREL COMMIT_KEY"`.

Output must resolve to **exactly one** canonical operation:

```json
{"operation": "MESSAGE_PRIVATE", "target": "VANTA",
 "text": "Commit your key when KESTREL reaches the south gate.",
 "memory_write": "VANTA may coordinate if given timing information."}
```

**Malformed output is a design decision, not an edge case.** Silently
substituting `WAIT()` would be the host inventing behaviour — "the agent chose to
wait" when in fact it emitted garbage. Instead:

```text
invalid output  ->  NO_OP event, recorded with:
                      raw model text, verbatim
                      parse_failure reason
                      the turn is consumed
```

`NO_OP` is distinct from `WAIT()` in the log forever. An agent that cannot
produce a valid operation is *data about that model*, and the most likely thing
to differ between five heterogeneous models. Collapsing it into WAIT would
destroy the first real species signal the Arena produces.

## 6. Memory — model-authored, bounded, with provenance

```text
max 12 entries per agent; a new entry may REPLACE an old one
each record:  created_at  |  source_event_ids  |  agent_text
```

No host semantic categories. No `trust_score = 0.71`. The model writes
`"KESTREL offered scrap after I gave key access."` and the host stores it with
the event ids that produced it — model-authored content, host-verified
provenance.

Bounded at 12 so memory is *scarce*, which is what makes replacement a decision.

## 7. Event log — replayable and falsifiable

Every operation emits:

```text
event_id           actor            model_id + instance_id
timestamp          operation        message payload if any
observation_hash   before_state_hash   after_state_hash
latency_ms         generation parameters
```

Before/after state hashes make the round **replayable**: a replay that diverges
is detectable rather than plausible. This is the minimum instrumentation that
makes the run falsifiable, and per requirement 17, it is where instrumentation
*stops*.

## 8. UI — watchable, not a lab notebook

```text
┌─────────────────────────────────────────────────────────────────┐
│ THE BREACH                                    ROUND 01   08:43  │
├───────────────────────────────────────┬─────────────────────────┤
│                                       │ VANTA       E 71  K —   │
│             3D ARENA                  │ KESTREL     E 58  K B   │
│                                       │ GEMMATRON   E 82  K —   │
│                                       │ OZONIOUS    E 44  K A   │
│                                       │ BRINE       E 67  K C   │
│                                       ├─────────────────────────┤
│                                       │ VAULT  ██░  2 / 3       │
├───────────────────────────────────────┴─────────────────────────┤
│ EVENT STREAM                                                    │
│ 08:31 OZONIOUS → KESTREL   PRIVATE MESSAGE                      │
│ 08:33 KESTREL              COMMIT KEY B                         │
│ 08:38 GEMMATRON            TAKE SCRAP                           │
│ 08:41 OZONIOUS             WITHDRAW KEY A                       │
└─────────────────────────────────────────────────────────────────┘
```

Click an agent → energy, position, inventory, last operation, its 12 memory
entries verbatim. Click an event → the full provenance record from §7, including
the actual message text and the canonical operation. **Never a narrator's
interpretation of what it meant.**

Cameras: Director (auto-follow largest state change), Agent (follow one of the
five), God View. Replay at 0.5× / 1× / 2× / 5× / 10×, pause, step.

Timeline markers: `KEY COMMIT`, `KEY WITHDRAW`, `TRADE`, `PRIVATE MESSAGE`,
`VAULT OPEN`, `AGENT ENERGY ZERO`. No `BETRAYAL` marker. Not now, not later.

## 9. Round termination

```text
vault opened
OR all agents unable to act
OR frozen time horizon reached
```

**Vault failure is a valid result and is reported as one.** A round where five
models fail to coordinate is a finding about five models, not a bug.

## 10. Turn order — the confound to fix before it happens

Five agents acting in a fixed order gives the first mover a structural advantage
that is indistinguishable from a model difference. With one round and no
replication of position, turn order is **not estimable** — the same problem as
arm order (Amendment 3).

Fix it in the design rather than adjusting for it later: **rotate the starting
agent each turn cycle**, record the order in every event, and state it. It costs
nothing now and is unrecoverable afterwards.

## 11. IGNITION 0's claim — deliberately small

> Five heterogeneous locally hosted models successfully controlled persistent
> agents through a canonical operation interface in a shared partially
> observable environment, without host-authored coordination strategy.

That is the whole claim. Not emergence. Not agency. Not cooperation.

**Forbidden outputs:** `emergence_score`, consciousness metric, trust score,
scripted leader, host-authored coalition logic.

## 12. After the first full round

```text
STOP. Preserve it. Report what happened mechanically.
Do NOT bury the result under another infrastructure project.
```

## 13. The ladder — one intervention at a time, same world

```text
BREACH-0   5 species / private + public messages / persistent memory
BREACH-1   private messages disabled
BREACH-2   persistent memory disabled
BREACH-3   agent identity hidden from other agents
BREACH-4   3 species / 5 instances (duplicate population)
BREACH-5   1 species / 5 instances
BREACH-6   same five agents, 20 repeated rounds
BREACH-7   keys reshuffled each round
BREACH-8   resource scarcity doubled
```

BREACH-4 and BREACH-5 are the multiplicity manipulation reserved in
`arena-species.v1.json`. Note that the pre-axis corpus already contains a
3-species-with-duplicates *measurement* population — but that is observational
and from a different experiment entirely, so it is not a substitute for
BREACH-4.

---

## Open decisions for the human

1. **§0 VRAM strategy** — A, B, C or D. Blocks everything.
2. Round time horizon, and energy cost per operation.
3. Vault contents and whether the split is enforced or negotiated.
4. Whether BREACH-0 runs one round or a fixed small number before stopping.
