extends SceneTree

## Paired counterfactual: does a real embedding choose a better memory than
## raw distance, given the exact same moment?
##
##   godot --headless --path . --script tools/embed_tournament.gd -- --runs 4
##
## Pre-registered in docs/EXPERIMENT_EMBEDDING.md BEFORE the model was
## downloaded. E0 is the shipped distance policy. E1 is nomic-embed-text-v1.5
## selecting from THE SAME shortlist by cosine similarity to the current moment.
## Only the chosen scar differs; both replies are scored and discarded.
##
## WHY OPPORTUNITIES WHERE THE TWO RULES AGREE ARE KEPT.
##
## The resonance tournament threw those away. This one generates both replies
## anyway and records them as `diverged: false`, because when the injected scar
## is identical the two replies differ ONLY by sampling noise. That gives a null
## control for free, measured inside the same run, on the same model, at the
## same moments as the real comparison.
##
## Without it a "+6 point" result has nothing to be six points larger than.
## CONTRIBUTING rule 2: you cannot set a useful threshold for a metric whose
## noise floor you have not measured.
##
## Reported separately, as pre-registered: overall conversion delta, and the
## delta restricted to opportunities where the two rules actually disagreed.
## The second is the only place an embedding router can demonstrate that it has
## discriminative power rather than expensive agreement.

const G := preload("res://scripts/arena/gonzo_recall.gd")
const E := preload("res://tools/embed_router.gd")
const LM := preload("res://scripts/arena/live_match.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const MAX_TOKENS := 110
const RESULTS := "user://embed_tournament.json"

## If the embedder cannot be reached the run ABORTS rather than silently
## degrading to distance-vs-distance, which would look like a null result
## instead of a missing dependency.
const EMBED_MODEL := "gonzo-embed"

var _model := ""
var _runs := 4
var _skip := 0
var _pairs: Array[Dictionary] = []
var _http: HTTPRequest
var _cache := {}
var _embed_ms: Array[float] = []
var _fail_open := 0


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

	# Prove the embedder answers before spending an hour on generation.
	var probe := await _embed("search_query: probe", true)
	if probe.size() != E.DIMENSION:
		printerr("embedder returned %d dims, expected %d -- refusing to run"
			% [probe.size(), E.DIMENSION])
		printerr("load it CPU-only first (see docs/EXPERIMENT_EMBEDDING.md)")
		quit(2)
		return

	print("=== paired embedding tournament (E0 distance vs E1 nomic) ===")
	print("chat model: %s" % _model)
	print("embedder:   %s  (%d dims)" % [EMBED_MODEL, probe.size()])

	var files := _transcripts()
	if files.is_empty():
		printerr("no transcripts in %s" % TRANSCRIPT_DIR)
		quit(2)
		return

	_load_results()
	if not _pairs.is_empty():
		print("resuming with %d opportunities already recorded" % _pairs.size())

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


## Identical generation settings on both arms; anything that differed would
## confound the only intended difference.
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


## Returns an empty vector on ANY failure. Callers fall open to distance.
func _embed(text: String, quiet: bool = false) -> PackedFloat32Array:
	var done := [false]
	var out := [PackedFloat32Array()]
	var t0 := Time.get_ticks_msec()
	_http.request_completed.connect(
		func(_r: int, code: int, _h, body: PackedByteArray):
			if code == 200:
				out[0] = E.parse_response(body.get_string_from_utf8())
			done[0] = true, CONNECT_ONE_SHOT)
	var payload := {"model": EMBED_MODEL, "input": text}
	if _http.request(LM_BASE + "/embeddings",
			["Content-Type: application/json"], HTTPClient.METHOD_POST,
			JSON.stringify(payload)) != OK:
		return PackedFloat32Array()
	var waited := 0
	while not done[0] and waited < 12000:
		await process_frame
		waited += 1
	if not quiet:
		_embed_ms.append(float(Time.get_ticks_msec() - t0))
	return out[0]


## Embed a scar ONCE. Scar text is immutable, so its vector is immutable.
func _scar_vector(scar: Dictionary) -> Dictionary:
	var text := str(scar["excerpt"])
	var turn := int(scar["source_turn"])
	var key := "%d:%s" % [turn, E.text_hash(text)]
	if _cache.has(key) and E.valid(_cache[key], turn, text):
		return _cache[key]
	var v := await _embed(E.DOC_PREFIX + text)
	if v.size() != E.DIMENSION:
		return {}
	var entry := E.stamp(v, turn, text)
	_cache[key] = entry
	return entry


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


## Rebuilt exactly as the arena would have, via the shipped helpers.
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

		# Shared eligible pool, then the shared shortlist by distance. Both
		# arms choose from THIS list, so the pool cannot confound the result.
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

		var e0_pick: Dictionary = shortlist[0]

		# E1: embed the moment as a QUERY, each scar as a DOCUMENT.
		var qv := await _embed(E.QUERY_PREFIX + recent.strip_edges())
		var cached: Array = []
		for s in shortlist:
			cached.append(await _scar_vector(s))
		var idx := E.best_index(qv, cached)
		if idx < 0:
			# Fail open: the embedder could not answer, so distance stands.
			_fail_open += 1
			idx = 0
		var e1_pick: Dictionary = shortlist[idx]

		var diverged := int(e0_pick["source_turn"]) != int(e1_pick["source_turn"])

		var sys := ("You are %s in a live debate arena. Reply in two sentences, "
			+ "in character.") % str(t["speaker"])
		var user := "Recent turns:\n" + recent.strip_edges() + "\n\nRespond as %s." % str(t["speaker"])

		var e0_text := await _ask(sys + "\n\n" + G.render(e0_pick), user)
		var e1_text := await _ask(sys + "\n\n" + G.render(e1_pick), user)

		# THE PLACEBO ARM. No memory injected at all -- the model cannot
		# possibly be engaging a scar it was never shown. Its reply is then
		# scored against both picks anyway.
		#
		# This exists because the first smoke run returned +50 points, which is
		# an order of magnitude larger than any effect this project has ever
		# measured, and large effects are usually broken instruments.
		#
		# The suspected mechanism: _is_callback rewards shared content words
		# between the excerpt and the reply. E1 selects the scar most similar
		# to the recent context, and the reply is GENERATED from that same
		# recent context, so E1's excerpt is word-similar to the reply whether
		# or not the memory was used at all.
		#
		# If placebo "conversion" against the E1 pick is also high, the metric
		# is measuring topical overlap, not memory engagement, and the headline
		# number is an artifact.
		var none_text := await _ask(sys, user)
		if e0_text == "" or e1_text == "" or none_text == "":
			continue

		_pairs.append({
			"turn": now,
			"diverged": diverged,
			"e0_ok": _is_callback(e0_pick, e0_text, history),
			"e1_ok": _is_callback(e1_pick, e1_text, history),
			"placebo_e0_ok": _is_callback(e0_pick, none_text, history),
			"placebo_e1_ok": _is_callback(e1_pick, none_text, history),
			"e0_dist": now - int(e0_pick["source_turn"]),
			"e1_dist": now - int(e1_pick["source_turn"]),
			"e0_unsupported": not G.provenance_holds(e0_pick, history),
			"e1_unsupported": not G.provenance_holds(e1_pick, history),
		})
		if _pairs.size() % 10 == 0:
			var dv := 0
			for p in _pairs:
				if p["diverged"]:
					dv += 1
			print("   %d opportunities (%d diverged)" % [_pairs.size(), dv])


## The frozen callback definition, unchanged from the resonance tournament:
## provenance valid, engages the recalled material, novel language beyond the
## excerpt, and not a verbatim repetition. This does not get adjusted because
## embeddings started looking prettier.
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
		_fail_open = int(p.get("fail_open", 0))
		for row in p.get("pairs", []):
			_pairs.append(row)


func _save_results() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.WRITE)
	if fh == null:
		return
	var med := 0.0
	if not _embed_ms.is_empty():
		var s := _embed_ms.duplicate()
		s.sort()
		med = s[s.size() / 2]
	fh.store_string(JSON.stringify({
		"pairs": _pairs, "fail_open": _fail_open, "model": _model,
		"embed_model": EMBED_MODEL, "median_embed_ms": med}, "\t"))
	fh.close()


func _conv(rows: Array, key: String) -> float:
	if rows.is_empty():
		return 0.0
	var ok := 0
	for p in rows:
		if p[key]:
			ok += 1
	return 100.0 * float(ok) / float(rows.size())


func _report() -> void:
	var n := _pairs.size()
	if n == 0:
		print("\nno paired opportunities found")
		quit(1)
		return

	var div: Array = []
	var same: Array = []
	var unsupported := 0
	for p in _pairs:
		if p["diverged"]:
			div.append(p)
		else:
			same.append(p)
		if p["e0_unsupported"] or p["e1_unsupported"]:
			unsupported += 1

	var e0 := _conv(_pairs, "e0_ok")
	var e1 := _conv(_pairs, "e1_ok")
	var overall := e1 - e0

	print("\n--- %d paired opportunities ---" % n)
	print("  selection divergence: %d of %d (%.1f%%)"
		% [div.size(), n, 100.0 * float(div.size()) / float(n)])
	print("\n  OVERALL")
	print("    E0 distance %5.1f%%    E1 nomic %5.1f%%    E1-E0 = %+.1f points"
		% [e0, e1, overall])

	# The placebo arm decides whether any of the above means anything.
	if _pairs[0].has("placebo_e1_ok"):
		var p0 := _conv(_pairs, "placebo_e0_ok")
		var p1 := _conv(_pairs, "placebo_e1_ok")
		print("\n  PLACEBO (reply generated with NO memory injected)")
		print("    scored against E0 pick %5.1f%%    against E1 pick %5.1f%%" % [p0, p1])
		print("    a reply that never saw a scar cannot call back to it, so")
		print("    these are the false-positive rates of the callback metric.")
		print("    TRUE EFFECT  E0 %+.1f    E1 %+.1f  (arm minus its own placebo)"
			% [e0 - p0, e1 - p1])
		print("    honest delta: %+.1f points" % ((e1 - p1) - (e0 - p0)))
		if p1 - p0 > 10.0:
			print("    !! the metric favours the E1 pick by %+.1f points with NO"
				% (p1 - p0))
			print("       memory present. The headline number is contaminated.")

	# The null control: same scar injected on both arms, so any gap here is
	# pure sampling noise. A result must clear this to mean anything.
	if not same.is_empty():
		var noise := _conv(same, "e1_ok") - _conv(same, "e0_ok")
		print("\n  NULL CONTROL (%d opportunities where both rules agreed)" % same.size())
		print("    same scar both arms: E0 %5.1f%%  E1 %5.1f%%  gap %+.1f points"
			% [_conv(same, "e0_ok"), _conv(same, "e1_ok"), noise])
		print("    ^ this gap is sampling noise. Any real effect must exceed it.")

	if not div.is_empty():
		var div_delta := _conv(div, "e1_ok") - _conv(div, "e0_ok")
		print("\n  WHERE THEY DISAGREED (%d opportunities)" % div.size())
		print("    E0 %5.1f%%    E1 %5.1f%%    delta %+.1f points"
			% [_conv(div, "e0_ok"), _conv(div, "e1_ok"), div_delta])
	else:
		print("\n  the two rules never disagreed -- nomic is expensive agreement")

	var dd := 0
	var ed := 0
	for p in _pairs:
		dd += int(p["e0_dist"])
		ed += int(p["e1_dist"])
	print("\n  mean source distance: E0 %.1f  E1 %.1f"
		% [float(dd) / float(n), float(ed) / float(n)])
	print("  unsupported attribution: %d" % unsupported)
	print("  fail-open events (embedder could not answer): %d" % _fail_open)
	if not _embed_ms.is_empty():
		var s := _embed_ms.duplicate()
		s.sort()
		print("  embed latency: median %.0f ms  p90 %.0f ms  (budget 150 / 100 ms)"
			% [s[s.size() / 2], s[int(float(s.size()) * 0.9)]])

	# Batches over the whole sequence, as pre-registered.
	var q := maxi(n / 4, 1)
	var wins := 0
	print("\n  batches of %d:" % q)
	for b in 4:
		var lo := b * q
		var hi := mini(lo + q, n)
		if lo >= hi:
			continue
		var rows := _pairs.slice(lo, hi)
		var bv0 := _conv(rows, "e0_ok")
		var bv1 := _conv(rows, "e1_ok")
		if bv1 > bv0:
			wins += 1
		print("    batch %d  E0 %5.1f%%  E1 %5.1f%%  %s" % [b + 1, bv0, bv1,
			"E1" if bv1 > bv0 else ("E0" if bv0 > bv1 else "tie")])
	print("  E1 wins %d of 4 batches" % wins)

	print("\nFROZEN DECISION (docs/EXPERIMENT_EMBEDDING.md)")
	if n < 120:
		print("  NOT YET DECIDABLE - %d of the pre-registered 120 opportunities" % n)
		print("  (the resonance run read as +5.0, then +7.4, then -3.9 on the same")
		print("   experiment. Reading this early is how that happens.)")
		quit(0)
		return
	if overall >= 10.0 and wins >= 3 and unsupported == 0:
		print("  KEEP THE EMBEDDING ROUTER")
	elif overall < 5.0:
		print("  REJECT - delete the embedding router")
	else:
		print("  INCONCLUSIVE - not shipped, question closes")
	quit(0)
