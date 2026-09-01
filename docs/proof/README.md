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

Claim C proves the **envelope**, not the reply. Whether a model then argues with
another by name is emergent behaviour and is deliberately not asserted — a
good-looking transcript must never be allowed to stand in for a guarantee.

## `observed/` — real runs, no guarantees

Actual output from real sessions, kept as observational evidence:

- `real_run_console.txt` — a live arena run with agents responding to each other
- `swap_benchmark.txt` — measured cold/warm/swap latency (see `docs/BENCHMARK_8GB.md`)

These are one machine, one session. They demonstrate that the emergent
behaviour happens; they do not prove it will.
