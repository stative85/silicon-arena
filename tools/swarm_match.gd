extends SceneTree

## Whole matches under CAGE, SWARM and a deranged SHAM, at temperature 0.
##
##   godot --headless --path . --script tools/swarm_match.gd -- --check
##   godot --headless --path . --script tools/swarm_match.gd -- --null
##   godot --headless --path . --script tools/swarm_match.gd -- --treatment
##
## Pre-registered in docs/EXPERIMENT_SWARM_B.md at 776edf9, amended twice before
## this file existed and before any match was run.
##
## THIS IS WHERE PAIRING DIES. SWARM-V replayed cage history and nothing
## advanced from either proposal, so both schedulers answered at the same frozen
## moment. Here the chosen speaker actually speaks, the reply enters history, and
## the next local views are computed from a state the treatment authored. After
## the first divergent allocation there is no shared moment left and no paired
## counterfactual is available. Distributions over independent matches replace
## it, and the SHAM -- not the cage -- is the control.
##
## TEMPERATURE 0, because this LM Studio build does not honour seeds at 0.8
## (measured in MP2: identical request, identical seed, different text). Greedy
## decoding removes the stochastic stream rather than partitioning it, so an arm
## can only differ by producing different prompts. That is the treatment.
##
## THE SHAM IS A DERANGEMENT. A plain permutation has fixed points, and a fixed
## point hands an agent its own bid back -- preserving exactly the locality the
## control exists to destroy, invisibly and in proportion to how often it
## happens.

const B := preload("res://scripts/arena/swarm_bid.gd")
const R := preload("res://scripts/arena/swarm_resolver.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const MODEL := "h2o-danube3-4b-chat"
const MAX_TOKENS := 110

const MATCH_TURNS := 30
const SEED_TURNS := 8       ## real opening used to start every arm identically
const AIRTIME_WINDOW := 20
const NAMED_WINDOW := 3

const NULL_SEEDS := 10
const NULL_MATCHES := 40
const TREATMENT_MATCHES := 40

const RESULTS_NULL := "user://swarm_b2_null.json"
const RESULTS_TREAT := "user://swarm_b2_treatment.json"

var _http: HTTPRequest
var _mode := ""
var _rows: Array[Dictionary] = []
var _results := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if str(a) == "--check":
			_mode = "check"
		if str(a) == "--null":
			_mode = "null"
		if str(a) == "--treatment":
			_mode = "treatment"
	if _mode == "":
		printerr("need one of --check, --null, --treatment")
		quit(2)
		return
	_results = RESULTS_NULL if _mode == "null" else RESULTS_TREAT

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 180.0

	if not await _model_available():
		printerr("model not available from LM Studio: %s" % MODEL)
		quit(2)
		return

	var files := _transcripts()
	if files.size() < TREATMENT_MATCHES:
		printerr("need at least %d transcripts for match seeds" % TREATMENT_MATCHES)
		quit(2)
		return

	# THE FIRST INFERENCE AFTER A COLD LOAD IS NOT REPRODUCIBLE. Measured on
	# this build: ten consecutive warm requests at temperature 0 return one
	# identical hash, stable across interleaved prompts and a 60s idle gap, but
	# the first call after the model loads differs from all of them. Every
	# recorded turn must therefore run warm, and this discarded generation is
	# what guarantees it.
	print("warming the model (discarded generation)...")
	var warm := await _ask("warmup", [{"turn": 0, "speaker": "warmup", "text": "hello"}])
	if warm == "":
		printerr("warm-up generation failed; is %s loaded?" % MODEL)
		quit(2)
		return

	match _mode:
		"check":
			await _integrity_check(files)
		"null":
			await _null_run(files)
		"treatment":
			await _treatment_run(files)


# ------------------------------------------------------- protocol integrity

## Not a decision gate and it has no bar. A null measured on a
## non-reproducible harness is measuring the harness.
func _integrity_check(files: Array) -> void:
	print("=== SWARM-B protocol integrity ===")
	print("3 repeats per arm, same match seed, same sham seed
")
	print("byte-identical transcripts are NOT required: temperature 0 on this")
	print("stack is deterministic in bursts and drifts across long sequences.")
	print("what IS required is an identical mechanical trajectory.
")
	var ok := true
	for arm in ["cage", "swarm", "sham"]:
		var runs: Array = []
		for _rep in 3:
			runs.append(await _play(files[0], arm, 0, 1))

		var speakers_same := true
		var codes_same := true
		var text_same := true
		var flips := 0
		var compared := 0
		for i in range(1, runs.size()):
			if str(runs[i]["speakers"]) != str(runs[0]["speakers"]):
				speakers_same = false
			if str(runs[i]["codes"]) != str(runs[0]["codes"]):
				codes_same = false
			if str(runs[i]["checksum"]) != str(runs[0]["checksum"]):
				text_same = false
			# BID-FLIP RATE: how often the text drift changed who was selected.
			# Drift that never flips a bid is noise in the prose. Drift that
			# flips bids is noise in the treatment.
			var a: PackedStringArray = str(runs[0]["speakers"]).split(",")
			var b: PackedStringArray = str(runs[i]["speakers"]).split(",")
			for k in mini(a.size(), b.size()):
				compared += 1
				if a[k] != b[k]:
					flips += 1

		print("  %-6s speakers %s   codes %s   text %s   bid flips %d/%d (%.1f%%)"
			% [arm,
				"SAME" if speakers_same else "DIFFER",
				"SAME" if codes_same else "DIFFER",
				"same" if text_same else "drifts",
				flips, compared,
				0.0 if compared == 0 else 100.0 * float(flips) / float(compared)])
		if not (speakers_same and codes_same):
			ok = false
	print("")
	if ok:
		print("MECHANICAL TRAJECTORY REPRODUCIBLE - the null may be interpreted")
		print("text drift is present and is absorbed by the sham-vs-sham null")
		quit(0)
	else:
		printerr("MECHANICAL TRAJECTORY NOT REPRODUCIBLE - stop.")
		printerr("the drift is flipping bids, so it is inside the treatment and")
		printerr("a wider bar will not rescue it. SWARM-B needs another instrument.")
		quit(1)


# ------------------------------------------------------------------ the runs

func _null_run(files: Array) -> void:
	print("=== SWARM-B sham null: %d derangement seeds x %d matches ==="
		% [NULL_SEEDS, NULL_MATCHES])
	print("this null is trajectory variance from destroying the")
	print("local-state-to-identity mapping in different valid ways.")
	print("it is NOT sampling noise: temperature 0 removed that.\n")
	_load()
	for s in NULL_SEEDS:
		for m in NULL_MATCHES:
			if _recorded("sham", m, s):
				continue
			var out: Dictionary = await _play(files[m], "sham", s, m)
			out["sham_seed"] = s
			_rows.append(out)
			_save()
			print("  seed %d match %d: longest silence %d" % [s, m, int(out["longest_silence"])])
	_save()
	_report_null()


func _treatment_run(files: Array) -> void:
	print("=== SWARM-B treatment: %d match triples ===\n" % TREATMENT_MATCHES)
	_load()
	for m in TREATMENT_MATCHES:
		for arm in ["cage", "swarm", "sham"]:
			if _recorded(arm, m, 0):
				continue
			var out: Dictionary = await _play(files[m], arm, 0, m)
			out["sham_seed"] = 0
			_rows.append(out)
			_save()
		print("  match %d of %d complete" % [m + 1, TREATMENT_MATCHES])
	_save()
	_report_treatment()


func _recorded(arm: String, match_index: int, sham_seed: int) -> bool:
	for r in _rows:
		if str(r["arm"]) == arm and int(r["match"]) == match_index \
				and int(r.get("sham_seed", 0)) == sham_seed:
			return true
	return false


# -------------------------------------------------------------- playing one

func _play(path: String, arm: String, sham_seed: int, match_index: int) -> Dictionary:
	var seed_turns := _load_turns(path)
	if seed_turns.size() < SEED_TURNS + 2:
		return {"arm": arm, "match": match_index, "speakers": "", "checksum": "",
			"codes": "", "longest_silence": 0, "participation": {}, "failures": {}}

	var roster := _roster(seed_turns)
	var history: Array = seed_turns.slice(0, SEED_TURNS)
	var speakers: Array = []
	var generated: Array = []
	var codes: Array = []
	var participation := {}
	var failures := {"NO_BIDS": 0, "NO_ELIGIBLE_BIDS": 0, "MALFORMED_BID": 0,
		"SHAM_UNDERANGEABLE": 0, "FALLBACK_WAKES": 0, "REQUEST_FAILED": 0}
	for a in roster:
		participation[a] = {"bids": 0, "abstained": 0, "malformed": 0, "spoke": 0}

	for t in MATCH_TURNS:
		var prev := str(history[history.size() - 1]["speaker"])
		var next_speaker := ""

		if arm == "cage":
			next_speaker = roster[(roster.find(prev) + 1) % roster.size()]
		else:
			var eligible: Array = []
			var tuples: Array = []
			for agent_v in roster:
				var agent := str(agent_v)
				if agent == prev:
					continue
				var view := _local_view(agent, history)
				var bid := B.compute(view)
				var submits := B.should_bid(view)
				if is_nan(bid):
					participation[agent]["malformed"] += 1
				elif submits:
					participation[agent]["bids"] += 1
				else:
					participation[agent]["abstained"] += 1
				eligible.append(agent)
				tuples.append({"submits": submits, "bid": (0.0 if is_nan(bid) else bid)})

			if arm == "sham":
				if eligible.size() < 2:
					failures["SHAM_UNDERANGEABLE"] += 1
				else:
					tuples = _derange(tuples, sham_seed, match_index, t)

			var bids: Array = []
			for i in eligible.size():
				if bool(tuples[i]["submits"]):
					# NORMAL because that is the regime SWARM-B actually ran in:
					# one model, no escalation, which METABOLISM-A calls M0. The
					# key became mandatory when the vocabulary grew; declaring it
					# explicitly is a description of what happened, not a change
					# to it. The resolver validates the class and never acts on
					# it, so every recorded allocation is unaffected.
					bids.append({"agent_id": str(eligible[i]), "eligible": true,
						"bid": float(tuples[i]["bid"]),
						"requested_class": "NORMAL"})

			var out: Dictionary = R.resolve(bids)
			if bool(out.get("ok", false)):
				next_speaker = str(out["agent_id"])
				codes.append("OK")
			else:
				# SWARM-SYSTEM FAILURE. Distinct from an agent choosing silence:
				# nobody could act, so the fallback authority wakes. This is the
				# cage-dependence number and nothing else is.
				var code := str(out.get("code", "?"))
				failures[code] = int(failures.get(code, 0)) + 1
				failures["FALLBACK_WAKES"] += 1
				codes.append(code)
				next_speaker = roster[(roster.find(prev) + 1) % roster.size()]

		var reply := await _ask(next_speaker, history)
		if reply == "":
			failures["REQUEST_FAILED"] += 1
			break
		history.append({"turn": SEED_TURNS + t, "speaker": next_speaker, "text": reply})
		speakers.append(next_speaker)
		generated.append(reply)
		participation[next_speaker]["spoke"] += 1

	var body := ""
	for h in history:
		body += str(h["speaker"]) + "|" + str(h["text"]) + "\n"

	return {
		"arm": arm, "match": match_index,
		"speakers": ",".join(PackedStringArray(speakers)),
		"checksum": body.sha256_text(),
		"codes": ",".join(PackedStringArray(codes)),
		"texts": generated,
		"longest_silence": _longest_silence(speakers, roster),
		"gini": _gini(speakers, roster),
		"participation": participation,
		"failures": failures,
	}


## No agent may receive its own tuple. Deterministic in (sham_seed, match, turn)
## and never in the arm's own trajectory.
func _derange(tuples: Array, sham_seed: int, match_index: int, turn: int) -> Array:
	var n := tuples.size()
	var idx: Array = []
	for i in n:
		idx.append(i)
	var h := _hash("%d:%d:%d" % [sham_seed, match_index, turn])
	# Fisher-Yates with a deterministic stream, retried until no fixed point.
	for _attempt in 32:
		var shuffled := idx.duplicate()
		for i in range(n - 1, 0, -1):
			h = (h * 1103515245 + 12345) & 0x7FFFFFFF
			var j := h % (i + 1)
			var tmp = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		var fixed := false
		for i in n:
			if int(shuffled[i]) == i:
				fixed = true
				break
		if not fixed:
			var out: Array = []
			for i in n:
				out.append(tuples[int(shuffled[i])])
			return out
	# A cycle-shift is a derangement for n >= 2 and is the deterministic
	# fallback, so this can never silently return the identity.
	var out2: Array = []
	for i in n:
		out2.append(tuples[(i + 1) % n])
	return out2


func _hash(s: String) -> int:
	var h := 2166136261
	for byte in s.to_utf8_buffer():
		h = (h ^ int(byte)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h & 0x7FFFFFFF


# -------------------------------------------------------------- local views

func _local_view(agent: String, history: Array) -> Dictionary:
	var since := 0
	var found := false
	for k in range(history.size() - 1, -1, -1):
		if str(history[k]["speaker"]) == agent:
			since = (history.size() - 1) - k
			found = true
			break
	if not found:
		since = history.size()

	var start := maxi(history.size() - AIRTIME_WINDOW, 0)
	var mine := 0
	var total := 0
	for k in range(start, history.size()):
		total += 1
		if str(history[k]["speaker"]) == agent:
			mine += 1
	var share := 0.0 if total == 0 else float(mine) / float(total)

	var handle := str(agent.split(" ", false)[0]).to_lower()
	var named := false
	for k in range(maxi(history.size() - NAMED_WINDOW, 0), history.size()):
		if str(history[k]["speaker"]) == agent:
			continue
		if str(history[k]["text"]).to_lower().find(handle) != -1:
			named = true
			break

	return B.local_view(since, named, share)


# -------------------------------------------------------------------- stats

func _longest_silence(speakers: Array, roster: Array) -> int:
	var worst := 0
	for agent in roster:
		var gap := 0
		var seen := false
		for s in speakers:
			if str(s) == str(agent):
				seen = true
				gap = 0
			else:
				gap += 1
				if seen:
					worst = maxi(worst, gap)
	return worst


func _gini(speakers: Array, roster: Array) -> float:
	if speakers.is_empty():
		return 0.0
	var counts: Array = []
	for agent in roster:
		var c := 0
		for s in speakers:
			if str(s) == str(agent):
				c += 1
		counts.append(c)
	counts.sort()
	var n := counts.size()
	var total := 0.0
	var weighted := 0.0
	for i in n:
		total += float(counts[i])
		weighted += float(i + 1) * float(counts[i])
	if total == 0.0:
		return 0.0
	return (2.0 * weighted) / (float(n) * total) - float(n + 1) / float(n)


# --------------------------------------------------------------- generation

func _ask(speaker: String, history: Array) -> String:
	var recent := ""
	for k in range(maxi(history.size() - 3, 0), history.size()):
		recent += "\n" + str(history[k]["speaker"]) + ": " + str(history[k]["text"])
	var sys := ("You are %s in a live debate arena. Reply in two sentences, "
		+ "in character.") % speaker
	var user := "Recent turns:" + recent.strip_edges() + "\n\nRespond as %s." % speaker

	var payload := {
		"model": MODEL,
		"messages": [{"role": "user", "content": sys + "\n\n" + user}],
		"max_tokens": MAX_TOKENS, "temperature": 0.0, "stream": false,
	}

	# Await the signal directly rather than connecting a one-shot lambda.
	# A lambda left over from a request that timed out stays connected and can
	# fire during the NEXT call, delivering the previous body -- which is a race
	# that produces exactly the kind of intermittent divergence the integrity
	# check caught, and which no amount of decoder determinism would fix.
	_http.cancel_request()
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(payload)) != OK:
		return ""
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return ""
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
		return ""
	return str(parsed["choices"][0]["message"].get("content", "")).strip_edges()


func _model_available() -> bool:
	_http.cancel_request()
	if _http.request(LM_BASE + "/models") != OK:
		return false
	var res: Array = await _http.request_completed
	if int(res[1]) != 200:
		return false
	var p = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(p) != TYPE_DICTIONARY or not p.has("data"):
		return false
	for m in p["data"]:
		if str(m.get("id", "")) == MODEL:
			return true
	return false


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


func _roster(turns: Array) -> Array:
	var seen := {}
	var out: Array = []
	for t in turns:
		var s := str(t["speaker"])
		if not seen.has(s):
			seen[s] = true
			out.append(s)
	return out


# ----------------------------------------------------------------- reporting

func _load() -> void:
	var fh := FileAccess.open(_results, FileAccess.READ)
	if fh == null:
		return
	var p = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(p) == TYPE_DICTIONARY:
		for row in p.get("rows", []):
			_rows.append(row)


func _save() -> void:
	var fh := FileAccess.open(_results, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify({"rows": _rows}, "\t"))
	fh.close()


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	var n := v.size()
	if n % 2 == 1:
		return float(v[n / 2])
	return (float(v[n / 2 - 1]) + float(v[n / 2])) / 2.0


func _report_null() -> void:
	var by_seed := {}
	for r in _rows:
		var s := int(r.get("sham_seed", 0))
		if not by_seed.has(s):
			by_seed[s] = []
		by_seed[s].append(int(r["longest_silence"]))

	if by_seed.size() < NULL_SEEDS:
		print("\n  %d of %d derangement seeds complete." % [by_seed.size(), NULL_SEEDS])
		print("  NOT DECIDABLE. No floor is published before the pre-registered")
		print("  seed count is reached, and there is no override.")
		quit(0)
		return

	var medians: Array = []
	for s in by_seed.keys():
		medians.append(_median(by_seed[s]))
	var diffs: Array = []
	for i in medians.size():
		for j in range(i + 1, medians.size()):
			diffs.append(absf(float(medians[i]) - float(medians[j])))
	diffs.sort()

	var p90 := float(diffs[mini(int(float(diffs.size()) * 0.9), diffs.size() - 1)])
	var worst := float(diffs[diffs.size() - 1])
	var bar := maxf(3.0 * p90, 3.0)

	print("\n--- sham null across %d derangement seeds ---\n" % by_seed.size())
	print("  per-seed median longest silence: %s" % str(medians))
	print("  pairwise |difference|: p90 %.2f   max %.2f" % [p90, worst])
	print("\nFROZEN DECISION (docs/EXPERIMENT_SWARM_B.md)")
	if p90 == 0.0 and worst == 0.0:
		printerr("  RUN IS VOID - the sham null has zero spread.")
		printerr("  the derangement is not changing what it was built to change,")
		printerr("  so the control is broken and the treatment has nothing to")
		printerr("  be compared against.")
		quit(1)
		return
	print("  FLOOR ESTABLISHED")
	print("  bar = max(3 x %.2f, 3.0) = %.2f turns" % [p90, bar])
	quit(0)


func _report_treatment() -> void:
	var arms := {"cage": [], "swarm": [], "sham": []}
	for r in _rows:
		var a := str(r["arm"])
		if arms.has(a):
			arms[a].append(int(r["longest_silence"]))

	if arms["swarm"].size() < TREATMENT_MATCHES:
		print("\n  %d of %d matches per arm." % [arms["swarm"].size(), TREATMENT_MATCHES])
		print("  NOT DECIDABLE. No rate is printed before the pre-registered")
		print("  target is reached, and there is no override.")
		quit(0)
		return
	print("\n  %d matches per arm recorded. Floor must be supplied from --null."
		% arms["swarm"].size())
	print("  medians: cage %.1f  swarm %.1f  sham %.1f"
		% [_median(arms["cage"]), _median(arms["swarm"]), _median(arms["sham"])])
	quit(0)
