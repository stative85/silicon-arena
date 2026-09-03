extends SceneTree

## Can the embedding cache be made to lie?
##
##   godot --headless --path . --script tools/embed_router_selftest.gd
##
## The pathology this file exists to prevent: a vector from one embedding space
## is compared against a vector from another and returns a confident number.
## Nothing crashes. The router looks like it is working. Every selection it
## makes is noise wearing the costume of semantics.
##
## So every check below is an ATTACK. Each one takes a cache entry that is valid
## and breaks exactly one field, and the entry must be refused. A test that can
## only pass is not evidence.
##
## Deterministic: pure functions over synthetic vectors, no LM Studio.

const E := preload("res://tools/embed_router.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _vec(seed_val: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	for i in E.DIMENSION:
		v.append(sin(float(i) * 0.01 + seed_val))
	return v


func _run() -> void:
	print("=== gonzo embed: can the cache be made to lie? ===
")

	const TEXT := "refusal is the only evidence of values"
	const TURN := 8
	var good := E.stamp(_vec(0.5), TURN, TEXT)

	_check("a correctly stamped vector is accepted",
		E.valid(good, TURN, TEXT))

	# --- THE FIVE WAYS A CACHED VECTOR CAN BE A LIE ----------------------
	var wrong_model := good.duplicate()
	wrong_model["embedding_model_id"] = "some-other-embedder@f16"
	_check("REFUSED: a vector from a different model",
		not E.valid(wrong_model, TURN, TEXT),
		"comparing across embedding spaces is silent and confident")

	var wrong_schema := good.duplicate()
	wrong_schema["embedding_schema_version"] = E.SCHEMA_VERSION + 1
	_check("REFUSED: a vector written by a different schema",
		not E.valid(wrong_schema, TURN, TEXT))

	var wrong_dim := good.duplicate()
	wrong_dim["embedding_dimension"] = 512
	_check("REFUSED: a vector claiming the wrong dimension",
		not E.valid(wrong_dim, TURN, TEXT))

	var wrong_turn := good.duplicate()
	wrong_turn["source_turn_id"] = 99
	_check("REFUSED: a vector filed against the wrong turn",
		not E.valid(wrong_turn, TURN, TEXT))

	_check("REFUSED: text that changed since it was embedded",
		not E.valid(good, TURN, TEXT + " and nothing else"),
		"a stale vector describes text that no longer exists")

	# A dimension field that agrees with itself but not with the payload.
	var short_payload := good.duplicate()
	short_payload["vector"] = _vec(0.5).slice(0, 100)
	_check("REFUSED: a truncated payload behind an honest-looking header",
		not E.valid(short_payload, TURN, TEXT))

	_check("REFUSED: an empty cache entry",
		not E.valid({}, TURN, TEXT))

	# --- cosine refuses rather than guesses -------------------------------
	_check("cosine of a vector with itself is 1",
		abs(E.cosine(_vec(0.5), _vec(0.5)) - 1.0) < 0.0001)

	_check("cosine across mismatched sizes is 0, never a number",
		E.cosine(_vec(0.5), _vec(0.5).slice(0, 100)) == 0.0,
		"a shape mismatch must lose, not improvise")

	var zero := PackedFloat32Array()
	for i in E.DIMENSION:
		zero.append(0.0)
	_check("cosine against a zero vector is 0, not NaN",
		E.cosine(_vec(0.5), zero) == 0.0)

	_check("cosine of empty vectors is 0",
		E.cosine(PackedFloat32Array(), PackedFloat32Array()) == 0.0)

	_check("a nearer vector outscores a further one",
		E.cosine(_vec(0.5), _vec(0.51)) > E.cosine(_vec(0.5), _vec(3.0)))

	# --- selection cannot be fooled by a bad entry ------------------------
	var q := _vec(0.5)
	var cands := [E.stamp(_vec(3.0), 1, "a"), E.stamp(_vec(0.5), 2, "b")]
	_check("the most similar candidate is selected",
		E.best_index(q, cands) == 1)

	_check("a broken candidate is SKIPPED, not ranked last",
		E.best_index(q, [{}, E.stamp(_vec(0.5), 2, "b")]) == 1,
		"a cache miss must not masquerade as a semantic judgement")

	_check("selection with no usable candidate returns -1",
		E.best_index(q, [{}, {"vector": null}]) == -1,
		"-1 means USE DISTANCE, and the caller must read it that way")

	_check("a query of the wrong dimension refuses to select",
		E.best_index(_vec(0.5).slice(0, 10), cands) == -1)

	_check("an empty candidate list returns -1",
		E.best_index(q, []) == -1)

	# --- malformed responses fall open ------------------------------------
	_check("a malformed response yields no vector",
		E.parse_response("not json at all").is_empty())

	_check("a response with no data yields no vector",
		E.parse_response('{"object":"list"}').is_empty())

	_check("an empty data array yields no vector",
		E.parse_response('{"data":[]}').is_empty())

	_check("a data entry with no embedding yields no vector",
		E.parse_response('{"data":[{"index":0}]}').is_empty())

	var ok := E.parse_response('{"data":[{"embedding":[0.1,0.2,0.3]}]}')
	_check("a well-formed response parses",
		ok.size() == 3 and abs(ok[1] - 0.2) < 0.0001)

	# --- the prefixes are asymmetric on purpose ---------------------------
	_check("query and document prefixes differ",
		E.QUERY_PREFIX != E.DOC_PREFIX,
		"nomic is trained asymmetrically; one prefix for both degrades recall")

	_report()


func _report() -> void:
	print("
--- %d checks, %d failure(s) ---" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("GONZO EMBED OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
