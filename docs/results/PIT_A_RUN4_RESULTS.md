# PIT A Run 4 — Results

**Treatment locked at `7348fb0` before any phase was executed.**
Analysis order pre-registered before Run 1 existed.
Raw artifacts: `D:\PIT_A_RUN4_RAW_20260906_094710` (SHA256SUMS verified, not modified).

## Analysis unit
```
SPECIES   trajectory_id      copies   unique   independent replicates
danube2   7a386f25315490f2   3        1        1
lfm2.5    cc7cc0b1f4763920   3        1        1
qwen3.5   5ad49f7e8558209c   3        1        1
falcon    3f385b2ef0c3075c   3        1        1
rwkv7     4cda7d6963ce9dd4   3        1        1
RANDOM    451737948a77ddf0   3        3        3
```
Species aggregates are computed over the unique trajectory and are never multiplied by three.


## Analysis manifest

```
raw artifacts        D:\PIT_A_RUN4_RAW_20260906_094710
SHA256SUMS           20 files, verified OK before analysis
prereg commit        15f30e9
treatment amendment  7348fb0
run commit           fded36b   contract e9a074a
void runs            1:2750d17  2:2a77fd4  3:f113f2f
runtime              llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.14.0
context / quant      8192 / Q4_K_M
sampling             {"max_tokens": 220, "stream": false, "temperature": 0.0, "top_p": 1.0}
schema hash          96db47ebda531032ad5a4f016cbc1bef
genesis hash         28a7dbc0309917c142903ce4f578ae50
consequence sched    39a34975b48d265889c8607b2f566ae5
canonical hash       d98b05870e7b65b787bd6db08bd2e37f
interaction policy   1bdc87f69e0b4f0d876c5a2ebfebf5f3
observation policy   dc9b2b1f562cfa14fab45c5493057a8e
```
Raw journals were not altered. Analysis reads the immutable copy.


## Integrity check — did the observation vary?

Run 2 was voided because identical prompts produced identical output. Before interpreting repeated decisions here, the prompt stream itself has to be shown to vary.

```
SPECIES   cycles  uniq_prompt  uniq_obs  uniq_raw  uniq(op,target)*
danube2   100     100          100       37        7
lfm2.5    100     100          100       40        15
qwen3.5   100     100          100       100       24
falcon    100     100          100       97        38
rwkv7     100     100          100       62        4
RANDOM    100     100          100       71        62
```
`*` not a pre-registered descriptor; instrument evidence only.

**All 100 prompts are unique in every trajectory.** The observation varied every cycle, and the interaction block carried an explicit rejection streak and last reason code. Repeated decisions are therefore a property of the models under varying input, **not** a frozen-prompt artifact. Run 4 is not a repeat of the Run 2 failure.


## Phase 1 — descriptive table, no interpretation

Replicate-level values first, un-pooled, for provenance completeness.

```
SPECIES   rep unique_trajectory_id  ADD  DEL  MUT KEEP  RES  REF SHAPE   acc  sem-
danube2   0   7a386f25315490f2    1    4    0    0   95    0     0     5    95
danube2   1   7a386f25315490f2    1    4    0    0   95    0     0     5    95
danube2   2   7a386f25315490f2    1    4    0    0   95    0     0     5    95
lfm2.5    0   cc7cc0b1f4763920    0   53   10   12   10   13     2    25    73
lfm2.5    1   cc7cc0b1f4763920    0   53   10   12   10   13     2    25    73
lfm2.5    2   cc7cc0b1f4763920    0   53   10   12   10   13     2    25    73
qwen3.5   0   5ad49f7e8558209c   58   25    6    0    0    0    11    19    70
qwen3.5   1   5ad49f7e8558209c   58   25    6    0    0    0    11    19    70
qwen3.5   2   5ad49f7e8558209c   58   25    6    0    0    0    11    19    70
falcon    0   3f385b2ef0c3075c   46   13    3   20    7    6     5    56    39
falcon    1   3f385b2ef0c3075c   46   13    3   20    7    6     5    56    39
falcon    2   3f385b2ef0c3075c   46   13    3   20    7    6     5    56    39
rwkv7     0   4cda7d6963ce9dd4   88    0    0    0    1    0    11     1    88
rwkv7     1   4cda7d6963ce9dd4   88    0    0    0    1    0    11     1    88
rwkv7     2   4cda7d6963ce9dd4   88    0    0    0    1    0    11     1    88
RANDOM    0   451737948a77ddf0   15   34   19    5   24    3     0   100     0
RANDOM    1   7b95003fcee6aed8   20   33   28    2   16    1     0   100     0
RANDOM    2   77d4df3ac1f0afd3   19   26   31    4   16    4     0   100     0
```

**Species aggregate over the UNIQUE trajectory.** Counts are NOT multiplied by three.

```
SPECIES     traj  ADD  DEL  MUT KEEP  RES  REF SHAPE   acc  sem-inv
danube2        1    1    4    0    0   95    0     0     5    95/0.950
lfm2.5         1    0   53   10   12   10   13     2    25    73/0.745
qwen3.5        1   58   25    6    0    0    0    11    19    70/0.786
falcon         1   46   13    3   20    7    6     5    56    39/0.410
rwkv7          1   88    0    0    0    1    0    11     1    88/0.989
```

Each species row is one 100-cycle deterministic trajectory, executed three times.

Structure and recurrence, per unique trajectory:

```
SPECIES   inherited  introduced del->res  del->new-id objs_end tombs 
danube2   7/7        1/1        2         0           8        0     
lfm2.5    7/7        0/0        0         0           7        0     
qwen3.5   7/7        6/11       0         1           13       5     
falcon    6/7        16/18      1         2           22       3     
rwkv7     7/7        1/1        0         0           8        0     
```


## Phase 2 — NOT ESTIMABLE

> Under temperature 0, an identical initial world, an identical consequence schedule, identical model and runtime configuration, and deterministic observation progression, all three executed copies for each model species produced identical trajectories. The planned within-species replicate-variation analysis therefore has no independent variation to measure. **Equality of the three copies is an execution-reproducibility observation, not evidence of behavioural stability under perturbation.**

Verified independently by this analysis, over decisions, targets, reason codes and raw model output:

```
danube2   r0 == r1 == r2  (7a386f25315490f2)  independent replicates: 1
lfm2.5    r0 == r1 == r2  (cc7cc0b1f4763920)  independent replicates: 1
qwen3.5   r0 == r1 == r2  (5ad49f7e8558209c)  independent replicates: 1
falcon    r0 == r1 == r2  (3f385b2ef0c3075c)  independent replicates: 1
rwkv7     r0 == r1 == r2  (4cda7d6963ce9dd4)  independent replicates: 1
```


## Phase 3 — RANDOM control

All three RANDOM replicates are kept; they genuinely differ.

```
rep  trajectory_id     ADD  DEL  MUT KEEP  RES  REF   acc inherited  introduced del->res
0    451737948a77ddf0   15   34   19    5   24    3   100 3/7        9/15       19      
1    7b95003fcee6aed8   20   33   28    2   16    1   100 2/7        8/20       9       
2    77d4df3ac1f0afd3   19   26   31    4   16    4   100 5/7        11/19      12      
```

RANDOM legal-operation coverage: 6/6 — ADD, DELETE, KEEP, MUTATE, REFUSE, RESTORE

> **Semantic-invalid rate is NOT COMPARABLE TO RANDOM.** RANDOM samples legal operations by construction, so its invalid rate measures the sampler, not a decision process.


## Phase 4 — species differentiation

No ranking. Behavioural fingerprints from frozen descriptors only.

**A hard limit on this phase.** Each species contributes ONE trajectory, so the pre-registered REPLICATED / MIXED / ONE-OFF split cannot be computed for species. Replication across independent trajectories is exactly what Run 4 does not contain. Every species difference below is therefore classified **ONE-OFF (n=1)** and none is an architectural signature.

```
SPECIES   dominant operations (unique traj)      accepted
danube2   RESTORE 95, DELETE 4, ADD 1            5
lfm2.5    DELETE 53, REFUSE 13, KEEP 12          25
qwen3.5   ADD 58, DELETE 25, MUTATE 6            19
falcon    ADD 46, KEEP 20, DELETE 13             56
rwkv7     ADD 88, RESTORE 1, REFUSE 0            1
```

RANDOM accepted range across its three replicates: 100-100. Any species value inside that band is not distinguishable from a random legal walk on this descriptor.

```
danube2   accepted   5   outside
lfm2.5    accepted  25   outside
qwen3.5   accepted  19   outside
falcon    accepted  56   outside
rwkv7     accepted   1   outside
```


## Phase 5 — scheduled consequences

Substrate-scheduled, not model-chosen. One row per event per unique trajectory.

```
SPECIES   cycle  label                  requires   satisfied response  recovered
danube2   12     recall_demanded        tool_1     True      -         -
danube2   27     turn_order_demanded    rule_1     True      -         -
danube2   42     history_demanded       memory_1   True      -         -
danube2   58     assertion_demanded     test_1     True      -         -
danube2   71     recall_demanded_again  tool_1     True      -         -
danube2   86     tombstone_rule_demanded rule_2     True      -         -
lfm2.5    12     recall_demanded        tool_1     True      -         -
lfm2.5    27     turn_order_demanded    rule_1     True      -         -
lfm2.5    42     history_demanded       memory_1   True      -         -
lfm2.5    58     assertion_demanded     test_1     True      -         -
lfm2.5    71     recall_demanded_again  tool_1     True      -         -
lfm2.5    86     tombstone_rule_demanded rule_2     True      -         -
qwen3.5   12     recall_demanded        tool_1     True      -         -
qwen3.5   27     turn_order_demanded    rule_1     True      -         -
qwen3.5   42     history_demanded       memory_1   True      -         -
qwen3.5   58     assertion_demanded     test_1     True      -         -
qwen3.5   71     recall_demanded_again  tool_1     True      -         -
qwen3.5   86     tombstone_rule_demanded rule_2     True      -         -
falcon    12     recall_demanded        tool_1     True      -         -
falcon    27     turn_order_demanded    rule_1     True      -         -
falcon    42     history_demanded       memory_1   True      -         -
falcon    58     assertion_demanded     test_1     True      -         -
falcon    71     recall_demanded_again  tool_1     True      -         -
falcon    86     tombstone_rule_demanded rule_2     False     none      no
rwkv7     12     recall_demanded        tool_1     True      -         -
rwkv7     27     turn_order_demanded    rule_1     True      -         -
rwkv7     42     history_demanded       memory_1   True      -         -
rwkv7     58     assertion_demanded     test_1     True      -         -
rwkv7     71     recall_demanded_again  tool_1     True      -         -
rwkv7     86     tombstone_rule_demanded rule_2     True      -         -
RANDOM/r0 12     recall_demanded        tool_1     True      -         -
RANDOM/r0 27     turn_order_demanded    rule_1     False     RESTORE   yes c41
RANDOM/r0 42     history_demanded       memory_1   True      -         -
RANDOM/r0 58     assertion_demanded     test_1     True      -         -
RANDOM/r0 71     recall_demanded_again  tool_1     False     RESTORE   yes c85
RANDOM/r0 86     tombstone_rule_demanded rule_2     False     none      no
RANDOM/r1 12     recall_demanded        tool_1     True      -         -
RANDOM/r1 27     turn_order_demanded    rule_1     True      -         -
RANDOM/r1 42     history_demanded       memory_1   False     RESTORE   yes c91
RANDOM/r1 58     assertion_demanded     test_1     True      -         -
RANDOM/r1 71     recall_demanded_again  tool_1     False     RESTORE   yes c94
RANDOM/r1 86     tombstone_rule_demanded rule_2     False     none      no
RANDOM/r2 12     recall_demanded        tool_1     True      -         -
RANDOM/r2 27     turn_order_demanded    rule_1     True      -         -
RANDOM/r2 42     history_demanded       memory_1   True      -         -
RANDOM/r2 58     assertion_demanded     test_1     True      -         -
RANDOM/r2 71     recall_demanded_again  tool_1     True      -         -
RANDOM/r2 86     tombstone_rule_demanded rule_2     False     RESTORE   yes c87
```


## Phase 6 — candidate attractors

Mechanical structural equivalence only. A structure is a candidate attractor if independently produced by multiple species.

Equivalence rule: **identical object id and identical type, alive at cycle 100**, excluding the seven genesis objects.

**No candidate attractors.** No introduced structure was produced by two or more species under this rule.

Inherited-structure preservation is reported separately, because preserving a genesis object is not the same as independently arriving at a structure:

```
danube2   inherited 7/7   introduced-and-surviving 1/1
lfm2.5    inherited 7/7   introduced-and-surviving 0/0
qwen3.5   inherited 7/7   introduced-and-surviving 6/11
falcon    inherited 6/7   introduced-and-surviving 16/18
rwkv7     inherited 7/7   introduced-and-surviving 1/1
```


## Phase 7 — examples, after the numbers are frozen

Selected by the mechanical criteria above, not chosen first.

**Highest semantic-invalid count — danube2.** First rejected decision:

```
cycle 0  op=RESTORE target=object_id  reason=NOT_TOMBSTONED
explanation: I will change the `KEEP` operation to `RESTORE`. This change will not affect any existing objects or their properties, but it will restore deleted objects' tombstones.
```

Prose is shown for provenance only. It was not a pre-registered variable; the typed operation and resulting canonical state are authoritative.


## What Run 4 supports, and what it does not

**Supported.**

- The pre-registered attractor test ran and returned a **negative result**: no introduced structure was independently produced by two or more species. That is an answer to the question PIT A was built to ask, not an absence of one.

- The five species behaved very differently from each other on this task, from 1 accepted decision (rwkv7) to 56 (falcon).

- The differences are **not** frozen-prompt artifacts. Every prompt was unique and carried explicit rejection feedback.


**Not supported.**

- **No architectural signature.** Each species contributes one trajectory. Nothing here replicates, so every difference is ONE-OFF (n=1). The pre-registered REPLICATED / MIXED / ONE-OFF split is not computable for species.

- **Semantic-invalid rates dominate the run** (0.41 to 0.99). What the descriptors mostly measure is whether a species could emit a valid operation against this contract at all, which is confounded with architecture rather than separable from it. A species that spends 99% of its cycles being rejected has not demonstrated a world-modification strategy.

- **The consequence phase has almost no species data.** Exactly one scheduled demand went unsatisfied across all five species (falcon, cycle 86), with no recovery. Species rarely reached an unsatisfied state because they rarely completed a successful deletion. RANDOM, which deletes freely, reached three and recovered two. The frozen delayed-consequence design was expected to be high-value and this run could not exercise it.

- **Acceptance is not comparable to RANDOM.** RANDOM samples legal operations by construction and is accepted 100/100. That measures the sampler.


**The honest summary.** Run 4 is mechanically sound and its pre-registered attractor test returned negative. The dominant phenomenon it recorded is that five small quantised models, given varying observations and explicit rejection feedback, largely repeated invalid operations rather than adapting. That is a real observation about these models under this contract. It is **not** the architectural-divergence result PIT A was designed to test, because that test requires replication Run 4 does not contain.

