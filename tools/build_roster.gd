extends SceneTree

## Build a legal roster from the models actually installed in LM Studio.
##
##   godot --headless --path . --script tools/build_roster.gd
##
## The shipped presets name portable public models so the repository is not
## tied to one machine. The consequence is that on any given machine most of
## them are not downloaded, and the arena looks broken when it is merely
## pointed at models you do not have.
##
## This writes an "Installed Models" preset into user://presets.json built from
## what this machine really has, with the size law applied BEFORE selection so
## an oversized model can never enter the roster in the first place.
##
## It never touches res://presets.json — the public defaults stay portable.

const PolicyScript := preload("res://scripts/arena/model_policy.gd")
const ClientScript := preload("res://scripts/api/lm_studio_client.gd")

## Single source of truth, overridable via SILICON_ARENA_LM_URL.
var LM_BASE := LMEndpoint.base_url()
const WANTED := 5

## FAST mode: every agent shares ONE model, so no turn ever swaps.
##
## Measured on an RTX 5060 8GB, five distinct models: 7 speeches in 280s, about
## one every 40s, almost all of it weight loading (docs/BENCHMARK_8GB.md puts a
## cold swap at 18-38s and warm inference at 0.06-0.26s). Sharing one model
## trades architectural variety for roughly an order of magnitude more turns.
##
##   godot --headless --path . --script tools/build_roster.gd -- --fast
var _fast := false

## Probe candidates before putting them in the roster.
##
## The catalog cannot tell a reasoning-only model from a normal one:
## chatCapable is null for all 17 reasoning-marked models installed here, and
## name heuristics ("thinking", "-r1", "distill") both over- and under-match.
##
## A build with no probe once selected
## qwen3-4b-instruct-grok-4-fast-brainstorming-distill, which returns HTTP 200
## with empty content and its whole answer in reasoning_content — structurally
## unable to speak in the arena. Measuring beats guessing, at the cost of one
## cold load per candidate.
##
##   --no-probe   skip it and accept the ranked order unverified
var _probe := true
const COLORS := ["c471ed", "3db1ff", "00d2ff", "5ad78c", "ff6b6b"]

var _policy


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--fast":
			_fast = true
		elif a == "--no-probe":
			_probe = false
	print("\n=== build roster from installed models ===\n")
	_policy = PolicyScript.new()
	get_root().add_child(_policy)
	_policy.load_catalog()
	if not _policy.is_loaded():
		printerr("model catalog not loaded — refusing to build a roster blind")
		quit(2)
		return

	var http := HTTPRequest.new()
	get_root().add_child(http)
	await process_frame
	http.timeout = 10.0
	http.request_completed.connect(_on_models)
	if http.request(LM_BASE + "/models") != OK:
		printerr("cannot reach LM Studio at %s — start it and enable the local server" % LM_BASE)
		quit(2)


func _on_models(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		printerr("LM Studio did not answer (result=%d code=%d). Start it, then Developer > Start Server." % [result, code])
		quit(2)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("data"):
		printerr("unexpected /v1/models body")
		quit(2)
		return

	var installed: Array[String] = []
	for m in parsed["data"]:
		installed.append(str(m.get("id", "")))

	# THE LAW FIRST. Selection only ever sees models already permitted, so an
	# oversized or unresolvable id cannot reach the roster by any path.
	var legal: Array[String] = []
	for id in installed:
		if _policy.check(id) == "":
			legal.append(id)

	print("installed: %d    permitted under the %.0fB ceiling: %d"
		% [installed.size(), _policy.MAX_PARAM_B, legal.size()])

	if legal.is_empty():
		printerr("\nNo installed model is permitted under the %.0fB ceiling." % _policy.MAX_PARAM_B)
		printerr("Download a model at or under %.0fB in LM Studio, or regenerate" % _policy.MAX_PARAM_B)
		printerr("config/model-catalog.v1.json from `lms ls --json` if your models are missing from it.")
		quit(1)
		return

	var picked: Array[String] = []
	if _probe:
		picked = await _probe_pick(legal, 1 if _fast else WANTED)
		if _fast and not picked.is_empty():
			var one := picked[0]
			picked = []
			for i in WANTED:
				picked.append(one)
	elif _fast:
		# One model, five agents. Personas differ; weights never move.
		var best := _pick_diverse(legal, 1)
		if best.is_empty():
			printerr("no usable model found")
			quit(1)
			return
		for i in WANTED:
			picked.append(best[0])
	else:
		picked = _pick_diverse(legal, WANTED)

	if picked.size() < WANTED:
		print("\nOnly %d eligible model(s) available; the arena wants %d." % [picked.size(), WANTED])
		print("Building a %d-agent roster instead of failing. Download more small models" % picked.size())
		print("to fill the roster out.")

	var roster: Array = []
	for i in picked.size():
		var nm := _display_name(picked[i])
		if _fast:
			# Distinct identities so the arena still reads as five agents.
			nm = "%s #%d" % [nm, i + 1]
		roster.append({
			"color": COLORS[i % COLORS.size()],
			"model": picked[i],
			"name": nm,
		})

	print("\nroster:")
	for a in roster:
		print("   %-18s %s" % [a["name"], a["model"]])

	if _fast:
		print("
FAST: all %d agents share one resident model — no turn swaps." % roster.size())
	else:
		print("
Every turn changes model, so every turn pays a cold swap (18-38s).")
		print("Run with  -- --fast  for one resident model and far more turns.")
	_write_user_preset(roster)
	quit(0)


## Prefer different model families over five builds of the same one. Family is
## approximated by the leading token of the id, which is crude but good enough
## to avoid a roster of four Britannica variants arguing with themselves.
## Rank, then spread across families.
##
## Alphabetical order alone produced a roster containing a Bhojpuri
## text-to-speech model and two base (non-instruct) checkpoints, all of which
## are legal under the ceiling and useless in a debate. Ranking uses the
## catalog's own evidence rather than the id string where possible.

## Rank, then VERIFY. Each candidate gets one tiny request; only models that
## return actual text are accepted. Costs a cold load per candidate, which is
## why it happens once at setup rather than during a match.
func _probe_pick(legal: Array[String], want: int) -> Array[String]:
	var ranked := _pick_diverse(legal, legal.size())
	var accepted: Array[String] = []
	var rejected := 0

	print("probing candidates (one cold load each, this is the slow part)...")
	for id in ranked:
		if accepted.size() >= want:
			break
		var verdict := await _probe_one(id)
		if verdict == "":
			accepted.append(id)
			print("   speaks   %s" % id)
		else:
			rejected += 1
			print("   rejected %s — %s" % [id, verdict])

	if rejected > 0:
		print("%d candidate(s) rejected because they never produced text." % rejected)
	return accepted


## "" when the model produced usable text, otherwise the reason it did not.
func _probe_one(model_id: String) -> String:
	var http := HTTPRequest.new()
	get_root().add_child(http)
	await process_frame
	http.timeout = 180.0

	var done := [false]
	var reason := ["probe did not complete"]
	http.request_completed.connect(func(r: int, code: int, _h, body: PackedByteArray):
		var raw := body.get_string_from_utf8()
		if r != HTTPRequest.RESULT_SUCCESS or code != 200:
			reason[0] = ClientScript.summarize_error(code, raw)
		else:
			var parsed = JSON.parse_string(raw)
			if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("choices"):
				reason[0] = "unparseable response"
			else:
				var msg = parsed["choices"][0]["message"]
				var text := str(msg.get("content", "")).strip_edges()
				if text != "":
					reason[0] = ""
				elif str(msg.get("reasoning_content", "")).strip_edges() != "":
					reason[0] = "reasoning-only (empty content)"
				elif msg.has("tool_calls"):
					reason[0] = "emits tool calls instead of text"
				else:
					reason[0] = "returned an empty reply"
		done[0] = true)

	var payload := {
		"model": model_id,
		"messages": [{"role": "user", "content": "Say the word: ready"}],
		"max_tokens": 16,
		"temperature": 0.1,
		"stream": false,
	}
	var err := http.request(LM_BASE + "/chat/completions",
		["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		return "could not issue request"

	var waited := 0
	while not done[0] and waited < 12000:
		await process_frame
		waited += 1
	http.queue_free()
	return str(reason[0])


func _pick_diverse(legal: Array[String], want: int) -> Array[String]:
	var scored: Array = []
	for id in legal:
		var sc := _score(id)
		if sc < 0.0:
			continue                     # not a chat model at all
		scored.append({"id": id, "score": sc})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	var out: Array[String] = []
	var seen_family := {}
	# Best of each distinct family first.
	for e in scored:
		if out.size() >= want:
			break
		var fam := _family(e["id"])
		if seen_family.has(fam):
			continue
		seen_family[fam] = true
		out.append(e["id"])
	# Backfill from the ranked list if too few families exist.
	for e in scored:
		if out.size() >= want:
			break
		if not out.has(e["id"]):
			out.append(e["id"])
	return out


func _family(id: String) -> String:
	var tail := id.get_slice("/", id.get_slice_count("/") - 1)
	return tail.split("-")[0]


## Higher is better. Negative means "never put this in a debate roster".
func _score(id: String) -> float:
	var low := id.to_lower()

	# Hard excludes: these are legal under the ceiling but cannot hold a turn.
	for bad in ["tts", "text_to_speech", "text-to-speech", "whisper", "embed",
			"embedding", "reranker", "ocr", "stable-diffusion", "clip-",
			"bge-", "nomic", "vision-encoder"]:
		if low.find(bad) != -1:
			return -1.0

	var s := 0.0
	var m = _policy.catalog_entry(id)
	if m != null:
		if m.get("chatCapable", null) == true:
			s += 100.0
		var p = m.get("paramsB", null)
		if p != null:
			s += float(p) * 5.0          # bigger is generally more capable
		if bool(m.get("vision", false)):
			s -= 10.0                    # vision models tend to be weaker chatters
	# Instruct/chat tuning is the single strongest signal available from the id.
	for good in ["instruct", "-it", "chat", "zephyr", "hermes"]:
		if low.find(good) != -1:
			s += 40.0
			break
	# Base/pretrain checkpoints do not follow turn instructions.
	for base in ["-base", "pretrain", "p2-", "-v1-", "completion"]:
		if low.find(base) != -1:
			s -= 60.0
			break
	return s


func _display_name(model_id: String) -> String:
	var tail := model_id.get_slice("/", model_id.get_slice_count("/") - 1)
	tail = tail.replace("-GGUF", "").replace("_", " ").replace("-", " ")
	var words := tail.split(" ", false)
	var out: Array[String] = []
	for w in words:
		if out.size() >= 3:
			break
		out.append(w.capitalize() if w.length() > 2 else w.to_upper())
	return " ".join(out)


## Appends (or replaces) an "Installed Models" preset in user://presets.json.
## res://presets.json is deliberately never modified.
func _write_user_preset(roster: Array) -> void:
	var path := "user://presets.json"
	var presets: Array = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_ARRAY:
				presets = parsed
	if presets.is_empty():
		# Seed from the shipped defaults so the other presets still exist.
		var rf := FileAccess.open("res://presets.json", FileAccess.READ)
		if rf != null:
			var rp = JSON.parse_string(rf.get_as_text())
			rf.close()
			if typeof(rp) == TYPE_ARRAY:
				presets = rp

	# Slot 0 is what the arena auto-loads, so put the working roster there and
	# keep the shipped ones after it.
	presets.push_front(roster)
	while presets.size() > 8:
		presets.pop_back()

	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		printerr("cannot write %s" % path)
		return
	w.store_string(JSON.stringify(presets, "\t"))
	w.close()
	print("\nwrote %s (slot 0 = Installed Models, %d agents)"
		% [ProjectSettings.globalize_path(path), roster.size()])
	print("Launch the arena; it loads slot 0 automatically.")
