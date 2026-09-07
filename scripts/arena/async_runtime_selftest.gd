extends SceneTree

## Gate 4: does the runtime guard void the right things, and only those?
##
##   godot --headless --path . --script scripts/arena/async_runtime_selftest.gd
##
## Two failure modes are checked with equal seriousness:
##   voiding too little   a transient eviction slipping through
##   voiding too much     an isolated SUSPECT killing a good replicate, which
##                        would resurrect n=1 after the health work proved it
##                        wrong
##
## Offline. No LM inference, no bridge.

const G := preload("res://scripts/arena/async_runtime_guard.gd")
const HL := preload("res://scripts/arena/bridge_health.gd")
const M := preload("res://scripts/arena/bridge_model.gd")

const EXPECTED := ["falcon-h1-1.5b-instruct", "h2o-danube2-1.8b-chat",
	"liquidai/lfm2.5-1.2b-instruct"]

var _checks := 0
var _failures: Array[String] = []
var _sections := ["suspect", "voiding", "transient", "envelope"]
var _done: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("   ok   %s" % name)
	else:
		_failures.append(name)
		print("   FAIL %s  %s" % [name, detail])


func _mk() -> AsyncRuntimeGuard:
	var g: AsyncRuntimeGuard = G.make("rep_0", EXPECTED)
	g.begin(EXPECTED, {"falcon-h1-1.5b-instruct": M.HOT})
	return g


func _receipt(verdict: String, resident: Array) -> Dictionary:
	return {"request_id": "q1", "model_id": EXPECTED[0],
		"health_verdict": verdict, "health_residual": 2.1,
		"resident_set": resident}


func _run() -> void:
	print("=== ASYNC-A runtime guard (Gate 4) ===\n")
	_suspect()
	_voiding()
	_transient()
	_envelope()
	_report()


## Voiding too much is a failure too.
func _suspect() -> void:
	print(" an isolated SUSPECT is context, NOT a void")
	var g := _mk()
	_check("   a clean replicate starts non-void", not g.is_void(),
		g.void_reason)
	g.on_receipt(_receipt(HL.SUSPECT, EXPECTED))
	_check("   one SUSPECT does not void", not g.is_void(), g.void_reason)
	_check("   but it IS recorded as runtime context",
		g.suspects.size() == 1,
		"suspects are real context and belong in the manifest")
	g.on_receipt(_receipt(HL.SUSPECT, EXPECTED))
	g.on_receipt(_receipt(HL.SUSPECT, EXPECTED))
	_check("   three isolated SUSPECT receipts still do not void",
		not g.is_void(),
		"the bridge decides when suspicion becomes actionable, not ASYNC-A")
	_check("   all three recorded", g.suspects.size() == 3)
	g.on_receipt(_receipt(HL.NORMAL, EXPECTED))
	_check("   NORMAL is neither recorded nor voiding",
		g.suspects.size() == 3 and not g.is_void())
	_done.append("suspect")


func _voiding() -> void:
	print("\n conditions that DO void")
	var g1 := _mk()
	g1.on_receipt(_receipt(HL.DEGRADED, EXPECTED))
	_check("   DEGRADED voids", g1.is_void(), g1.void_reason)

	var g2 := _mk()
	g2.on_receipt(_receipt(HL.CATASTROPHE, EXPECTED))
	_check("   CATASTROPHE voids", g2.is_void())

	var g3 := _mk()
	g3.on_model_state_changed(EXPECTED[0], M.HOT, M.WEDGED, "timeout")
	_check("   a WEDGED transition voids", g3.is_void(), g3.void_reason)

	var g4 := _mk()
	g4.on_model_state_changed(EXPECTED[0], M.HOT, M.EVICTED, "missing")
	_check("   an EVICTED transition voids", g4.is_void())

	var g5 := _mk()
	g5.on_recovery(EXPECTED[0], "reload", true)
	_check("   ANY bridge recovery voids, even a successful one", g5.is_void(),
		"a five-second reload is not an experimental treatment")

	var g6 := _mk()
	g6.on_residency_poll(["falcon-h1-1.5b-instruct"])
	_check("   a polled residency mismatch voids", g6.is_void())

	var g7: AsyncRuntimeGuard = G.make("rep_x", EXPECTED)
	g7.begin(["falcon-h1-1.5b-instruct"], {})
	_check("   starting outside the expected regime voids", g7.is_void())

	var g8 := _mk()
	g8.finish(["falcon-h1-1.5b-instruct"], {})
	_check("   ending outside the expected regime voids", g8.is_void())
	_done.append("voiding")


## THE TRANSIENT. Endpoints agree; the replicate is still contaminated.
func _transient() -> void:
	print("\n a transient eviction that endpoint hashes cannot see")
	var g := _mk()
	g.world_tick = 12
	# mid-replicate: evicted, then restored
	g.on_model_state_changed(EXPECTED[0], M.HOT, M.EVICTED, "vram")
	g.world_tick = 15
	g.on_recovery(EXPECTED[0], "reload", true)
	g.on_model_state_changed(EXPECTED[0], M.LOADING, M.HOT, "restored")
	g.finish(EXPECTED, {})

	_check("   SABOTAGE APPLIED: the model left and came back",
		g.runtime_events.size() >= 3, str(g.runtime_events.size()))
	_check("   the endpoint-only detector INCORRECTLY passes",
		g.endpoints_agree(),
		"start and end resident sets are identical -- this is why snapshots "
		+ "are insufficient")
	_check("   the event detector VOIDS", g.is_void(), g.void_reason)
	_check("   and the event history records when it happened",
		int((g.runtime_events[0] as Dictionary)["world_tick"]) == 12,
		"those ticks are in the data")
	_done.append("transient")


func _envelope() -> void:
	print("\n the replicate runtime envelope")
	var g := _mk()
	g.on_receipt(_receipt(HL.SUSPECT, EXPECTED))
	g.finish(EXPECTED, {"falcon-h1-1.5b-instruct": M.HOT})
	var e := g.envelope()
	for k in ["replicate_id", "expected_resident_hash", "start_resident_set",
			"start_resident_hash", "runtime_events", "suspects",
			"end_resident_set", "end_resident_hash", "void_reason"]:
		_check("   envelope carries %s" % k, e.has(k))
	_check("   a clean replicate has an empty void_reason",
		str(e["void_reason"]) == "")
	_check("   suspects survive into the manifest",
		(e["suspects"] as Array).size() == 1)
	_check("   the resident hash is order-independent",
		G.hash_set(["b", "a"]) == G.hash_set(["a", "b"]),
		"set identity must not depend on enumeration order")
	_check("   and distinguishes different sets",
		G.hash_set(["a", "b"]) != G.hash_set(["a", "c"]))
	_done.append("envelope")


func _report() -> void:
	for sec in _sections:
		if not _done.has(sec):
			_failures.append("section did not complete: " + sec)
			print("   FAIL section aborted: %s" % sec)
	print("\n--- %d checks, %d failure(s), %d/%d sections ---"
		% [_checks, _failures.size(), _done.size(), _sections.size()])
	if _failures.is_empty():
		print("ASYNC RUNTIME OK")
		quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		quit(1)
