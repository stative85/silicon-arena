extends RefCounted
class_name RecoveryAction

## Verified model recovery. The primitive for RECOVERY-COUPLING.
##
## THE CONTRACT IS DELIBERATELY STUPID. No model judgement, no semantic
## interpretation, no "probably recovered":
##
##     RECOVERY_VALID iff
##         pre_target_present
##     and unload_target_absent
##     and reload_target_present
##     and neighbor_residency_preserved
##     and post_target_liveness
##     and epoch_incremented_exactly_once
##
## THE INCARNATION BOUNDARY. `residency_epoch` advances ONLY after a confirmed
## present -> absent -> present transition. It does NOT advance when a command is
## issued, and it does NOT advance on a "recovery requested" receipt. A receipt
## claiming success cannot satisfy this witness, which is the whole point:
## anything less is RECOVERY_NOT_VERIFIED.
##
## ABSENCE IS VERIFIED IMMEDIATELY AFTER THE BLOCKING UNLOAD, never by waiting
## for a periodic poll to happen to catch it. If LM Studio can unload and reload
## faster than a poll interval, a polling witness succeeds only by winning a race
## against its own runtime. This project has already paid tuition for that class
## of engineering comedy.
##
## RESIDENCY IS CHECKED AS AN EXACT SET, NOT AS PRESENCE. `lms load` on an
## already-resident model creates a SECOND INSTANCE ("qwen3.5-2b:2") rather than
## being idempotent. A presence-only check calls that restored while the pool
## silently carries a duplicate eating ~1.3 GB of VRAM and changing contention
## for every model in it. This is the same "exact pool, not at-least" rule
## arm_baseline.py already enforces, and it is enforced here too.
##
## NO SABOTAGE AFFORDANCES EXIST IN THIS FILE. The self-test injects a different
## command runner rather than setting a "suppress" flag, so the production path
## has no switch that could ever be left on.

const LMS := "C:/Users/cleve/.lmstudio/bin/lms.exe"
const MODELS_ENDPOINT := "http://127.0.0.1:1234/api/v0/models"
const CONTEXT := "8192"

const VALID := "RECOVERY_VALID"
const NOT_VERIFIED := "RECOVERY_NOT_VERIFIED"

var residency_epoch: int = 0


## The real command runner. Blocking, so absence can be checked the instant the
## unload returns. Returns the process exit code.
static func real_runner(args: Array) -> int:
	var out: Array = []
	var argv := PackedStringArray()
	for a in args:
		argv.append(str(a))
	return OS.execute(LMS, argv, out, true, false)


## Read the resident set from the server. No inference; a state read only.
## Returns [] on failure, which the caller treats as a failed verification
## rather than as an empty pool.
static func resident_set(http: HTTPRequest) -> Array:
	var got: Array = []
	if http.request(MODELS_ENDPOINT) != OK:
		return got
	var res: Array = await http.request_completed
	if int(res[1]) != 200:
		return got
	var parsed = JSON.parse_string(
		(res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return got
	for entry in (parsed as Dictionary).get("data", []):
		var e: Dictionary = entry
		if str(e.get("state", "not-loaded")) != "not-loaded":
			got.append(str(e.get("id", "")))
	return got


## One mechanical liveness probe: does the target answer at all after reload?
## Deliberately trivial -- 1 token, no schema, no judgement of the content.
static func liveness(http: HTTPRequest, model_id: String) -> bool:
	var body := JSON.stringify({
		"model": model_id, "max_tokens": 1, "temperature": 0.0,
		"messages": [{"role": "user", "content": "ok"}],
	})
	var err := http.request("http://127.0.0.1:1234/v1/chat/completions",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		return false
	var res: Array = await http.request_completed
	return int(res[1]) == 200


## Perform and VERIFY one recovery.
##
## `runner` is injected so the self-test can suppress the unload, suppress the
## reload, or evict a neighbour without this file containing any such switch.
func perform(http: HTTPRequest, target: String, neighbours: Array,
		runner: Callable = Callable()) -> Dictionary:
	var run := runner if runner.is_valid() \
		else Callable(RecoveryAction, "real_runner")
	var old_epoch := residency_epoch
	var w := {
		"target": target, "neighbours": neighbours,
		"recovery_attempted": false,
		"pre_target_present": false, "pre_neighbours_present": false,
		"unload_verified": false, "unload_neighbours_present": false,
		"reload_verified": false, "neighbor_set_preserved": false,
		"post_liveness_verified": false,
		"old_epoch": old_epoch, "new_epoch": old_epoch,
		"verdict": NOT_VERIFIED, "reason": "",
		"t_unload_start_ms": 0, "t_unload_done_ms": 0,
		"t_reload_start_ms": 0, "t_reload_done_ms": 0,
	}

	# PRE
	var pre := await resident_set(http)
	w["pre_target_present"] = pre.has(target)
	var expected: Array = neighbours.duplicate()
	expected.append(target)
	w["pre_neighbours_present"] = _exact(pre, expected)
	if not bool(w["pre_target_present"]) or not bool(w["pre_neighbours_present"]):
		w["reason"] = "pre-state wrong: resident=%s" % str(pre)
		return w

	# UNLOAD, blocking, then verify absence IMMEDIATELY.
	w["recovery_attempted"] = true
	w["t_unload_start_ms"] = Time.get_ticks_msec()
	run.call(["unload", target])
	w["t_unload_done_ms"] = Time.get_ticks_msec()
	var mid := await resident_set(http)
	w["unload_verified"] = not mid.has(target)
	w["unload_neighbours_present"] = _exact(mid, neighbours)
	var mid_n: bool = bool(w["unload_neighbours_present"])
	if not w["unload_verified"]:
		w["reason"] = "target never became absent; resident=%s" % str(mid)
		# The target never left, so there is nothing to reload. Issuing a load
		# here would create a duplicate instance rather than restoring anything.
		return w

	# RELOAD
	w["t_reload_start_ms"] = Time.get_ticks_msec()
	run.call(["load", target, "--gpu=max", "--context-length=" + CONTEXT, "-y"])
	w["t_reload_done_ms"] = Time.get_ticks_msec()
	var post := await resident_set(http)
	w["reload_verified"] = post.has(target)
	var post_n := _exact(post, expected)
	w["neighbor_set_preserved"] = mid_n and post_n
	w["post_resident_set"] = post
	if not w["reload_verified"]:
		w["reason"] = "target absent after reload; resident=%s" % str(post)
		return w
	if not w["neighbor_set_preserved"]:
		w["reason"] = "neighbour residency changed; resident=%s" % str(post)
		return w

	# POST liveness
	w["post_liveness_verified"] = await liveness(http, target)
	if not w["post_liveness_verified"]:
		w["reason"] = "target resident but did not answer a liveness probe"
		return w

	# The incarnation boundary: present -> absent -> present, all confirmed.
	residency_epoch = old_epoch + 1
	w["new_epoch"] = residency_epoch
	w["verdict"] = VALID
	return w


## Exact set equality, order-insensitive. An EXTRA resident model fails this,
## which is the whole reason it exists.
static func _exact(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for x in want:
		if not got.has(str(x)):
			return false
	return true


## Load only if not already resident. `lms load` is NOT idempotent -- it spawns
## a second instance -- so every restore path must check first.
static func ensure_loaded(http: HTTPRequest, model_id: String) -> bool:
	var now := await resident_set(http)
	if now.has(model_id):
		return true
	real_runner(["load", model_id, "--gpu=max",
		"--context-length=" + CONTEXT, "-y"])
	var after := await resident_set(http)
	return after.has(model_id)


## The contract, evaluated from a witness. Kept separate so a witness can be
## re-checked from a stored artifact long after the run.
static func is_valid(w: Dictionary) -> bool:
	return bool(w.get("pre_target_present", false)) \
		and bool(w.get("unload_verified", false)) \
		and bool(w.get("reload_verified", false)) \
		and bool(w.get("neighbor_set_preserved", false)) \
		and bool(w.get("post_liveness_verified", false)) \
		and int(w.get("new_epoch", 0)) == int(w.get("old_epoch", 0)) + 1
