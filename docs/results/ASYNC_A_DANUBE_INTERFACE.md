# Danube Interface Failure — mechanical categorization

Harvested from ASYNC-A Run 1 (VOID, `241d86c`) before retiring the model from
the experiment. **This is not a rescue attempt and changes nothing about the
void.** It is preserved because the pattern is specific enough to be worth a
future question.

## The failure is one thing, not a spread

387 shape failures across the three live arms, all with raw output preserved:

```
starts as a valid JSON object            387  (100%)
emits the correct key "target_id"        387  (100%)
packs MULTIPLE ids into the value        387  (100%)
backtick-wrapped inside the string       387  (100%)
unterminated / trailing comma            387  (100%)

output length   min 34, median 34, max 35 characters
```

Verbatim:

```
{\n  "target_id": "`r_08``,`r_12``,
{\n  "target_id": "`r_09``,`r_10``,
```

## What actually happens

danube2 understands the contract. It opens the object correctly and names the
right key. It then attempts to **enumerate several candidate resources inside
the single string field**, in a backticked list, and the response is truncated
at the `max_tokens = 24` ceiling mid-string — leaving unterminated JSON.

So the mechanical cause is **an over-long value hitting the token cap**, not an
inability to produce JSON.

## Honest limits on that reading

- A larger `max_tokens` might change the outcome. It is **not** being tried
  here: that would be per-model contract tuning inside a running experiment,
  which is exactly what turns ASYNC-A into a model-format study.
- The contract is demonstrably expressible. lfm2.5 and falcon produced **zero**
  failures across thousands of calls within the same 24-token budget. danube2
  chooses a verbose form the budget cannot hold.
- Whether this is a prompt-sensitivity, a decoding-length, or a
  concurrency-interaction effect is **not determined**. Three candidate causes,
  no evidence separating them.

## The unexplained gradient

Shape-failure rate rose across arms:

```
SERIAL     25.0%
NATURAL    31.7%
EQUALIZED  49.5%
```

The arms differ in cognition cadence, in-flight concurrency and calls per
agent, so this is **not interpreted**. It is recorded because a monotonic
interface-degradation gradient across timing regimes is strange, and because
the raw outputs are preserved if it ever becomes its own question:

> **Does producer interface compliance degrade under concurrency or cadence
> pressure?**

That would be a separate experiment with its own pre-registration, a control
for token budget, and no world attached. It is not ASYNC-A.

## Status

danube2 is **retired from ASYNC-A**. No prompt change, no cleanup pass, no
relaxed parsing, no enumerated-id schema, no per-model special case. Run 1
stays VOID.
