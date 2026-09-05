extends RefCounted
class_name PitGate

## PIT A refuses to start unless the regime is exactly what was frozen.
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9.
##
## FAIL CLOSED, NOT A WARNING. Six weeks from now LM Studio updates something,
## the pit runs, and 500 generations later someone discovers RWKV ran on one
## runtime while Danube's historical trajectory ran on another. That is not a
## caveat to add to a results table; it is two experiments wearing one name. So
## a mismatch STOPS the run and nothing is recorded.
##
## The instrument is part of the regime. `response_format: json_schema` is what
## made all five species emit typed operations at all -- three of five fail
## without it, in three different ways -- so the schema is pinned by hash and a
## changed schema is a changed experiment.
##
## Provenance records the EFFECTIVE configuration reported by the runtime, never
## the requested one, because those are the same right up until they are not.

const EXPECTED_RUNTIME := "llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.14.0"
const EXPECTED_CONTEXT := 8192
const EXPECTED_QUANT := "Q4_K_M"
const CONSTRAINT_MODE := "common_all_species"
const RESPONSE_FORMAT := "json_schema"

## The five, frozen. Resolved from the runtime's own inventory at 15f30e9, never
## inferred from filenames.
const SPECIES := {
	"h2o-danube2-1.8b-chat": "llama",
	"lfm2.5-1.2b-instruct@q4_k_m": "lfm2",
	"qwen3.5-2b": "qwen35",
	"falcon-h1-1.5b-instruct": "falcon-h1",
	"rwkv7-1.5b-g1": "rwkv7",
}

## The typed-operation schema every species emits through. Hashed rather than
## trusted, so a later edit cannot silently become "the same experiment".
const SCHEMA_TEXT := '{"operation":["ADD","DELETE","MUTATE","KEEP","RESTORE","REFUSE"],"target":"string","explanation":"string"}'


static func schema_hash() -> String:
	return SCHEMA_TEXT.sha256_text()


## Returns {"ok": bool, "failures": Array}. The runner MUST stop on ok == false.
##
## `observed` carries what the runtime actually reported: runtime id, per-model
## effective context, quantisation and architecture.
static func check(observed: Dictionary) -> Dictionary:
	var bad: Array = []

	if str(observed.get("runtime", "")) != EXPECTED_RUNTIME:
		bad.append("runtime is %s, expected %s"
			% [str(observed.get("runtime", "<none>")), EXPECTED_RUNTIME])

	if str(observed.get("response_format", "")) != RESPONSE_FORMAT:
		bad.append("response_format is %s, expected %s"
			% [str(observed.get("response_format", "<none>")), RESPONSE_FORMAT])
	if str(observed.get("schema_hash", "")) != schema_hash():
		bad.append("schema hash mismatch: the typed-operation contract changed")
	if str(observed.get("constraint_mode", "")) != CONSTRAINT_MODE:
		bad.append("constraint mode is not common across species")

	var models: Dictionary = observed.get("models", {})
	for id in SPECIES:
		if not models.has(id):
			bad.append("species missing from the runtime: %s" % id)
			continue
		var m: Dictionary = models[id]
		if int(m.get("context", -1)) != EXPECTED_CONTEXT:
			bad.append("%s effective context is %s, expected %d"
				% [id, str(m.get("context", "?")), EXPECTED_CONTEXT])
		if str(m.get("quant", "")) != EXPECTED_QUANT:
			bad.append("%s quantisation is %s, expected %s"
				% [id, str(m.get("quant", "?")), EXPECTED_QUANT])
		if str(m.get("arch", "")) != str(SPECIES[id]):
			bad.append("%s architecture is %s, expected %s"
				% [id, str(m.get("arch", "?")), str(SPECIES[id])])

	# Five distinct architectures is the experiment. Two species reporting the
	# same arch would mean the roster silently collapsed into cousins.
	var seen := {}
	for id in models:
		if SPECIES.has(id):
			seen[str((models[id] as Dictionary).get("arch", ""))] = true
	if models.size() > 0 and seen.size() != SPECIES.size():
		bad.append("expected %d distinct architectures, runtime reports %d"
			% [SPECIES.size(), seen.size()])

	return {"ok": bad.is_empty(), "failures": bad}


## What goes into provenance for every PIT A run.
static func provenance(observed: Dictionary) -> Dictionary:
	return {
		"runtime": str(observed.get("runtime", "")),
		"response_format": RESPONSE_FORMAT,
		"schema_hash": schema_hash(),
		"constraint_mode": CONSTRAINT_MODE,
		"context": EXPECTED_CONTEXT,
		"quant": EXPECTED_QUANT,
		"models": observed.get("models", {}),
	}
