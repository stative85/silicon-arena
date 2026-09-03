extends SceneTree

## Paired counterfactual recall trials: does resonance choose a better memory
## than distance, given the exact same moment?
##
##   godot --headless --path . --script tools/recall_tournament.gd -- --runs 4
##
## Walks a RECORDED transcript. At every eligible recall opportunity it freezes
## the state and generates two disposable responses that differ in exactly one
## thing -- which scar was injected. Both are scored, both are recorded, both
## are thrown away. Nothing enters history, so the branches cannot diverge and
## every opportunity yields one D and one R observation on identical context.
##
## The arena experiment could not answer this: once the arms pick differently
## the debates diverge and the candidate pools stop being comparable, so the
## design manufactures the variance it is fighting.
##
## Eligibility, shortlisting and scoring come from GonzoRecall itself rather
## than a reimplementation, so this harness cannot quietly disagree with the
## runtime it is measuring.

const G := preload("res://scripts/arena/gonzo_recall.gd")
const LM := preload("res://scripts/arena/live_match.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const MAX_TOKENS := 110

## Results persist across invocations: a full tournament exceeds a single
## process window, and the pre-registered target is 100+ pairs. Plumbing only --
## the callback definition and the decision margins are untouched.
const RESULTS := "user://recall_tournament.json"

var _model := ""
var _runs := 4
var _skip := 0
var _pairs: Array[Dictionary] = []
var _skipped_same := 0
var _http: HTTPRequest


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for i in OS.get_cmdline_user_args().size():
		var a := str(OS.get_cmdline_user_args()[i])
		if a == "--runs" and i + 1 < OS.get_cmdline_user_args().size():
			_runs = int(OS.get_cmdline_user_args()[i + 1])
		if a == "--skip" and i + 1 < OS.get_cmdline_user_args().size():
			_skip = int(OS.get_cmdline_user_args()[i + 1])
		if a == "--reset":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS))

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 180.0

	_model = await _first_model()
	if _model == "":
		printerr("no model available from LM Studio")
		quit(2)
		return
	print("=== paired recall tournament ===")
	print("model: %s" % _model)

	var files := _transcripts()
	if files.is_empty():
		printerr("no transcripts in %s" % TRANSCRIPT_DIR)
		quit(2)
		return

	_load_results()
	if not _pairs.is_empty():
		print("resuming with %d pairs already recorded" % _pairs.size())
	var used := 0
	var seen := 0
	for f in files:
		seen += 1
		if seen <= _skip:
			continue
		if used >= _runs:
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


## The two prompts differ only in the injected memory, so any generation
## setting that differed would confound the comparison.
func _ask(system: String, user: String) -> String:
	var done := [false]
	var text := [""]
	var cb := func(_r: int, code: int, _h, body: PackedByteArray):
		if code == 200:
			var p = JSON.parse_string(body.get_string_from_utf8())
			if typeof(p) == TYPE_DICTIONARY and p.has("choices"):
				text[0] = str(p["choices"][0]["message"].get("content", ""))
		done[0] = true
	_http.request_completed.connect(cb, CONNECT_ONE_SHOT)
	var payload := {
		"model": _model,
		"messages": [{"role": "user", "content": system + "\n\n" + user}],
		"max_tokens": MAX_TOKENS, "temperature": 0.8, "stream": false,
	}
	if _http.request(LM_BASE + "/chat/completions",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(payload)) != OK:
		return ""
	var waited := 0
	while not done[0] and waited < 12000:
		await process_frame
		waited += 1
	return str(text[0]).strip_edges()


func _first_model() -> String:
	var done := [false]
	var id := [""]
	_http.request_completed.connect(
		func(_r: int, code: int, _h, body: PackedByteArray):
			if code == 200:
				var p = JSON.parse_string(body.get_string_from_utf8())
				if typeof(p) == TYPE_DICTIONARY and p.has("data") and p["data"].size() > 0:
					# Prefer something small and chat-capable that the arena uses.
					for m in p["data"]:
						var mid := str(m.get("id", ""))
						if mid.find("stablelm") != -1 or mid.find("danube") != -1:
							id[0] = mid
							break
					if id[0] == "":
						id[0] = str(p["data"][0].get("id", ""))
			done[0] = true, CONNECT_ONE_SHOT)
	if _http.request(LM_BASE + "/models") != OK:
		return ""
	var waited := 0
	while not done[0] and waited < 3000:
		await process_frame
		waited += 1
	return id[0]


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


## Rebuild the scar set exactly as the arena would have.
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


func _walk(turns: Array) -> void:
	for i in turns.size():
		var t: Dictionary = turns[i]
		var now := int(t["turn"])
		if now < G.MIN_RECALL_DISTANCE + 2:
			continue
		var history: Array = []
		for j in i:
			history.append(turns[j])
		var scars := _scars_at(turns, now)
		if scars.is_empty():
			continue

		var recent := ""
		for k in range(maxi(i - 3, 0), i):
			recent += " " + str(turns[k]["text"])
		var named: Array = []
		for s in scars:
			if not named.has(str(s["source_speaker"])):
				named.append(str(s["source_speaker"]))

		# Shared eligible pool, then the shared shortlist by distance.
		var pool: Array = []
		for s in scars:
			if not G.provenance_holds(s, history):
				continue
			if now - int(s["source_turn"]) < G.MIN_RECALL_DISTANCE:
				continue
			pool.append(s)
		if pool.size() < 2:
			continue
		pool.sort_custom(func(a, b): return int(a["source_turn"]) < int(b["source_turn"]))
		var shortlist: Array = pool.slice(0, mini(G.CANDIDATE_SHORTLIST, pool.size()))

		var d_pick: Dictionary = shortlist[0]
		var r_pick: Dictionary = shortlist[0]
		var best := -1.0
		for s in shortlist:
			var v: float = G.score(s, recent, str(t["speaker"]), named, now)
			if v > best:
				best = v
				r_pick = s
		if int(d_pick["source_turn"]) == int(r_pick["source_turn"]):
			_skipped_same += 1
			continue

		var sys := ("You are %s in a live debate arena. Reply in two sentences, "
			+ "in character.") % str(t["speaker"])
		var user := "Recent turns:\n" + recent.strip_edges() + "\n\nRespond as %s." % str(t["speaker"])

		var d_text := await _ask(sys + "\n\n" + G.render(d_pick), user)
		var r_text := await _ask(sys + "\n\n" + G.render(r_pick), user)
		if d_text == "" or r_text == "":
			continue

		_pairs.append({
			"turn": now,
			"d_ok": _is_callback(d_pick, d_text, history),
			"r_ok": _is_callback(r_pick, r_text, history),
			"d_dist": now - int(d_pick["source_turn"]),
			"r_dist": now - int(r_pick["source_turn"]),
			"d_unsupported": not G.provenance_holds(d_pick, history),
			"r_unsupported": not G.provenance_holds(r_pick, history),
		})
		if _pairs.size() % 10 == 0:
			print("   %d pairs" % _pairs.size())


## The frozen callback definition: provenance valid, engages, novel language
## beyond the excerpt, and not a verbatim repetition.
func _is_callback(scar: Dictionary, reply: String, history: Array) -> bool:
	if not G.provenance_holds(scar, history):
		return false
	var ex := str(scar["excerpt"])
	var exw := _words(ex)
	var rw := _words(reply)
	var shared := 0
	for w in exw:
		if rw.has(w):
			shared += 1
	if shared < 2:
		return false
	var novel := 0
	for w in rw:
		if not exw.has(w):
			novel += 1
	if novel < 8:
		return false
	return not _shares_ngram(ex, reply, 6)


func _words(t: String) -> Dictionary:
	var out := {}
	for w in t.to_lower().split(" ", false):
		var c := ""
		for i in w.length():
			var ch := w[i]
			if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
				c += ch
		if c.length() > 3 and not G.STOP.has(c):
			out[c] = true
	return out


func _shares_ngram(a: String, b: String, n: int) -> bool:
	var aw := a.to_lower().split(" ", false)
	var bw := b.to_lower().split(" ", false)
	if aw.size() < n or bw.size() < n:
		return false
	var seen := {}
	for i in range(aw.size() - n + 1):
		seen[" ".join(aw.slice(i, i + n))] = true
	for i in range(bw.size() - n + 1):
		if seen.has(" ".join(bw.slice(i, i + n))):
			return true
	return false


func _load_results() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.READ)
	if fh == null:
		return
	var p = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(p) == TYPE_DICTIONARY:
		_skipped_same = int(p.get("skipped_same", 0))
		for row in p.get("pairs", []):
			_pairs.append(row)


func _save_results() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify({
		"pairs": _pairs, "skipped_same": _skipped_same,
		"model": _model}, "	"))
	fh.close()


func _report() -> void:
	var n := _pairs.size()
	if n == 0:
		print("\nno paired opportunities found")
		quit(1)
		return
	var d_ok := 0
	var r_ok := 0
	var unsupported := 0
	var d_dist := 0
	var r_dist := 0
	for p in _pairs:
		if p["d_ok"]:
			d_ok += 1
		if p["r_ok"]:
			r_ok += 1
		if p["d_unsupported"] or p["r_unsupported"]:
			unsupported += 1
		d_dist += int(p["d_dist"])
		r_dist += int(p["r_dist"])

	var d_conv := 100.0 * float(d_ok) / float(n)
	var r_conv := 100.0 * float(r_ok) / float(n)
	print("\n--- %d paired opportunities (%d skipped: both rules picked the same scar) ---"
		% [n, _skipped_same])
	print("  DISTANCE  conversion %5.1f%%   mean source distance %.1f" % [d_conv, float(d_dist) / float(n)])
	print("  RESONANCE conversion %5.1f%%   mean source distance %.1f" % [r_conv, float(r_dist) / float(n)])
	print("  R - D = %+.1f points" % (r_conv - d_conv))
	print("  unsupported attribution: %d" % unsupported)

	# Batch agreement: quarters of the sequence, so a majority can be read.
	var q := maxi(n / 4, 1)
	var wins := 0
	print("\n  batches of %d:" % q)
	for b in 4:
		var lo := b * q
		var hi := mini(lo + q, n)
		if lo >= hi:
			continue
		var dd := 0
		var rr := 0
		for k in range(lo, hi):
			if _pairs[k]["d_ok"]:
				dd += 1
			if _pairs[k]["r_ok"]:
				rr += 1
		var dv := 100.0 * float(dd) / float(hi - lo)
		var rv := 100.0 * float(rr) / float(hi - lo)
		if rv > dv:
			wins += 1
		print("    batch %d  D %5.1f%%  R %5.1f%%  %s" % [b + 1, dv, rv,
			"R" if rv > dv else ("D" if dv > rv else "tie")])
	print("  R wins %d of 4 batches" % wins)

	var diff := r_conv - d_conv
	print("\nFROZEN DECISION (docs/EXPERIMENT_TOURNAMENT.md)")
	if diff >= 8.0 and wins >= 3 and unsupported == 0:
		print("  KEEP RESONANCE")
	elif absf(diff) <= 5.0 and unsupported == 0:
		print("  DELETE RESONANCE")
	else:
		print("  INCONCLUSIVE - resonance stays, question closed")
	quit(0)
