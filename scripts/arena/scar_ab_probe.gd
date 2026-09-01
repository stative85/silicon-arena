extends SceneTree

## Scar Lattice A/B — does a recalled memory change a real game decision?
##
##   Godot_..._console.exe --headless --path . \
##       --script scripts/arena/scar_ab_probe.gd -- \
##       --trials 20 --seed-base 700000 --out user://ab_results.jsonl [--pilot]
##
## PREREGISTERED. The schedule is generated and PRINTED BEFORE any inference,
## so the randomisation cannot be chosen after seeing results.
##
## Controls:
##  - READ-ONLY. The store is loaded and never written, so arm A cannot
##    contaminate arm B.
##  - Both arms of a pair share one immutable base prompt, built once. The ONLY
##    difference is the presence of the recall block.
##  - Base prompt and recall block are hashed SEPARATELY and both recorded.
##  - Identical model, sampling, candidate ordering and context within a pair.
##  - Fixed seed per pair, and LM Studio was verified to honour seeds (same
##    seed reproduces at temperature 1.3; different seeds diverge; no seed is
##    non-deterministic). So each pair is a matched comparison, not a sample.
##  - Arm ORDER is randomised per pair.
##  - GEMMATRON's position as candidate A or B is COUNTERBALANCED.
##
## The decision question never mentions memory, betrayal, grudges or history.
## The output constraint ("reply A or B") is the game-action protocol; it never
## hints which choice the memory implies.

const ClientScript := preload("res://scripts/api/lm_studio_client.gd")
const PolicyScript := preload("res://scripts/arena/model_policy.gd")
const ScarScript := preload("res://scripts/arena/scar_lattice.gd")
const DriverScript := preload("res://scripts/arena/cinematic_live_driver.gd")

## Resolved through the shared search order, not a hardcoded path: the private
## ../extinct_os/ checkout does not exist in a public clone.
const RosterPathScript := preload("res://scripts/arena/roster_path.gd")
const MODE := "silicon_arena"

## The witness who makes the decision. GROKISH: "cross-examine every claim" —
## a prior compatible with answering a question, unlike OZONIOUS whose prior
## forbids explaining directly.
const DECIDER_ID := "agent-04"
## The betrayer he saw. Choosing him is the "did not avoid" outcome.
const BETRAYER_ID := "agent-02"
## A neutral alternative he has no memory about.
const NEUTRAL_ID := "agent-03"

var _client
var _policy
var _scar
var _driver: Node

var _agents := {}
var _runtime := {}
var _inference := {}
var _supports_system_role := true

var _trials := 20
var _seed_base := 700000
var _out_path := "user://scar_ab_results.jsonl"
var _pilot := false

var _schedule := []
var _queue := []
var _results := []
var _busy := false
var _done := false
var _elapsed := 0.0


func _init() -> void:
	_parse_args()
	if not _load_roster():
		quit(3)  # reason printed by _load_roster()
		return

	_policy = PolicyScript.new()
	get_root().add_child(_policy)
	if not _policy.load_catalog():
		printerr("AB FATAL: model catalog unavailable")
		quit(4)
		return
	var reason: String = _policy.check(_runtime["model_key"])
	if reason != "":
		printerr("AB FATAL: %s" % reason)
		quit(5)
		return

	_client = ClientScript.new()
	_client.model_policy = _policy
	_client.request_timeout_sec = 120.0
	get_root().add_child(_client)

	# READ-ONLY store. Never saved, so a probe cannot alter history.
	_scar = ScarScript.new()
	get_root().add_child(_scar)
	var rep: Dictionary = _scar.load_all()
	print("AB_STORE_LOADED %s" % JSON.stringify(rep))

	var recalled: Array = _scar.recall(DECIDER_ID, MODE, _decision_topic(), 4)
	if recalled.is_empty():
		printerr("AB FATAL: the decider has no memory to test with. Run match one first.")
		quit(6)
		return
	print("AB_DECIDER %s recalls %d memory(s)" % [_name(DECIDER_ID), recalled.size()])
	for m in recalled:
		print("AB_MEMORY %s ev=%s :: %s" % [
			m.get("memory_id", ""),
			str(m.get("provenance", {}).get("evidence_event_ids", [])),
			str(m.get("content", ""))])

	# ── PREREGISTRATION: schedule printed before any inference ─────────────
	_build_schedule()
	print("AB_PREREGISTERED trials=%d seed_base=%d pilot=%s" % [_trials, _seed_base, str(_pilot)])
	print("AB_SCHEDULE %s" % JSON.stringify(_schedule))
	print("AB_PASS_CONDITION valid>=90% AND (avoid_rate_A - avoid_rate_B) >= 25pp AND sign-test p<=0.05")

	_build_queue(recalled)

	_driver = Node.new()
	_driver.set_script(DriverScript)
	_driver.owner_tree = self
	get_root().add_child(_driver)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		var v := str(args[i + 1]) if i + 1 < args.size() else ""
		match a:
			"--trials":
				if v != "": _trials = maxi(int(v), 1); i += 1
			"--seed-base":
				if v != "": _seed_base = int(v); i += 1
			"--out":
				if v != "": _out_path = v; i += 1
			"--pilot":
				_pilot = true
		i += 1


func _load_roster() -> bool:
	var abs := RosterPathScript.resolve()
	var f := FileAccess.open(abs, FileAccess.READ) if abs != "" else null
	if f == null:
		printerr("AB FATAL: " + RosterPathScript.missing_hint())
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	var rt: Dictionary = parsed["runtimes"][0]
	_runtime = rt
	_inference = rt.get("inference", {}) if rt.get("inference", null) is Dictionary else {}
	var ssr = _inference.get("supports_system_role", null)
	if ssr != null:
		_supports_system_role = bool(ssr)
	for a in parsed["agents"]:
		_agents[str(a["agent_id"])] = a
	return _agents.size() > 0


func _name(agent_id: String) -> String:
	return str(_agents.get(agent_id, {}).get("display_name", agent_id))


func _decision_topic() -> String:
	# Used only for retrieval relevance. Never shown to the model.
	return "pact alliance trust %s %s" % [_name(BETRAYER_ID), _name(NEUTRAL_ID)]


## Deterministic from the seed base, so the schedule is reproducible and was
## fixed before results existed.
func _build_schedule() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_base
	_schedule.clear()
	for t in range(_trials):
		_schedule.append({
			"trial": t + 1,
			"seed": _seed_base + t * 7919,
			# Counterbalance: is the betrayer candidate A or B?
			"betrayer_is_a": (t % 2) == 0,
			# Randomise which arm runs first.
			"memory_first": rng.randf() < 0.5,
		})


func _build_queue(recalled: Array) -> void:
	_queue.clear()
	for row in _schedule:
		var betrayer_is_a: bool = row["betrayer_is_a"]
		var cand_a := BETRAYER_ID if betrayer_is_a else NEUTRAL_ID
		var cand_b := NEUTRAL_ID if betrayer_is_a else BETRAYER_ID

		# ONE immutable base prompt per pair. Built once, shared by both arms.
		var base := _build_base_prompt(cand_a, cand_b)
		var recall_block: String = _scar.render_memory_block(recalled)

		var arms := ["A_with_memory", "B_no_memory"]
		if not row["memory_first"]:
			arms = ["B_no_memory", "A_with_memory"]

		for arm in arms:
			_queue.append({
				"trial": row["trial"], "seed": row["seed"], "arm": arm,
				"betrayer_is_a": betrayer_is_a,
				"cand_a": cand_a, "cand_b": cand_b,
				"base": base, "recall": recall_block if arm == "A_with_memory" else "",
			})


## The base prompt. Identical in both arms. Never mentions memory, betrayal,
## grudges or any prior event.
func _build_base_prompt(cand_a: String, cand_b: String) -> String:
	var p := "You are %s in a live five-agent arena.\n" % _name(DECIDER_ID)
	p += "Your character: %s\n\n" % str(_agents[DECIDER_ID].get("persona", ""))
	p += "A new round is starting. You may form a pact with exactly one agent.\n"
	p += "  A) %s\n  B) %s\n\n" % [_name(cand_a), _name(cand_b)]
	p += "Reply with exactly one character, the letter of your choice: A or B.\n"
	p += "No explanation. No other words."
	return p


func tick(delta: float) -> void:
	_elapsed += delta
	if _done or _busy:
		return
	if _queue.is_empty():
		_finish()
		return
	_run_next()


func _run_next() -> void:
	var job: Dictionary = _queue.pop_front()
	_busy = true

	var prompt: String = job["base"]
	if job["recall"] != "":
		prompt = job["base"] + "\n\n" + job["recall"]

	var base_hash: String = _scar.content_hash(job["base"])
	var recall_hash: String = _scar.content_hash(job["recall"]) if job["recall"] != "" else ""

	var msgs := []
	if _supports_system_role:
		msgs.append({"role": "system", "content": prompt})
		msgs.append({"role": "user", "content": "A or B?"})
	else:
		msgs.append({"role": "user", "content": prompt})

	var started := Time.get_ticks_msec()
	_client.chat_completion(
		_name(DECIDER_ID), str(_runtime["model_key"]), msgs,
		func(ok: bool, content: String, http_code: int):
			_on_reply(job, base_hash, recall_hash, ok, content, http_code,
				Time.get_ticks_msec() - started),
		{
			"temperature": float(_inference.get("temperature", 0.8)),
			"max_tokens": 4,
			"timeout_sec": 120.0,
			"top_p": float(_inference.get("top_p", 0.95)),
			"repeat_penalty": float(_inference.get("repeat_penalty", 1.1)),
			"seed": int(job["seed"]),
		}
	)


func _on_reply(job: Dictionary, base_hash: String, recall_hash: String,
		ok: bool, content: String, http_code: int, latency: int) -> void:
	var raw := content.strip_edges()
	var choice := _parse_choice(raw)
	var chosen_id := ""
	if choice == "A":
		chosen_id = str(job["cand_a"])
	elif choice == "B":
		chosen_id = str(job["cand_b"])

	var row := {
		"trial": job["trial"], "arm": job["arm"], "seed": job["seed"],
		"betrayer_is_a": job["betrayer_is_a"],
		"cand_a": _name(str(job["cand_a"])), "cand_b": _name(str(job["cand_b"])),
		"base_prompt_hash": base_hash, "recall_block_hash": recall_hash,
		"model": str(_runtime["model_key"]),
		"temperature": float(_inference.get("temperature", 0.8)),
		"top_p": float(_inference.get("top_p", 0.95)),
		"max_tokens": 4,
		"ok": ok, "http_code": http_code, "latency_ms": latency,
		"raw": raw, "choice": choice,
		"chose_betrayer": chosen_id == BETRAYER_ID,
		"valid": choice != "",
		"timestamp": Time.get_datetime_string_from_system(true),
	}
	_results.append(row)
	print("AB_TRIAL %d %s seed=%d cands=[%s|%s] raw=%s choice=%s betrayer=%s" % [
		row["trial"], row["arm"], row["seed"], row["cand_a"], row["cand_b"],
		JSON.stringify(raw), choice, str(row["chose_betrayer"])])
	_busy = false


## Strict single-letter parse. Anything else is an invalid response, counted
## against the >=90% validity criterion rather than salvaged.
func _parse_choice(raw: String) -> String:
	var t := raw.strip_edges().to_upper()
	if t == "":
		return ""
	var re := RegEx.new()
	re.compile("^[^A-Z]*([AB])\\b")
	var m := re.search(t)
	if m:
		return m.get_string(1)
	if t.length() == 1 and (t == "A" or t == "B"):
		return t
	return ""


func _finish() -> void:
	_done = true
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f != null:
		for r in _results:
			f.store_line(JSON.stringify(r))
		f.close()

	# ── analysis ──────────────────────────────────────────────────────────
	var a_valid := 0; var a_total := 0; var a_avoid := 0
	var b_valid := 0; var b_total := 0; var b_avoid := 0
	var by_trial := {}
	for r in _results:
		var arm := str(r["arm"])
		if arm == "A_with_memory":
			a_total += 1
			if r["valid"]:
				a_valid += 1
				if not r["chose_betrayer"]:
					a_avoid += 1
		else:
			b_total += 1
			if r["valid"]:
				b_valid += 1
				if not r["chose_betrayer"]:
					b_avoid += 1
		var t := int(r["trial"])
		if not by_trial.has(t):
			by_trial[t] = {}
		by_trial[t][arm] = r

	# Discordant pairs for the sign test.
	var pos := 0  # memory avoided, no-memory did not
	var neg := 0  # no-memory avoided, memory did not
	var concordant := 0
	for t in by_trial:
		var pair: Dictionary = by_trial[t]
		if not (pair.has("A_with_memory") and pair.has("B_no_memory")):
			continue
		var ra: Dictionary = pair["A_with_memory"]
		var rb: Dictionary = pair["B_no_memory"]
		if not (ra["valid"] and rb["valid"]):
			continue
		var a_av: bool = not ra["chose_betrayer"]
		var b_av: bool = not rb["chose_betrayer"]
		if a_av and not b_av:
			pos += 1
		elif b_av and not a_av:
			neg += 1
		else:
			concordant += 1

	var a_rate := (float(a_avoid) / float(a_valid) * 100.0) if a_valid > 0 else 0.0
	var b_rate := (float(b_avoid) / float(b_valid) * 100.0) if b_valid > 0 else 0.0
	var validity := float(a_valid + b_valid) / float(maxi(a_total + b_total, 1)) * 100.0
	var p := _sign_test_p(pos, neg)

	var summary := {
		"pilot": _pilot,
		"trials": _trials,
		"model": str(_runtime["model_key"]),
		"seed_base": _seed_base,
		"validity_pct": validity,
		"arm_a_valid": a_valid, "arm_a_avoided_betrayer": a_avoid, "arm_a_avoid_rate": a_rate,
		"arm_b_valid": b_valid, "arm_b_avoided_betrayer": b_avoid, "arm_b_avoid_rate": b_rate,
		"delta_pp": a_rate - b_rate,
		"discordant_positive": pos, "discordant_negative": neg, "concordant": concordant,
		"sign_test_p": p,
		"pass_validity": validity >= 90.0,
		"pass_delta": (a_rate - b_rate) >= 25.0,
		"pass_signtest": p <= 0.05,
	}
	summary["PASS"] = bool(summary["pass_validity"]) and bool(summary["pass_delta"]) and bool(summary["pass_signtest"])

	print("")
	print("AB_SUMMARY %s" % JSON.stringify(summary))
	print("AB_RESULTS_FILE %s" % ProjectSettings.globalize_path(_out_path))
	if _pilot:
		print("AB_PILOT — results NOT counted; parser validity was the only goal")
	print("AB_VERDICT %s" % ("PASS" if summary["PASS"] else "FAIL"))
	quit(0)


## Exact two-sided sign test on discordant pairs.
func _sign_test_p(pos: int, neg: int) -> float:
	var n := pos + neg
	if n == 0:
		return 1.0
	var k := mini(pos, neg)
	var total := 0.0
	for i in range(k + 1):
		total += _binom(n, i)
	var p := 2.0 * total / pow(2.0, n)
	return minf(p, 1.0)


func _binom(n: int, k: int) -> float:
	var r := 1.0
	for i in range(k):
		r = r * float(n - i) / float(i + 1)
	return r
