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
## RESIDENCY IS A MULTISET, NOT A SET. LM Studio proved it: {qwen, falcon} and
## {qwen, qwen, falcon} are the same mathematical set and radically different
## runtime states. The invariant is therefore an exact COUNT MAP --
## qwen=1, lfm2.5=1, falcon=1, total=3 -- and an extra instance of any model
## fails the witness even though every expected model is present.
##
## RESIDENCY IS CHECKED AS AN EXACT COUNT MAP, NOT AS PRESENCE. `lms load` on an
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


## PRODUCER CONTRACT, qualified empirically against this runtime rather than
## inferred from a pattern. Observed directly on 2026-09-07:
##
##     lms load qwen3.5-2b   (already resident)
##     -> 'To use the model in the API/SDK, use the identifier "qwen3.5-2b:2".'
##     -> /api/v0/models then lists BOTH "qwen3.5-2b" and "qwen3.5-2b:2"
##
## So a trailing ":<digits>" denotes instance multiplicity FOR THIS PRODUCER.
##
## THE SUFFIX IS ONLY STRIPPED WHEN THE RESULT IS A KNOWN POOL MEMBER. A blind
## parser would one day meet a legitimate model whose canonical id ends in ":2"
## and silently merge it into a base that does not exist -- Law 5 murdered by a
## naming convention. An unrecognised numeric-colon id is left intact so the
## gate reports it as foreign rather than quietly absorbing it.
static func base_id(instance_id: String, known: Array = []) -> String:
	if known.has(instance_id):
		return instance_id
	var c := instance_id.rfind(":")
	if c < 0:
		return instance_id
	var suffix := instance_id.substr(c + 1)
	if suffix.is_empty() or not suffix.is_valid_int():
		return instance_id
	var candidate := instance_id.substr(0, c)
	if known.is_empty() or known.has(candidate):
		return candidate
	return instance_id      # numeric colon, unknown base: NOT collapsed


## Residency as a COUNT MAP: base model id -> number of live instances.
static func residency_counts(http: HTTPRequest,
		known: Array = []) -> Dictionary:
	var ids := await resident_set(http)
	var counts := {}
	for i in ids:
		var b := base_id(str(i), known)
		counts[b] = int(counts.get(b, 0)) + 1
	return counts


## Exact count-map equality. An EXTRA instance fails this; so does a missing one,
## a replacement, and an unexpected model.
static func counts_match(got: Dictionary, want: Dictionary) -> bool:
	if got.size() != want.size():
		return false
	for k in want:
		if int(got.get(k, 0)) != int(want[k]):
			return false
	return true


## Expected count map for a pool: exactly one instance of each.
static func expect_one_each(models: Array) -> Dictionary:
	var want := {}
	for m in models:
		want[str(m)] = 1
	return want


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
	var pre := await residency_counts(http)
	var expected: Array = neighbours.duplicate()
	expected.append(target)
	var want_full := expect_one_each(expected)
	var want_absent := expect_one_each(neighbours)
	w["pre_counts"] = pre
	w["pre_target_present"] = int(pre.get(target, 0)) == 1
	w["pre_neighbours_present"] = counts_match(pre, want_full)
	if not bool(w["pre_target_present"]) or not bool(w["pre_neighbours_present"]):
		w["reason"] = "pre-state wrong: resident=%s" % str(pre)
		return w

	# UNLOAD, blocking, then verify absence IMMEDIATELY.
	w["recovery_attempted"] = true
	w["t_unload_start_ms"] = Time.get_ticks_msec()
	run.call(["unload", target])
	w["t_unload_done_ms"] = Time.get_ticks_msec()
	var mid := await residency_counts(http)
	w["mid_counts"] = mid
	w["unload_verified"] = int(mid.get(target, 0)) == 0
	w["unload_neighbours_present"] = counts_match(mid, want_absent)
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
	var post := await residency_counts(http)
	w["post_counts"] = post
	w["reload_verified"] = int(post.get(target, 0)) == 1
	var post_n := counts_match(post, want_full)
	w["neighbor_set_preserved"] = mid_n and post_n
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


## Load only if not already resident. `lms load` is NOT idempotent -- it spawns
## a second instance -- so every restore path must check first.
static func ensure_loaded(http: HTTPRequest, model_id: String) -> bool:
	var now := await residency_counts(http)
	var have := int(now.get(model_id, 0))
	if have == 1:
		return true
	if have > 1:
		# AT-LEAST-ONE IS NOT THE INVARIANT. Loading again would add a third
		# instance; returning true would report a corrupted pool as restored.
		# The caller's exact count-map check is the backstop, but this must not
		# lie to it.
		return false
	real_runner(["load", model_id, "--gpu=max",
		"--context-length=" + CONTEXT, "-y"])
	var after := await residency_counts(http)
	return int(after.get(model_id, 0)) == 1


## The contract, evaluated from a witness. Kept separate so a witness can be
## re-checked from a stored artifact long after the run.
static func is_valid(w: Dictionary) -> bool:
	return bool(w.get("pre_target_present", false)) \
		and bool(w.get("unload_verified", false)) \
		and bool(w.get("reload_verified", false)) \
		and bool(w.get("neighbor_set_preserved", false)) \
		and bool(w.get("post_liveness_verified", false)) \
		and int(w.get("new_epoch", 0)) == int(w.get("old_epoch", 0)) + 1
