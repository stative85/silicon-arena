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
## preload, not the `TurnOrder` global class name: global classes are only
## registered by an editor import, so a headless tool run from a fresh clone
## would not see it. This repo has already shipped that bug once.
const TurnOrderScript := preload("res://scripts/arena/turn_order.gd")
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

## BALANCED mode: N agents over M distinct models, grouped so each model is
## loaded once per round.
##
## The diverse roster and --fast are the two ends of one dial and nothing sat
## between them. Cost per round is dominated by cold loads (18-38s) rather than
## inference (0.06-0.26s), and TurnOrder shows a grouped roster pays exactly
## one load per DISTINCT model per round. So swaps scale with the number of
## models, not the number of agents:
##
##   5 agents,  5 models  ->  5 loads/round   ~150s   (diverse: max variety)
##   5 agents,  2 models  ->  2 loads/round    ~60s   (balanced: 2.5x faster)
##   5 agents,  1 model   ->  1 load/round     ~30s   (--fast: no variety)
##
## Balanced keeps genuinely different architectures arguing while cutting most
## of the waiting. Two models is the default because it is the smallest roster
## that is still heterogeneous.
##
##   godot --headless --path . --script tools/build_roster.gd -- --balanced
##   godot --headless --path . --script tools/build_roster.gd -- --balanced=3
var _balanced := 0

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
		elif a == "--balanced":
			_balanced = 2
		elif a.begins_with("--balanced="):
			# Clamp rather than trust: 1 is --fast and WANTED is the diverse
			# roster, so anything outside that range is a typo, not a request.
			_balanced = clampi(int(a.get_slice("=", 1)), 1, WANTED)
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
	# How many DISTINCT models this roster should use. That number, not the
	# agent count, is what a round costs in cold loads (see TurnOrder).
	var want_distinct := WANTED
	if _fast:
		want_distinct = 1
	elif _balanced > 0:
		want_distinct = _balanced

	if _probe:
		picked = await _probe_pick(legal, want_distinct)
		if want_distinct < WANTED and not picked.is_empty():
			picked = _spread(picked, WANTED)
	elif want_distinct < WANTED:
		# Fewer models than agents. Personas differ; weights move rarely.
		var best := _pick_diverse(legal, want_distinct)
		if best.is_empty():
			printerr("no usable model found")
			quit(1)
			return
		picked = _spread(best, WANTED)
	else:
		picked = _pick_diverse(legal, WANTED)

	if picked.size() < WANTED:
		print("\nOnly %d eligible model(s) available; the arena wants %d." % [picked.size(), WANTED])
		print("Building a %d-agent roster instead of failing. Download more small models" % picked.size())
		print("to fill the roster out.")

	# Group before naming, so the numbering a viewer reads runs 1,2,3 down the
	# roster instead of jumping around after the reorder.
	var pre: Array = []
	for i in picked.size():
		pre.append({"model": picked[i]})
	var before_swaps := TurnOrderScript.swaps_per_round(pre)
	pre = TurnOrderScript.group_by_model(pre)

	# Number only models that actually repeat. A roster of distinct models
	# should not gain meaningless "#1" suffixes.
	var counts := {}
	for a in pre:
		counts[a["model"]] = int(counts.get(a["model"], 0)) + 1
	var seen := {}
	var roster: Array = []
	for i in pre.size():
		var id: String = pre[i]["model"]
		var nm := _display_name(id)
		if int(counts[id]) > 1:
			seen[id] = int(seen.get(id, 0)) + 1
			# Distinct identities so the arena still reads as five agents.
			nm = "%s #%d" % [nm, int(seen[id])]
		roster.append({
			"color": COLORS[i % COLORS.size()],
			"model": id,
			"name": nm,
		})

	print("
roster:")
	for a in roster:
		print("   %-18s %s" % [a["name"], a["model"]])

	var swaps := TurnOrderScript.swaps_per_round(roster)
	var distinct := TurnOrderScript.distinct_models(roster)
	print("
%d agents, %d distinct model(s), %d cold load(s) per round."
		% [roster.size(), distinct, swaps])
	if before_swaps > swaps:
		print("Ordering saved %d cold load(s) per round (%d -> %d) by grouping"
			% [before_swaps - swaps, before_swaps, swaps])
		print("agents that share a model. Same agents, same models, cheaper cycle.")
	# ~30s median cold swap, ~0.2s warm inference (docs/BENCHMARK_8GB.md).
	print("At the measured ~30s median swap that is roughly %ds of loading per round."
		% (swaps * 30))

	if _fast:
		print("
FAST: all %d agents share one resident model - no turn swaps." % roster.size())
		print("One architecture wearing %d hats. Use --balanced to keep real variety." % roster.size())
	elif _balanced > 0:
		print("
BALANCED: %d architectures across %d agents." % [distinct, roster.size()])
		if swaps >= WANTED:
			# Asking for as many models as agents IS the diverse roster. Say so
			# rather than dressing it up as a saving of 1.0x.
			print("That is one model per agent, which is the default roster with no")
			print("saving at all. Ask for fewer models than agents to buy anything.")
		else:
			print("Roughly %.1fx fewer cold loads per round than a %d-model roster,"
				% [float(WANTED) / float(maxi(swaps, 1)), WANTED])
			print("while still being a genuinely heterogeneous debate.")
	else:
		print("
Every turn changes model, so every turn pays a cold swap (18-38s).")
		print("Run with  -- --balanced  to keep several architectures at a fraction")
		print("of the loading, or  -- --fast  for one resident model and the most turns.")

	_write_user_preset(roster)
	_write_live_roster(roster)
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


## Fill `count` agent slots from a smaller set of models, as evenly as
## possible. Round-robin rather than blocking (A B A B A, not A A A B B) so the
## remainder lands on the earliest — that is, the highest-ranked — models. The
## caller groups afterwards, so the interleaving here costs nothing and keeps
## the extra agent on the better model.
func _spread(models: Array[String], count: int) -> Array[String]:
	var out: Array[String] = []
	if models.is_empty():
		return out
	for i in count:
		out.append(models[i % models.size()])
	return out


## Also write the roster the HEADLESS live path reads.
##
## live_match.gd, scar_ladder.gd, scar_ab_probe.gd, scar_table.gd and
## match_scene.gd all read config/arena-roster.v1.json. Nothing in this
## repository produced it: the file was absent and the only other search path
## pointed into a PRIVATE sibling checkout (../extinct_os/), so on a clean
## clone every headless live tool failed with "roster not found". The old
## advice was to "copy user://presets.json" there, which cannot work — the two
## files have different schemas.
##
## Writing both from one selection also keeps them from disagreeing, which is
## the duplicated-truth failure this project has already shipped three times.
func _write_live_roster(roster: Array) -> void:
	if roster.is_empty():
		return
	var agents: Array = []
	for i in roster.size():
		var a: Dictionary = roster[i]
		agents.append({
			"agent_id": "agent-%02d" % (i + 1),
			"display_name": a["name"],
			"model_key": a["model"],
			"runtime_id": "runtime-01",
			"color": "#" + str(a["color"]),
			"persona": "",
		})
	# runtimes[0] is the default any agent without its own model_key inherits.
	# Every agent above carries an explicit key, so a heterogeneous roster
	# survives the round trip rather than collapsing onto one model.
	var first: Dictionary = roster[0]
	var doc := {
		"version": 1,
		"generated_by": "tools/build_roster.gd",
		"runtimes": [{
			"runtime_id": "runtime-01",
			"endpoint": LM_BASE,
			"model_key": first["model"],
			"display_name": first["name"],
			"params_b": _policy.params_from_id(first["model"]) if _policy.has_method("params_from_id") else null,
			"quantization": "",
			"inference": {
				"temperature": 0.8,
				"max_tokens": 110,
				"notes": "generated defaults; tune per model family",
			},
		}],
		"agents": agents,
	}
	var dir := ProjectSettings.globalize_path("res://config")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "res://config/arena-roster.v1.json"
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		printerr("cannot write %s" % path)
		return
	w.store_string(JSON.stringify(doc, "\t"))
	w.close()
	print("wrote %s (%d agents) for the headless live path"
		% [ProjectSettings.globalize_path(path), agents.size()])
