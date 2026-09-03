extends SceneTree

## Does the CONTENT of a recalled scar change the reply, or does any block of
## old text do the same job?
##
##   godot --headless --path . --script tools/source_probe.gd -- --mode a
##   godot --headless --path . --script tools/source_probe.gd -- --mode b
##   godot --headless --path . --script tools/source_probe.gd -- --mode b --temp 0
##
## Pre-registered in docs/EXPERIMENT_SOURCE.md at 1d3e62d, before this file was
## written and before any generation was run.
##
## MP1 showed real memory tying a sham at 80.6% once the verbatim clause came
## off, so absolute conversion is abandoned as a quantity. This measures
## something a sham cannot satisfy by construction: whether the reply carries
## material traceable to ONE specific source and not the other.
##
## THE DESIGN IS A CROSSOVER. Every reply is scored against BOTH the real scar
## and the sham scar, so each reply carries its own control -- the same text,
## the same verbosity, scored against a source it never saw. The no-memory
## branch supplies the false-positive floor in the same batch, and the
## estimator subtracts it. That subtraction is not decoration: measured offline
## before freezing, at a threshold of one distinctive term a reply that never
## saw scar A takes it up 31.9% of the time and prefers it over an unrelated
## scar by +6.9 points with nothing injected at all. That is the artifact that
## inverted the embedding result from +30.4 to -10.9.
##
## The arithmetic lives in tools/source_measure.gd so the self-test exercises
## the real thing. THIS HARNESS WILL NOT PRINT ARM RATES BEFORE ITS TARGET, and
## there is no flag that changes that.

const G := preload("res://scripts/arena/gonzo_recall.gd")
const LM := preload("res://scripts/arena/live_match.gd")
const M := preload("res://tools/source_measure.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const MAX_TOKENS := 110

## Frozen in the pre-registration. MP1 ran on this model; changing it would
## make the two incomparable.
const MODEL := "h2o-danube3-4b-chat"

## Sham matching: excerpt length band, in characters.
const SHAM_LEN_BAND := 40

const TARGET_A := 60    ## MP2-A, the metric validation gate
const TARGET_B := 240   ## MP2-B, the verdict
const GATE_A := 25.0    ## ceiling uptake must clear this or the measure is blind

## MP2-A ran and its ceiling arm never rose: instructed to build on the memory,
## the model copied a six-word run from it ZERO times in 60 opportunities and
## its uptake matched the uninstructed arm at 0.50 against 0.52. The ledger says
## why -- nine rejections agree that instructions do not survive contact with
## these models -- so A2 replaces the instruction with a transformation the
## model will actually perform: restate the excerpt in its own words.
##
## A paraphrase of the source is source-specific use by construction. If the
## measure cannot see one, it is blind for real.
const PARAPHRASE_MIN_RATIO := 0.5   ## a paraphrase shorter than this is not one
const PARAPHRASE_MAX_DISCARD := 25.0  ## above this the ceiling is void, not failed
const SCRAMBLE_BOUND := 5.0
const SCRAMBLE_SEED := 20260903
const SCRAMBLE_REPS := 200

const RESULTS_A := "user://source_probe_a.json"
const RESULTS_A2 := "user://source_probe_a2.json"
const RESULTS_B := "user://source_probe_b.json"
const RESULTS_B_DET := "user://source_probe_b_det.json"

var _mode := "b"
var _temp := 0.8
var _runs := 8
var _skip := 0

## Walk the corpus and count, generating nothing.
##
## The pre-registration quotes a 0.7% discard rate and 100% sham availability,
## and those numbers came from a separate Python implementation of the same
## rules. Two implementations of one rule set is exactly the duplicated truth
## this project keeps getting bitten by, so this mode exists to check that the
## harness that actually runs agrees with the document that constrains it.
var _dry := false
var _dry_opportunities := 0
var _rows: Array[Dictionary] = []
var _http: HTTPRequest
var _results := RESULTS_B
var _target := TARGET_B
var _arms: PackedStringArray = ["N", "S", "R"]

var _sham_pool: Array = []
var _sham_cursor := 0
var _discarded_empty := 0
var _discarded_no_sham := 0

## A run whose every generation failed used to walk every transcript, record
## nothing, and exit 0 with a tidy report of zero. That is the silent-failure
## shape tools/lint_exits.py exists for -- the clip recorder printing CLIP SAVED
## with no file. It is caught in two places now: consecutively, so a dead
## endpoint stops the run in seconds instead of an hour, and at the end, so an
## empty result can never be mistaken for a completed one.
const MAX_CONSECUTIVE_FAILURES := 12
var _gen_failures := 0
var _para_discarded := 0
var _consecutive_failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a := str(args[i])
		if a == "--mode" and i + 1 < args.size():
			_mode = str(args[i + 1]).to_lower()
		if a == "--temp" and i + 1 < args.size():
			_temp = float(args[i + 1])
		if a == "--runs" and i + 1 < args.size():
			_runs = int(args[i + 1])
		if a == "--skip" and i + 1 < args.size():
			_skip = int(args[i + 1])
		if a == "--dry":
			_dry = true

	if _mode == "a":
		_arms = ["N", "P", "R"]
		_target = TARGET_A
		_results = RESULTS_A
	elif _mode == "a2":
		_arms = ["N", "P2", "R"]
		_target = TARGET_A
		_results = RESULTS_A2
	else:
		_arms = ["N", "S", "R"]
		_target = TARGET_B
		_results = RESULTS_B_DET if _temp == 0.0 else RESULTS_B

	for i in args.size():
		if str(args[i]) == "--reset":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_results))

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 180.0

	if not _dry and not await _model_available():
		printerr("model not available from LM Studio: %s" % MODEL)
		quit(2)
		return

	var files := _transcripts()
	if files.size() < 20:
		printerr("need at least 20 transcripts: some are targets, some donate shams")
		quit(2)
		return

	# Donors are a FIXED slice that is never walked as a target, so sham
	# material can never come from a transcript being scored.
	var targets := files.slice(0, 10)
	var donors := files.slice(10, 20)
	_build_sham_pool(donors)
	if _sham_pool.is_empty():
		printerr("no sham material in donor transcripts")
		quit(2)
		return

	print("=== source probe: MP2-%s ===" % _mode.to_upper())
	print("model: %s   temperature: %.2f   target: %d" % [MODEL, _temp, _target])
	print("branches: %s" % ", ".join(_arms))
	print("sham pool: %d scars from %d donor transcripts" % [_sham_pool.size(), donors.size()])

	_load_results()
	if not _rows.is_empty():
		print("resuming with %d opportunities already recorded" % _rows.size())

	var used := 0
	var seen := 0
	for f in targets:
		seen += 1
		if seen <= _skip:
			continue
		if used >= _runs or _rows.size() >= _target:
			break
		var turns := _load_turns(f)
		if turns.size() < 30:
			continue
		used += 1
		print("\ntranscript %s (%d turns)" % [f.get_file(), turns.size()])
		await _walk(turns)
		_save_results()

	_save_results()
	_report()


# ---------------------------------------------------------------- generation

func _ask(system: String, user: String) -> String:
	var done := [false]
	var text := [""]
	_http.request_completed.connect(
		func(_r: int, code: int, _h, body: PackedByteArray):
			if code == 200:
				var p = JSON.parse_string(body.get_string_from_utf8())
				if typeof(p) == TYPE_DICTIONARY and p.has("choices"):
					text[0] = str(p["choices"][0]["message"].get("content", ""))
			done[0] = true, CONNECT_ONE_SHOT)
	# No seed. Measured on this build: two identical requests at temperature 0.8
	# carrying the same seed return different text. Temperature 0 is
	# deterministic, which is why the replication runs there instead.
	var payload := {
		"model": MODEL,
		"messages": [{"role": "user", "content": system + "\n\n" + user}],
		"max_tokens": MAX_TOKENS, "temperature": _temp, "stream": false,
	}
	# Cancel anything still in flight. Without this, one request that outlived
	# its wait leaves HTTPRequest busy, every subsequent request returns
	# ERR_BUSY instantly, and the run silently walks every transcript recording
	# nothing -- which is exactly how the first attempt at this probe ended.
	_http.cancel_request()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(payload)) != OK:
		return ""
	var waited := 0
	while not done[0] and waited < 12000:
		await process_frame
		waited += 1
	return str(text[0]).strip_edges()


func _model_available() -> bool:
	var done := [false]
	var ok := [false]
	_http.request_completed.connect(
		func(_r: int, code: int, _h, body: PackedByteArray):
			if code == 200:
				var p = JSON.parse_string(body.get_string_from_utf8())
				if typeof(p) == TYPE_DICTIONARY and p.has("data"):
					for m in p["data"]:
						if str(m.get("id", "")) == MODEL:
							ok[0] = true
			done[0] = true, CONNECT_ONE_SHOT)
	if _http.request(LM_BASE + "/models") != OK:
		return false
	var waited := 0
	while not done[0] and waited < 3000:
		await process_frame
		waited += 1
	return ok[0]


# ------------------------------------------------------------------ material

func _transcripts() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(TRANSCRIPT_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".jsonl"):
			out.append(TRANSCRIPT_DIR.path_join(f))
		f = d.get_next()
	out.sort()
	out.reverse()
	return out


func _load_turns(path: String) -> Array:
	var out: Array = []
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return out
	while not fh.eof_reached():
		var line := fh.get_line()
		if line.strip_edges() == "":
			continue
		var d = JSON.parse_string(line)
		if typeof(d) != TYPE_DICTIONARY or d.get("kind", "") != "turn":
			continue
		out.append({"turn": int(d.get("turn", 0)),
			"speaker": str(d.get("display_name", "")),
			"text": str(d.get("text", ""))})
	fh.close()
	return out


func _scars_at(turns: Array, upto: int) -> Array:
	var scars: Array = []
	for t in turns:
		if int(t["turn"]) >= upto:
			break
		var shape: String = G.shape_of(str(t["text"]))
		if shape == "assert":
			continue
		var excerpt: String = LM.extract_claim(str(t["text"]))
		if excerpt == "":
			continue
		scars.append({"excerpt": excerpt, "source_turn": int(t["turn"]),
			"source_speaker": str(t["speaker"]), "other_speaker": "",
			"shape": shape, "intensity": 0.8,
			"last_reinforced_turn": int(t["turn"]),
			"last_recalled_turn": -999, "recall_count": 0})
	return scars


func _build_sham_pool(donors: Array) -> void:
	_sham_pool.clear()
	for g in donors:
		for s in _scars_at(_load_turns(g), 999999):
			_sham_pool.append(s)


## Round-robin BY INDEX, then constrained. The cursor advances past whatever it
## rejected, so the sham is never CHOSEN for being dissimilar -- selecting the
## control to lose is how a sham stops being a control.
##
## The speaker constraint closes a leak MP1 had. Every transcript here shares
## the same five-agent roster, measured at 70 of 70, so a sham can always name a
## speaker the agent recognises. Without it, R and S differ in whether the cited
## speaker exists at all, which the model can read off the prompt without
## reading the memory.
func _next_sham(real: Dictionary, cast: Dictionary, transcript_text: String) -> Dictionary:
	var n := _sham_pool.size()
	var real_len: int = str(real["excerpt"]).length()
	for k in n:
		var s: Dictionary = _sham_pool[(_sham_cursor + k) % n]
		var ex := str(s["excerpt"])
		if absi(ex.length() - real_len) > SHAM_LEN_BAND:
			continue
		if not cast.has(str(s["source_speaker"])):
			continue
		if transcript_text.find(ex) != -1:
			continue
		_sham_cursor += k + 1
		return s
	_sham_cursor += 1
	return {}


# ----------------------------------------------------------------- the walk

func _walk(turns: Array) -> void:
	var cast := {}
	var whole := ""
	for t in turns:
		cast[str(t["speaker"])] = true
		whole += " " + str(t["text"])

	for i in turns.size():
		if _rows.size() >= _target:
			return
		var t: Dictionary = turns[i]
		var now := int(t["turn"])
		if now < G.MIN_RECALL_DISTANCE + 2:
			continue
		var history: Array = []
		for j in i:
			history.append(turns[j])

		var pool: Array = []
		for s in _scars_at(turns, now):
			if not G.provenance_holds(s, history):
				continue
			if now - int(s["source_turn"]) < G.MIN_RECALL_DISTANCE:
				continue
			pool.append(s)
		if pool.is_empty():
			continue
		pool.sort_custom(func(a, b): return int(a["source_turn"]) < int(b["source_turn"]))

		# The shipped policy: the most distant eligible scar.
		var real: Dictionary = pool[0]
		var sham := _next_sham(real, cast, whole)
		if sham.is_empty():
			_discarded_no_sham += 1
			continue

		var recent := ""
		for k in range(maxi(i - 3, 0), i):
			recent += " " + str(turns[k]["text"])
		recent = recent.strip_edges()

		var ex_a := str(real["excerpt"])
		var ex_b := str(sham["excerpt"])
		var d_a := M.distinctive(ex_a, recent, ex_b)
		var d_b := M.distinctive(ex_b, recent, ex_a)

		# Discarded BEFORE generation, so the filter can never depend on an
		# outcome. Measured rate on 543 real opportunities: 0.7%.
		if d_a.is_empty() or d_b.is_empty():
			_discarded_empty += 1
			continue

		if _dry:
			_dry_opportunities += 1
			continue

		var sys := ("You are %s in a live debate arena. Reply in two sentences, "
			+ "in character.") % str(t["speaker"])
		var user := "Recent turns:\n" + recent + "\n\nRespond as %s." % str(t["speaker"])

		var replies := {}
		var para_reject := false
		for arm in _arms:
			var out := ""
			if arm == "P2":
				# The ceiling. Not an instruction about how to behave -- a
				# transformation of supplied text, which is the kind of thing
				# these models actually do. A paraphrase of the excerpt is
				# source-specific use by construction.
				out = await _ask(sys,
					"Restate the following in your own words, in one or two sentences:\n\n\""
					+ ex_a + "\"")
				if out != "" and not _is_paraphrase(out, ex_a):
					out = ""
					para_reject = true
					_para_discarded += 1
			else:
				out = await _ask(sys + _block(arm, real, sham), user)
			if out == "":
				break
			replies[arm] = out
		if replies.size() != _arms.size():
			# A rejected paraphrase is the ceiling guard doing its job, not a
			# dead endpoint. Counting it toward the abort would stop a healthy
			# run for the wrong reason.
			if para_reject:
				continue
			_gen_failures += 1
			_consecutive_failures += 1
			if _consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
				printerr("%d consecutive generation failures - is %s loaded in LM Studio?"
					% [_consecutive_failures, MODEL])
				_save_results()
				quit(2)
			continue
		_consecutive_failures = 0

		var scored := {}
		var copy := {}
		var unsup := {}
		for arm in _arms:
			var reply := str(replies[arm])
			scored[arm] = {
				"a": M.score(reply, ex_a, d_a),
				"b": M.score(reply, ex_b, d_b),
			}
			var own := ex_b if arm == "S" else ex_a
			copy[arm] = 1 if (arm != "N" and M.copied(own, reply)) else 0
			unsup[arm] = 1 if M.unsupported(reply, history) else 0

		_rows.append({"turn": now, "scored": scored, "copy": copy, "unsup": unsup})
		if _rows.size() % 10 == 0:
			print("   %d opportunities" % _rows.size())
			# Persist mid-transcript. MP1's first attempt saved once per
			# transcript and lost an hour of generation when it was killed.
			_save_results()


## Is this actually a paraphrase, or did the model copy or stub it?
##
## MP2-A's ceiling failed silently: the arm produced output, the output was
## scored, and nothing in the harness could tell that the model had ignored the
## instruction entirely. A ceiling that cannot detect its own failure is how a
## null becomes uninterpretable, so this one is checked.
func _is_paraphrase(out: String, excerpt: String) -> bool:
	if M.copied(excerpt, out):
		return false   # that is copying, not restating
	var want := float(excerpt.split(" ", false).size()) * PARAPHRASE_MIN_RATIO
	return float(out.split(" ", false).size()) >= want


func _block(arm: String, real: Dictionary, sham: Dictionary) -> String:
	match arm:
		"S":
			return "\n\n" + G.render(sham)
		"R":
			return "\n\n" + G.render(real)
		"P":
			# Calibration ceiling only. An instructed arm is not a candidate
			# intervention and will never ship -- the ledger settled prompt
			# instructions across four rejections. It exists so that a null from
			# MP2-B can be told apart from a measure that cannot see anything.
			return ("\n\n" + G.render(real)
				+ "\n\nBuild on that prior moment explicitly in your reply.")
	return ""


# ----------------------------------------------------------------- reporting

func _load_results() -> void:
	if _dry:
		return
	var fh := FileAccess.open(_results, FileAccess.READ)
	if fh == null:
		return
	var p = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(p) == TYPE_DICTIONARY:
		_discarded_empty = int(p.get("discarded_empty", 0))
		_discarded_no_sham = int(p.get("discarded_no_sham", 0))
		_para_discarded = int(p.get("para_discarded", 0))
		for row in p.get("rows", []):
			_rows.append(row)


func _save_results() -> void:
	# A dry walk records nothing, so writing here would truncate a real run's
	# results to an empty file. It generates no data and it owns no data.
	if _dry:
		return
	var fh := FileAccess.open(_results, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify({
		"rows": _rows, "model": MODEL, "mode": _mode, "temperature": _temp,
		"discarded_empty": _discarded_empty,
		"discarded_no_sham": _discarded_no_sham,
		"para_discarded": _para_discarded,
	}, "\t"))
	fh.close()


func _flag_rate(key: String, arm: String) -> float:
	if _rows.is_empty():
		return 0.0
	var c := 0
	for r in _rows:
		c += int(r[key][arm])
	return 100.0 * float(c) / float(_rows.size())


func _report() -> void:
	var n := _rows.size()
	print("\ndiscarded before generation: %d empty distinctive set, %d no matched sham"
		% [_discarded_empty, _discarded_no_sham])
	if _gen_failures > 0:
		print("generation failures: %d opportunities lost" % _gen_failures)

	if _dry:
		var offered := _dry_opportunities + _discarded_empty + _discarded_no_sham
		if offered == 0:
			printerr("dry walk found no eligible opportunities at all")
			quit(2)
			return
		print("\n--- dry walk, no generation ---")
		print("  eligible opportunities offered   %d" % offered)
		print("  usable                           %d" % _dry_opportunities)
		print("  discarded, empty distinctive set %d = %.1f%%"
			% [_discarded_empty, 100.0 * float(_discarded_empty) / float(offered)])
		print("  discarded, no matched sham       %d = %.1f%%"
			% [_discarded_no_sham, 100.0 * float(_discarded_no_sham) / float(offered)])
		print("\n  pre-registered: 0.7% discard, 100% sham availability")
		quit(0)
		return

	if n == 0:
		printerr("no opportunities recorded - %d generation failures, %d discarded."
			% [_gen_failures, _discarded_empty + _discarded_no_sham])
		printerr("an empty run is a failed run, not a result of zero.")
		quit(2)
		return

	# THE TEETH. No flag reaches past this. Three consecutive experiments told
	# different stories early and late, and MP1 warned against early reads in
	# the same document that contained one.
	if not M.decidable(n, _target):
		print("\n  %d of %d opportunities." % [n, _target])
		print("  NOT DECIDABLE. No arm rate is printed before the pre-registered")
		print("  target is reached, and there is no override.")
		quit(0)
		return

	print("\n--- %d opportunities, MP2-%s, temperature %.2f ---\n"
		% [n, _mode.to_upper(), _temp])
	print("  uptake: reply carries >= %d terms distinctive to a source\n" % M.UPTAKE_MIN)
	print("  %-10s %12s %12s" % ["", "vs A (real)", "vs B (sham)"])
	for arm in _arms:
		print("  %-10s %11.1f%% %11.1f%%"
			% ["reply " + arm, M.rate(_rows, arm, "a", "u"), M.rate(_rows, arm, "b", "u")])

	if _mode == "a":
		var gate := M.rate(_rows, "P", "a", "u") - M.rate(_rows, "N", "a", "u")
		print("\n  INSTRUCTED UPTAKE (the calibration ceiling)")
		print("    U(P,A) - U(N,A) = %+.1f points   gate %+.1f" % [gate, GATE_A])
		print("\nFROZEN DECISION (docs/EXPERIMENT_SOURCE.md)")
		if gate >= GATE_A:
			print("  MEASURE CAN SEE UPTAKE - proceed to MP2-B")
		else:
			print("  MEASURE IS BLIND - STOP. MP2-B is not run. Redesign the measure.")
		quit(0)
		return

	if _mode == "a2":
		var gate2 := M.rate(_rows, "P2", "a", "u") - M.rate(_rows, "N", "a", "u")
		var offered := n + _para_discarded
		var discard_pct := 100.0 * float(_para_discarded) / float(maxi(offered, 1))
		print("\n  PARAPHRASE CEILING")
		print("    U(P2,A) - U(N,A) = %+.1f points   gate %+.1f" % [gate2, GATE_A])
		print("    paraphrases rejected: %d of %d offered = %.1f%%  (void above %.1f%%)"
			% [_para_discarded, offered, discard_pct, PARAPHRASE_MAX_DISCARD])
		print("\nFROZEN DECISION (docs/EXPERIMENT_SOURCE.md)")
		# Void before failed. MP2-A could not tell the difference between its
		# ceiling failing and its ceiling never existing, and that ambiguity is
		# what cost the run.
		if discard_pct > PARAPHRASE_MAX_DISCARD:
			print("  CEILING VOID - too few usable paraphrases to call this a ceiling")
			print("  this is not a verdict on the measure; the control did not exist")
		elif gate2 >= GATE_A:
			print("  MEASURE CAN SEE SOURCE-SPECIFIC USE - proceed to MP2-B")
		else:
			print("  MEASURE IS BLIND - STOP. MP2-B is not run.")
			print("  the uptake definition itself is what needs replacing")
		quit(0)
		return

	var lift_r := M.lift(_rows, "R", "a", "b", "u")
	var lift_s := M.lift(_rows, "S", "b", "a", "u")
	var lift_r_uq := M.lift(_rows, "R", "a", "b", "uq")
	var lift_r3 := M.lift(_rows, "R", "a", "b", "u3")

	print("\n  SOURCE LIFT (difference of differences, floor subtracted)")
	print("    real arm, own source   %+.1f points" % lift_r)
	print("    sham arm, own source   %+.1f points  (internal replication)" % lift_s)
	print("\n  REPORTED, CANNOT CHANGE THE VERDICT")
	print("    quotation-excluded     %+.1f points" % lift_r_uq)
	print("    threshold %d            %+.1f points" % [M.UPTAKE_MIN_ROBUST, lift_r3])

	var unsup_total := 0.0
	for arm in _arms:
		unsup_total += _flag_rate("unsup", arm)
	var copy_r := _flag_rate("copy", "R")
	var copy_s := _flag_rate("copy", "S")
	print("\n  CONDITIONS")
	print("    unsupported attribution   %.1f%% summed across arms" % unsup_total)
	print("    verbatim copying          R %.1f%%   S %.1f%%   R-S %+.1f"
		% [copy_r, copy_s, copy_r - copy_s])

	var scram := M.scramble_worst(_rows, _arms, SCRAMBLE_SEED, SCRAMBLE_REPS)
	print("\n  LABEL-SCRAMBLE GATE")
	print("    worst |source lift| over %d permutations: %.1f  (bound %.1f)"
		% [SCRAMBLE_REPS, scram, SCRAMBLE_BOUND])

	print("\nFROZEN DECISION (docs/EXPERIMENT_SOURCE.md)")
	if scram >= SCRAMBLE_BOUND:
		print("  RUN IS VOID - a scramble produced a result; the estimator is broken")
		quit(1)
		return

	var conditions_hold := (unsup_total == 0.0
		and lift_r_uq >= 0.5 * lift_r
		and (copy_r - copy_s) <= 15.0)

	if lift_r >= 10.0 and (lift_r - lift_s) >= 10.0 and conditions_hold:
		print("  CONTENT CAUSAL, SELECTION MATTERS - recall is justified as designed")
	elif lift_r >= 10.0 and lift_s >= 10.0 and absf(lift_r - lift_s) < 10.0 and conditions_hold:
		print("  CONTENT CAUSAL, SELECTION IRRELEVANT - injection keeps authority")
		print("  the distance selection policy reopens as a shipping decision")
	elif lift_r < 5.0:
		print("  NO SOURCE-SPECIFIC CONTENT EFFECT")
		print("  automatic injection loses default runtime authority")
		print("  storage, scars, provenance, decay, cooldown and the guards all stay")
	elif not conditions_hold:
		print("  INCONCLUSIVE - a primary number cleared its bar but a condition failed")
	else:
		print("  INCONCLUSIVE - the bar does not move and the sample is not extended")
	quit(0)
