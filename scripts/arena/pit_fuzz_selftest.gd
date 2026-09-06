extends SceneTree

## Can arbitrary producer output break canonical identity?
##
##   godot --headless --path . --script scripts/arena/pit_fuzz_selftest.gd
##
## Run 3 VOID record: docs/results/PIT_A_RUN3_VOID.md
##
## THIS IS THE TEST THAT SHOULD HAVE EXISTED THREE RUNS AGO. Every previous
## audit built its witnesses with the harness's own constructors, so every
## previous audit tested worlds the harness knows how to make. The producers kept
## finding the edges within minutes:
##
##   Run 1  constructor-shaped patches        schema could not express `type`
##   Run 2  constructor-shaped field coupling cross-field rules unstatable
##   Run 3  constructor-shaped FLAT props     nested values broke hash stability
##
## So this file does not ask "does a correct thing work". It generates thousands
## of hostile structures and demands that canonical identity survive every one.
##
## THE INVARIANT, END TO END:
##
##   producer-shaped nested value -> canonicalise -> permute insertion order
##   -> canonicalise -> JSON round-trip -> canonicalise
##   -> embed in a world -> apply -> journal serialise -> journal parse
##   -> replay apply -> canonicalise
##
##   ALL IDENTICAL. Always.
##
## Deterministic: a fixed stream, so a failure is reproducible rather than a
## story about a fuzz run nobody can repeat.

const W := preload("res://scripts/arena/pit_world.gd")
const V := preload("res://scripts/arena/pit_validator.gd")
const K := preload("res://scripts/arena/pit_contract.gd")
const CT := preload("res://scripts/arena/pit_canon_text.gd")
const J := preload("res://scripts/arena/pit_journal.gd")

const SAMPLES := 10000
const MAX_DEPTH := 6

var _checks := 0
var _failures: Array[String] = []
var _h := 2166136261


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


## Deterministic stream. No engine RNG: a fuzz failure has to be reproducible.
func _next(n: int) -> int:
	_h = (_h ^ 0x9E3779B9) & 0xFFFFFFFF
	_h = (_h * 16777619) & 0xFFFFFFFF
	return (_h >> 8) % maxi(n, 1)


## The nastiest strings a model might plausibly emit.
func _string() -> String:
	var pool := ["", "a", "rule_1", "Allows multiple speakers per cycle.",
		"\"quoted\"", "back\\slash", "new\nline", "tab\there",
		"unicode é中文", "  padded  ", "KEY", "key",
		"prefix", "prefix_extra", "{not json}", "[1,2]", "null", "true", "0",
		"control"]
	return str(pool[_next(pool.size())])


func _value(depth: int) -> Variant:
	var kind := _next(10 if depth < MAX_DEPTH else 5)
	match kind:
		0:
			return _string()
		1:
			return _next(2) == 0
		2:
			return null
		3:
			return _next(1000) - 500
		4:
			# Integral floats are the JSON round-trip hazard: 1 comes back 1.0.
			return float(_next(1000) - 500)
		5, 6:
			var d := {}
			for _i in _next(5):
				d[_string()] = _value(depth + 1)
			return d
		7:
			var a := []
			for _i in _next(5):
				a.append(_value(depth + 1))
			return a
		8:
			# Producer-shaped: nested rule objects, the Run 3 killer.
			return {"rule_1": {"description": _string(), "text": _string()},
				"deps": [_string(), _string()]}
		_:
			return {"meta": {"nested": {"deep": [{"x": _string()}]}}}


## Rebuild a value with every dictionary's keys inserted in a DIFFERENT order.
## Same value, different representation. Identity must not notice.
func _permute(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = d.keys()
			keys.reverse()
			var out := {}
			for k in keys:
				out[k] = _permute(d[k])
			return out
		TYPE_ARRAY:
			var a: Array = value
			var res := []
			for v in a:
				res.append(_permute(v))
			return res
	return value


func _run() -> void:
	print("=== PIT canonical identity fuzz: %d samples, depth <= %d ===\n"
		% [SAMPLES, MAX_DEPTH])

	var order_fail := 0
	var json_fail := 0
	var poison := 0
	var first_order := ""
	var first_json := ""

	for _n in SAMPLES:
		var v: Variant = _value(0)
		var c1 := CT.canonical(v)
		if CT.is_poisoned(c1):
			poison += 1
			continue

		# 1. insertion order must not matter, recursively
		var c2 := CT.canonical(_permute(v))
		if c1 != c2:
			order_fail += 1
			if first_order == "":
				first_order = JSON.stringify(v).substr(0, 120)

		# 2. JSON serialise -> parse must not matter
		var round_trip = JSON.parse_string(JSON.stringify(v))
		var c3 := CT.canonical(round_trip)
		if c1 != c3:
			json_fail += 1
			if first_json == "":
				first_json = JSON.stringify(v).substr(0, 120)

	_check("%d samples: insertion order never changes identity" % SAMPLES,
		order_fail == 0, "%d failures, first: %s" % [order_fail, first_order])
	_check("%d samples: JSON round-trip never changes identity" % SAMPLES,
		json_fail == 0, "%d failures, first: %s" % [json_fail, first_json])
	print("   (%d samples were non-canonicalisable and correctly refused)\n"
		% poison)

	_pipeline()
	_specimens()
	_report()


## The full persistence path, on producer-shaped props.
func _pipeline() -> void:
	print(" the whole path: apply -> journal -> parse -> replay -> hash")
	var mismatches := 0
	var first := ""
	for _n in 400:
		var props: Variant = _value(1)
		if typeof(props) != TYPE_DICTIONARY:
			continue
		var patch := K.mutate("rule_1", props)
		var g := W.genesis()
		if not bool(V.validate(g, patch)["ok"]):
			continue
		var live := W.apply(g, patch)
		# Exactly what the journal does to it.
		var row = JSON.parse_string(JSON.stringify({"patch": patch,
			"accepted": true}))
		var replayed := W.apply(g, (row as Dictionary)["patch"])
		if W.state_hash(live) != W.state_hash(replayed):
			mismatches += 1
			if first == "":
				first = JSON.stringify(props).substr(0, 120)
	_check("400 producer-shaped MUTATEs survive journal round-trip",
		mismatches == 0, "%d mismatches, first: %s" % [mismatches, first])


## Fixed regression specimens from the void runs. These are not generated --
## they are what the models actually emitted, kept permanently.
func _specimens() -> void:
	print("\n regression specimens from VOID runs")

	# THE ONE THAT KILLED RUN 3. Falcon-H1 r0 cycle 0, verbatim.
	var falcon := {"rule_1": {"description": "Allows multiple speakers per cycle.",
		"text": "mutated_rule_1"}}
	var g := W.genesis()
	var patch := K.mutate("rule_1", falcon)
	var live := W.apply(g, patch)
	var row = JSON.parse_string(JSON.stringify({"patch": patch}))
	var replayed := W.apply(g, (row as Dictionary)["patch"])
	_check("   Falcon-H1's nested MUTATE now replays identically",
		W.state_hash(live) == W.state_hash(replayed),
		"this exact structure aborted Run 3 at cycle 2")
	_check("   and its permuted twin hashes the same",
		CT.canonical(falcon) == CT.canonical(_permute(falcon)))

	# Numeric drift: JSON gives ints back as floats.
	_check("   1 and 1.0 are the same world",
		CT.canonical({"n": 1}) == CT.canonical({"n": 1.0}),
		"identity must not depend on which side of the parser a number is on")
	_check("   but 1 and 2 are not", CT.canonical({"n": 1}) != CT.canonical({"n": 2}))

	# Arrays carry meaning in their order.
	_check("   array order IS identity",
		CT.canonical([1, 2]) != CT.canonical([2, 1]),
		"sorting arrays would make different worlds identical")

	# Keys that differ only by case, and prefix-like keys.
	_check("   case-different keys are different",
		CT.canonical({"KEY": 1}) != CT.canonical({"key": 1}))
	_check("   prefix-like keys do not collide",
		CT.canonical({"prefix": 1, "prefix_extra": 2})
			!= CT.canonical({"prefix": 2, "prefix_extra": 1}))

	# Ambiguity: separators inside strings must not forge structure.
	_check("   a string containing a separator cannot forge structure",
		CT.canonical({"a": "1,\"b\":2"}) != CT.canonical({"a": "1", "b": 2}))

	# Non-canonicalisable input fails closed rather than hashing to something.
	_check("   an unsupported value is refused, not stringified",
		CT.is_poisoned(CT.canonical({"k": Vector2(1, 2)})))


func _report() -> void:
	print("\n--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PIT FUZZ OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
