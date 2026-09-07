extends SceneTree

## RECOVERY-COUPLING step 2: prove the recovery tooth before the monster.
##
##   godot --headless --path . --script tools/recovery_tooth_selftest.gd
##
## Four cases. The first must PASS. The other three must FAIL, each for its own
## mechanical reason:
##
##   real recovery        -> RECOVERY_VALID
##   suppressed recovery  -> target never becomes absent, epoch does not advance
##   missing reload       -> reload_verified false
##   neighbour eviction   -> neighbor_set_preserved false
##
## Sabotage is injected as a different COMMAND RUNNER, not as a flag on the
## production path. `recovery_action.gd` contains no suppress switch that could
## be left on by accident.
##
## THIS IS NOT THE EXPERIMENT. It exists so the causal experiment is not also
## the first place the recovery primitive gets tested. The pool is restored at
## the end regardless of outcome.

const RA := preload("res://scripts/arena/recovery_action.gd")

const POOL := ["liquidai/lfm2.5-1.2b-instruct", "qwen3.5-2b",
	"falcon-h1-1.5b-instruct"]
const TARGET := "qwen3.5-2b"

var _http: HTTPRequest
var _fail := 0
var _checks := 0
var _done := {}


func _init() -> void:
	_run.call_deferred()


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s %s" % [label, detail])


func _run() -> void:
	print("=== RECOVERY tooth self-test ===")
	print("Real recovery must PASS. Three sabotages must FAIL.\n")

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame

	var start := await RA.resident_set(_http)
	print("resident at start: %s" % str(start))
	for m in POOL:
		if not start.has(m):
			print("FAIL pool incomplete; cannot run the tooth")
			quit(1)
			return
	var neighbours: Array = []
	for m in POOL:
		if m != TARGET:
			neighbours.append(m)

	# ---------------------------------------------------------------- case 1
	print("\n[1] REAL RECOVERY -- must be VALID")
	var a := RA.new()
	var w1: Dictionary = await a.perform(_http, TARGET, neighbours)
	_print_witness(w1)
	_ok("verdict VALID", str(w1["verdict"]) == RA.VALID, str(w1["reason"]))
	_ok("epoch advanced exactly once",
		int(w1["new_epoch"]) == int(w1["old_epoch"]) + 1)
	_ok("is_valid() agrees", RA.is_valid(w1))
	_done["real"] = true

	# ---------------------------------------------------------------- case 2
	print("\n[2] SUPPRESSED RECOVERY -- commands dropped entirely")
	var b := RA.new()
	b.residency_epoch = 17
	var w2: Dictionary = await b.perform(_http, TARGET, neighbours,
		func(_args): return 0)          # accepts, does nothing, returns success
	_print_witness(w2)
	_ok("verdict NOT_VERIFIED", str(w2["verdict"]) == RA.NOT_VERIFIED)
	_ok("target never became absent", not bool(w2["unload_verified"]))
	_ok("epoch did NOT advance", int(w2["new_epoch"]) == 17,
		"epoch moved to %d" % int(w2["new_epoch"]))
	_ok("is_valid() rejects", not RA.is_valid(w2))
	_ok("a success exit code did not satisfy the witness", true)
	_done["suppressed"] = true

	# ---------------------------------------------------------------- case 3
	print("\n[3] MISSING RELOAD -- unload runs, reload dropped")
	var c := RA.new()
	var w3: Dictionary = await c.perform(_http, TARGET, neighbours,
		func(args):
			if str(args[0]) == "load":
				return 0                # swallow the reload
			return RA.real_runner(args))
	_print_witness(w3)
	_ok("verdict NOT_VERIFIED", str(w3["verdict"]) == RA.NOT_VERIFIED)
	_ok("unload_verified true", bool(w3["unload_verified"]))
	_ok("reload_verified false", not bool(w3["reload_verified"]))
	_ok("epoch did NOT advance",
		int(w3["new_epoch"]) == int(w3["old_epoch"]))
	_ok("is_valid() rejects", not RA.is_valid(w3))
	_done["missing_reload"] = true
	print("  restoring %s after the missing-reload case" % TARGET)
	RA.real_runner(["load", TARGET, "--gpu=max", "--context-length=8192", "-y"])
	await _settle()

	# ---------------------------------------------------------------- case 4
	print("\n[4] NEIGHBOUR EVICTION -- recovery succeeds, a neighbour is lost")
	var victim := str(neighbours[0])
	var d := RA.new()
	var w4: Dictionary = await d.perform(_http, TARGET, neighbours,
		func(args):
			var rc := RA.real_runner(args)
			if str(args[0]) == "load":
				RA.real_runner(["unload", victim])   # collateral damage
			return rc)
	_print_witness(w4)
	_ok("verdict NOT_VERIFIED", str(w4["verdict"]) == RA.NOT_VERIFIED)
	_ok("reload_verified true", bool(w4["reload_verified"]))
	_ok("neighbor_set_preserved false", not bool(w4["neighbor_set_preserved"]))
	_ok("epoch did NOT advance",
		int(w4["new_epoch"]) == int(w4["old_epoch"]))
	_ok("is_valid() rejects", not RA.is_valid(w4))
	_done["neighbour_eviction"] = true

	# ------------------------------------------------------------- restore
	print("\n[RESTORE] returning the pool to the frozen three")
	# ensure_loaded checks residency FIRST. `lms load` on an already-resident
	# model spawns a SECOND INSTANCE. An earlier version of this loop did exactly
	# that and left 5 instances at 7,656 of 8,151 MiB VRAM, while a
	# presence-only check cheerfully reported "pool restored".
	for m in POOL:
		await RA.ensure_loaded(_http, m)
	await _settle()
	var final := await RA.resident_set(_http)
	print("  resident: %s" % str(final))
	_ok("pool restored EXACTLY, no extra instances",
		_same_set(final, POOL), str(final))
	print("\n[SUMMARY]")
	var missing: Array = []
	for k in ["real", "suppressed", "missing_reload", "neighbour_eviction"]:
		if not _done.has(k):
			missing.append(k)
	print("  checks %d, failures %d" % [_checks, _fail])
	if not missing.is_empty():
		print("  INCOMPLETE CASES: %s" % str(missing))
		print("\nTOOTH RED")
		quit(1)
		return
	if _fail > 0:
		print("\nTOOTH RED")
		quit(1)
		return
	print("\nTOOTH GREEN -- the recovery primitive may be wired to the scheduler")
	quit(0)


func _same_set(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for x in want:
		if not got.has(str(x)):
			return false
	return true


func _settle() -> void:
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until:
		await process_frame


func _print_witness(w: Dictionary) -> void:
	print("    attempted=%s pre=%s unload=%s reload=%s neigh=%s live=%s"
		% [str(w["recovery_attempted"]), str(w["pre_target_present"]),
		   str(w["unload_verified"]), str(w["reload_verified"]),
		   str(w["neighbor_set_preserved"]),
		   str(w["post_liveness_verified"])])
	print("    epoch %d -> %d   verdict %s   %s"
		% [int(w["old_epoch"]), int(w["new_epoch"]), str(w["verdict"]),
		   str(w["reason"])])
