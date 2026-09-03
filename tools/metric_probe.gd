extends SceneTree

## Is `_is_callback` measuring memory engagement, or is it measuring nothing?
##
##   godot --headless --path . --script tools/metric_probe.gd -- --runs 4
##
## Pre-registered in docs/EXPERIMENT_METRIC.md before this file was written.
##
## Gonzo recall is SHIPPED, and it was accepted on evidence produced by this
## metric. The metric has since scored a no-memory control HIGHER than either
## memory arm. So the question is not academic: does recall stay shipped?
##
## THE SCORE IS NOT THE INSTRUMENT HERE. Each arm records WHY the metric
## refused -- provenance, too few shared words, too few novel words, or the
## six-word verbatim exclusion. The hypothesis is that genuine engagement echoes
## a phrase of the memory and gets disqualified by that last rule, while topical
## coincidence sails through. That is a claim about a specific counter, and it
## is checked directly rather than inferred from percentages.

const G := preload("res://scripts/arena/gonzo_recall.gd")
const LM := preload("res://scripts/arena/live_match.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const MAX_TOKENS := 110
const RESULTS := "user://metric_probe.json"

var _model := ""
var _runs := 4
var _skip := 0
var _rows: Array[Dictionary] = []
var _http: HTTPRequest

## Scars harvested from OTHER transcripts, used as sham material. Real text,
## real provenance in its own match, simply not from this conversation.
var _sham_pool: Array = []
var _sham_cursor := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a := str(args[i])
		if a == "--runs" and i + 1 < args.size():
			_runs = int(args[i + 1])
		if a == "--skip" and i + 1 < args.size():
			_skip = int(args[i + 1])
		if a == "--reset":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS))

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 180.0

	_model = await _first_model()
	if _model == "":
		printerr("no chat model available from LM Studio")
		quit(2)
		return

	var files := _transcripts()
	if files.size() < 2:
		printerr("need at least 2 transcripts: one supplies the sham pool")
		quit(2)
		return

	print("=== metric probe: S0 none / S1 sham / S2 real ===")
	print("model: %s" % _model)

	_load_results()
	if not _rows.is_empty():
		print("resuming with %d opportunities already recorded" % _rows.size())

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

		# The sham pool is built from every OTHER transcript, so sham material
		# is never drawn from the conversation being scored.
		_sham_pool.clear()
		for g in files:
			if g == f:
				continue
			var other := _load_turns(g)
			for s in _scars_at(other, 999999):
				_sham_pool.append(s)
		if _sham_pool.is_empty():
			continue

		used += 1
		print("\ntranscript %s (%d turns, %d sham scars available)"
			% [f.get_file(), turns.size(), _sham_pool.size()])
		await _walk(turns)
		_save_results()

	_save_results()
	_report()


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


## Round-robin by index. The sham is never CHOSEN for being dissimilar --
## selecting the control to lose is how a sham stops being a control.
func _next_sham() -> Dictionary:
	var s: Dictionary = _sham_pool[_sham_cursor % _sham_pool.size()]
	_sham_cursor += 1
	return s


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

		var pool: Array = []
		for s in scars:
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
		var sham := _next_sham()

		var sys := ("You are %s in a live debate arena. Reply in two sentences, "
			+ "in character.") % str(t["speaker"])
		var user := "Recent turns:\n" + recent.strip_edges() + "\n\nRespond as %s." % str(t["speaker"])

		# Identical volume and format on S1 and S2; only the content differs.
		var s0 := await _ask(sys, user)
		var s1 := await _ask(sys + "\n\n" + G.render(sham), user)
		var s2 := await _ask(sys + "\n\n" + G.render(real), user)
		if s0 == "" or s1 == "" or s2 == "":
			continue

		# All three scored against THE SAME real scar.
		_rows.append({
			"turn": now,
			"s0": _why(real, s0, history),
			"s1": _why(real, s1, history),
			"s2": _why(real, s2, history),
		})
		if _rows.size() % 10 == 0:
			print("   %d opportunities" % _rows.size())
			# Persist mid-transcript. A first version only saved after a whole
			# transcript finished, so a run killed 20 opportunities in lost all
			# 20 -- an hour of generation with nothing to resume from.
			_save_results()


## The frozen callback definition, decomposed. Same order, same thresholds, same
## outcome as `_is_callback` -- it just reports WHICH clause refused instead of
## collapsing everything to false.
func _why(scar: Dictionary, reply: String, history: Array) -> String:
	if not G.provenance_holds(scar, history):
		return "provenance"
	var ex := str(scar["excerpt"])
	var exw := _words(ex)
	var rw := _words(reply)
	var shared := 0
	for w in exw:
		if rw.has(w):
			shared += 1
	if shared < 2:
		return "shared"
	var novel := 0
	for w in rw:
		if not exw.has(w):
			novel += 1
	if novel < 8:
		return "novel"
	if _shares_ngram(ex, reply, 6):
		return "verbatim"
	return "passed"


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
		for row in p.get("rows", []):
			_rows.append(row)


func _save_results() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify({"rows": _rows, "model": _model}, "\t"))
	fh.close()


func _rate(arm: String, reason: String) -> float:
	if _rows.is_empty():
		return 0.0
	var c := 0
	for r in _rows:
		if str(r[arm]) == reason:
			c += 1
	return 100.0 * float(c) / float(_rows.size())


func _report() -> void:
	var n := _rows.size()
	if n == 0:
		print("\nno opportunities found")
		quit(1)
		return

	const REASONS := ["passed", "verbatim", "shared", "novel", "provenance"]
	print("\n--- %d opportunities ---\n" % n)
	print("  the metric's verdict, and which clause produced it:\n")
	print("  %-12s %8s %8s %8s" % ["", "S0 none", "S1 sham", "S2 real"])
	for reason in REASONS:
		print("  %-12s %7.1f%% %7.1f%% %7.1f%%"
			% [reason, _rate("s0", reason), _rate("s1", reason), _rate("s2", reason)])

	var p0 := _rate("s0", "passed")
	var p1 := _rate("s1", "passed")
	var p2 := _rate("s2", "passed")
	var v0 := _rate("s0", "verbatim")
	var v2 := _rate("s2", "verbatim")
	var verbatim_gap := v2 - v0
	var sham_gap := p2 - p1

	print("\n  ENGAGEMENT (metric as shipped)")
	print("    S2 real %.1f%%   S1 sham %.1f%%   S2-S1 = %+.1f points" % [p2, p1, sham_gap])
	print("    S0 none %.1f%%" % p0)
	print("\n  THE SUSPECT CLAUSE")
	print("    verbatim rejection: S0 %.1f%%   S2 %.1f%%   gap %+.1f points"
		% [v0, v2, verbatim_gap])

	# Engagement with the verbatim exclusion removed -- the proposed repair.
	var r0 := p0 + v0
	var r1 := p1 + _rate("s1", "verbatim")
	var r2 := p2 + v2
	print("\n  REPAIRED METRIC (verbatim exclusion removed, reported separately)")
	print("    S0 none %.1f%%   S1 sham %.1f%%   S2 real %.1f%%" % [r0, r1, r2])
	print("    S2-S1 = %+.1f points   S2-S0 = %+.1f points" % [r2 - r1, r2 - r0])

	print("\nFROZEN DECISION (docs/EXPERIMENT_METRIC.md)")
	if n < 120:
		print("  NOT YET DECIDABLE - %d of the pre-registered 120" % n)
		quit(0)
		return
	if verbatim_gap >= 10.0:
		print("  METRIC IS BROKEN - redefine it")
		print("  report engagement and verbatim rate as two numbers, never one")
	elif verbatim_gap < 5.0 and sham_gap >= 10.0:
		print("  METRIC IS SOUND - recall keeps its shipped status")
	elif verbatim_gap < 5.0:
		print("  RECALL LOSES ITS JUSTIFICATION - the sham is as good as the memory")
		print("  memory content is not doing the work; reopen as a shipping decision")
	else:
		print("  INCONCLUSIVE - metric stays suspect")
		print("  no absolute conversion number may be published until settled")
	quit(0)
