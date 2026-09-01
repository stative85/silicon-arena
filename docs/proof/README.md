# Proof artifacts

Two kinds of evidence live here, deliberately separated.

## `latest/` — deterministic proof

Regenerate with:

```
godot --headless --path . --script tools/prove.gd
```

| claim | what is proven | deterministic? |
|---|---|---|
| **A** resource law | an oversized model is refused *before any HTTP request leaves the process* — the client returns MODEL_REJECTED without a server involved | yes |
| **B** heterogeneous execution | three or more distinct permitted models are installed and legal to run | needs LM Studio; SKIPPED with a note when offline |
| **C** cross-agent context | a later agent's payload mechanically contains earlier speakers by name and their utterances | yes |
| **D** VRAM residency | two permitted models whose combined estimate fits the budget do not evict each other: alternating between them costs the same order as repeating one | needs LM Studio; SKIPPED with a note when offline |

Claim D is the one that overturns an assumption this project was built on.
"One model is resident, so every model change costs a cold load" is only true
when the models do not fit together; when they do, a heterogeneous roster costs
nothing extra. It is measured on the machine running it rather than asserted,
and it fails loudly if the pair turns out to evict each other.

Claim C proves the **envelope**, not the reply. Whether a model then argues with
another by name is emergent behaviour and is deliberately not asserted — a
good-looking transcript must never be allowed to stand in for a guarantee.

## `observed/` — real runs, no guarantees

Actual output from real sessions, kept as observational evidence:

- `real_run_console.txt` — a live arena run with agents responding to each other
- `swap_benchmark.txt` — measured cold/warm/swap latency (see `docs/BENCHMARK_8GB.md`)

These are one machine, one session. They demonstrate that the emergent
behaviour happens; they do not prove it will.
