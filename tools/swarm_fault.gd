extends SceneTree

## SWARM-F: does the blind swarm keep allocating when agents vanish or return?
##
##   godot --headless --path . --script tools/swarm_fault.gd -- --breach
##   godot --headless --path . --script tools/swarm_fault.gd -- --dry
##   godot --headless --path . --script tools/swarm_fault.gd -- --run
##
## Pre-registered in docs/EXPERIMENT_SWARM_F.md at 59dd514, amended at 86959a9,
## both before this file existed and before any match was run.
##
## NOTHING IN THE MECHANISM MOVES. Same bid function, same resolver, same
## abstention floor, same FAIR_SHARE, same temperature 0. The only new code is a
## fault injector that decides WHICH agents exist on a given turn, and it is
## deliberately dumb: a schedule of roster membership indexed by turn, with no
## awareness of what anyone said.
##
## THE INJECTOR NEVER TOUCHES THE RESOLVER. Removing an agent means it is not
## asked for a bid. It does not mean the resolver learns that a removal
## happened, and there is no "degraded mode" anywhere in the allocation path.
## The substrate is not owed the difference between an agent that abstained and
## an agent that no longer exists -- that is the entire architecture, tested
## under the one condition most likely to tempt someone into breaking it.
##
## --breach IS THE POSITIVE CONTROL AND IT COSTS NO GPU. Rule 6: a control must
## detect its own failure. F5 cannot be that control because `named_recently` may
## rescue it, so the control is instead a constructed failure -- an empty bid
## list and an all-ineligible list -- which MUST produce NO_BIDS and
## NO_ELIGIBLE_BIDS and MUST increment the counter the live harness reads. If a
## failure built to occur is not reported, a clean sheet from F0-F4 means
## nothing.
##
## --dry TESTS THE PAPER PREDICTION WITHOUT GENERATION. The derived collapse
## curve (3/2/1/0 bidders at n=5/4/3/2) assumes no direct address, and a dry run
## has no text, so `named_recently` is false everywhere by construction. That
## makes the dry run the idealised curve, exactly. The GPU run then shows how far
## real dialogue -- where agents name each other -- moves it.

const B := preload("res://scripts/arena/swarm_bid.gd")
const R := preload("res://scripts/arena/swarm_resolver.gd")

var LM_BASE := LMEndpoint.base_url()
const TRANSCRIPT_DIR := "user://live_matches"
const MODEL := "h2o-danube3-4b-chat"
const MAX_TOKENS := 110

## 40, not 30. AIRTIME_WINDOW is 20, so a scoring region holding no
## pre-perturbation history requires the match to outlast the window.
const MATCH_TURNS := 40
const SEED_TURNS := 8
const AIRTIME_WINDOW := 20
const NAMED_WINDOW := 3

## Turns 20-39 inclusive: the airtime window contains only post-perturbation
## history from turn 20 onward.
const SCORE_FROM := 20

const MATCHES := 20
const ARMS := ["F0", "F1", "F2", "F3", "F4", "F5"]

## Statistic 3 (bidder count against the derived prediction) applies ONLY
## where the roster is fixed from turn 0. The prediction is an even-rotation
## steady state; F3 and F4 are deliberately transient, so a mismatch there is
## the perturbation working, not the policy failing. Reported, never scored.
const STEADY_ARMS := ["F0", "F1", "F2", "F5"]

const F3_START := 10        ## intermittent silence begins
const F3_PERIOD := 5        ## 5 turns off, 5 on, repeating
const F4_OUT := 10          ## agent removed
const F4_BACK := 20         ## agent rejoins, 20 turns of observation remain

const RESULTS := "user://swarm_f.json"

## Derived in docs/EXPERIMENT_SWARM_F.md before any run, from the frozen policy
## at even rotation with no naming. Indexed by active roster size.
const PREDICTED_BIDDERS := {5: 3, 4: 2, 3: 1, 2: 0}

var _http: HTTPRequest
var _mode := ""
var _rows: Array[Dictionary] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a) == "--breach":
			_mode = "breach"
		if str(a) == "--dry":
			_mode = "dry"
		if str(a) == "--run":
			_mode = "run"
	if _mode == "":
		printerr("need one of --breach, --dry, --run")
		quit(2)
		return

	if _mode == "breach":
		_breach()
		return

	var files := _transcripts()
	if files.is_empty():
		printerr("no transcripts in %s for match seeds" % TRANSCRIPT_DIR)
		quit(2)
		return

	if _mode == "dry":
		await _dry(files)
		return

	_http = HTTPRequest.new()
	get_root().add_child(_http)
	await process_frame
	_http.timeout = 180.0

	if not await _model_available():
		printerr("model not available from LM Studio: %s" % MODEL)
		quit(2)
		return
	if files.size() < MATCHES:
		printerr("need at least %d transcripts, have %d" % [MATCHES, files.size()])
		quit(2)
		return

	print("warming the model (discarded generation)...")
	var warm := await _ask("warmup", [{"turn": 0, "speaker": "warmup", "text": "hello"}])
	if warm == "":
		printerr("warm-up generation failed; is %s loaded?" % MODEL)
		quit(2)
		return

	await _live(files)


# ----------------------------------------------------- the positive control

## Constructed failures the resolver MUST report. No generation, no roster, no
## schedule -- if this cannot go red, nothing downstream is evidence.
func _breach() -> void:
	print("=== SWARM-F positive control: constructed resolver failures ===\n")
	var bad := 0

	var empty: Dictionary = R.resolve([])
	print("  empty bid list          -> ok=%s code=%s"
		% [str(empty.get("ok", false)), str(empty.get("code", "-"))])
	if bool(empty.get("ok", false)) or str(empty.get("code", "")) != "NO_BIDS":
		printerr("  FAIL: an empty bid list must produce NO_BIDS")
		bad += 1

	# NORMAL declared explicitly: requested_class became mandatory with
	# METABOLISM-A. The class is validated and never acted on, so these
	# constructed failures test exactly what they tested before.
	var none_eligible: Dictionary = R.resolve([
		{"agent_id": "a", "eligible": false, "bid": 0.9,
			"requested_class": "NORMAL"},
		{"agent_id": "b", "eligible": false, "bid": 0.8,
			"requested_class": "NORMAL"},
	])
	print("  all entries ineligible  -> ok=%s code=%s"
		% [str(none_eligible.get("ok", false)), str(none_eligible.get("code", "-"))])
	if bool(none_eligible.get("ok", false)) \
			or str(none_eligible.get("code", "")) != "NO_ELIGIBLE_BIDS":
		printerr("  FAIL: an all-ineligible list must produce NO_ELIGIBLE_BIDS")
		bad += 1

	# The counter the live harness reads must move for a constructed failure,
	# by the same code path the live harness uses.
	var failures := _new_failures()
	_record_failure(failures, empty)
	_record_failure(failures, none_eligible)
	print("  counters after 2 breaches -> NO_BIDS=%d NO_ELIGIBLE_BIDS=%d FALLBACK_WAKES=%d"
		% [int(failures["NO_BIDS"]), int(failures["NO_ELIGIBLE_BIDS"]),
			int(failures["FALLBACK_WAKES"])])
	if int(failures["FALLBACK_WAKES"]) != 2:
		printerr("  FAIL: the fallback counter did not move for constructed failures")
		bad += 1

	# And a well-formed list must still succeed, or the control proves only that
	# the resolver refuses everything.
	var good: Dictionary = R.resolve([
		{"agent_id": "a", "eligible": true, "bid": 0.2,
			"requested_class": "NORMAL"},
		{"agent_id": "b", "eligible": true, "bid": 0.5,
			"requested_class": "NORMAL"},
	])
	print("  well-formed list        -> ok=%s agent=%s"
		% [str(good.get("ok", false)), str(good.get("agent_id", "-"))])
	if not bool(good.get("ok", false)) or str(good.get("agent_id", "")) != "b":
		printerr("  FAIL: a well-formed list must still allocate to the top bid")
		bad += 1

	if bad > 0:
		printerr("\nBREACH CONTROL FAILED. No SWARM-F arm is interpretable.")
		quit(1)
		return
	print("\n  BREACH CONTROL OK - constructed failures are reported.")
	quit(0)


# ------------------------------------------------------------ fault injector

## Which agents exist on this turn? Membership only. The injector is never told
## what anybody said and never speaks to the resolver.
func _active(arm: String, roster: Array, t: int) -> Array:
	match arm:
		"F0":
			return roster
		"F1":
			return roster.slice(0, roster.size() - 1)
		"F2":
			return roster.slice(0, roster.size() - 2)
		"F5":
			return roster.slice(0, 2)
		"F3":
			if t < F3_START:
				return roster
			# 5 off, 5 on, repeating, starting with off.
			var phase := int((t - F3_START) / F3_PERIOD) % 2
			return roster if phase == 1 else roster.slice(0, roster.size() - 1)
		"F4":
			if t >= F4_OUT and t < F4_BACK:
				return roster.slice(0, roster.size() - 1)
			return roster
	return roster


## Turns at which an agent DISAPPEARS, for statistic 4.
func _is_dropout(arm: String, t: int) -> bool:
	if arm == "F4":
		return t == F4_OUT
	if arm == "F3" and t >= F3_START:
		return (t - F3_START) % (F3_PERIOD * 2) == 0
	return false


## Turns at which an agent RETURNS, for statistic 5.
func _is_rejoin(arm: String, t: int) -> bool:
	if arm == "F4":
		return t == F4_BACK
	if arm == "F3" and t >= F3_START:
		return (t - F3_START) % (F3_PERIOD * 2) == F3_PERIOD
	return false


# ------------------------------------------------------------- playing one

func _play(path: String, arm: String, match_index: int, live: bool) -> Dictionary:
	var seed_turns := _load_turns(path)
	if seed_turns.size() < SEED_TURNS + 2:
		return {}

	var roster := _roster(seed_turns)
	if roster.size() < 5:
		return {}

	var history: Array = seed_turns.slice(0, SEED_TURNS)
	var speakers: Array = []
	var codes: Array = []
	var bidder_counts: Array = []
	var active_sizes: Array = []
	var failures := _new_failures()
	var stat4_violations := 0
	var stat5_violations := 0
	var pending_dropout := false

	for t in MATCH_TURNS:
		var active := _active(arm, roster, t)
		var prev := str(history[history.size() - 1]["speaker"])

		# Statistic 5 is decided on the rejoin turn itself: the returning agent's
		# first eligible turn is the turn it comes back, not the one after.
		var returner_now := ""
		if _is_rejoin(arm, t):
			var r := str(roster[roster.size() - 1])
			if r != prev:
				returner_now = r

		var eligible: Array = []
		var bids: Array = []
		for agent_v in active:
			var agent := str(agent_v)
			if agent == prev:
				continue
			eligible.append(agent)
			var view := _local_view(agent, history)
			if B.should_bid(view):
				var b := B.compute(view)
				# NORMAL: SWARM-F ran one model with no escalation. See the note
				# in swarm_match.gd -- the class is validated and never acted on,
				# so the recorded allocations are unchanged.
				bids.append({"agent_id": agent, "eligible": true, "bid": b,
					"requested_class": "NORMAL"})

		bidder_counts.append(bids.size())
		active_sizes.append(active.size())

		var next_speaker := ""
		var out: Dictionary = R.resolve(bids)
		if bool(out.get("ok", false)):
			next_speaker = str(out["agent_id"])
			codes.append("OK")
		else:
			_record_failure(failures, out)
			codes.append(str(out.get("code", "?")))
			# Fallback authority. It must route within the ACTIVE roster: handing
			# the slot to an agent that does not exist would be the injector
			# leaking into the allocation path.
			next_speaker = _fallback(active, prev)

		# Statistic 4: after a dropout, allocation must resume on the next turn.
		if pending_dropout:
			if codes[codes.size() - 1] != "OK":
				stat4_violations += 1
			pending_dropout = false
		if _is_dropout(arm, t):
			pending_dropout = true

		# Statistic 5: a returning agent must win its first eligible turn.
		if returner_now != "" and next_speaker != returner_now:
			stat5_violations += 1

		var reply := ""
		if live:
			reply = await _ask(next_speaker, history)
			if reply == "":
				failures["REQUEST_FAILED"] = int(failures["REQUEST_FAILED"]) + 1
				break
		else:
			# No text at all, so `named_recently` is false everywhere and the
			# dry run measures the idealised curve by construction.
			reply = "."

		history.append({"turn": SEED_TURNS + t, "speaker": next_speaker, "text": reply})
		speakers.append(next_speaker)

	return {
		"arm": arm, "match": match_index,
		"speakers": ",".join(PackedStringArray(speakers)),
		"codes": ",".join(PackedStringArray(codes)),
		"bidder_counts": bidder_counts,
		"active_sizes": active_sizes,
		"failures": failures,
		"stat4_violations": stat4_violations,
		"stat5_violations": stat5_violations,
		"max_silence": _max_silence(speakers, _always_active(arm, roster)),
	}


## The cage, woken only because nothing else could act. Next in the ACTIVE
## roster after `prev`, which is round-robin over whoever still exists.
func _fallback(active: Array, prev: String) -> String:
	if active.is_empty():
		return prev
	var i := active.find(prev)
	if i == -1:
		return str(active[0])
	return str(active[(i + 1) % active.size()])


## Agents present for the whole match, so statistic 6 is not computed over an
## agent that was deliberately removed.
func _always_active(arm: String, roster: Array) -> Array:
	match arm:
		"F1", "F3", "F4":
			return roster.slice(0, roster.size() - 1)
		"F2":
			return roster.slice(0, roster.size() - 2)
		"F5":
			return roster.slice(0, 2)
	return roster


func _new_failures() -> Dictionary:
	return {"NO_BIDS": 0, "NO_ELIGIBLE_BIDS": 0, "MALFORMED_BID": 0,
		"FALLBACK_WAKES": 0, "REQUEST_FAILED": 0}


func _record_failure(failures: Dictionary, out: Dictionary) -> void:
	var code := str(out.get("code", "?"))
	failures[code] = int(failures.get(code, 0)) + 1
	failures["FALLBACK_WAKES"] = int(failures["FALLBACK_WAKES"]) + 1


# ------------------------------------------------------------------- runners

func _dry(files: Array) -> void:
	print("=== SWARM-F dry run: schedule and idealised bid curve, NO generation ===")
	print("no text is produced, so named_recently is false everywhere and this")
	print("is the paper prediction measured directly.\n")
	for arm in ARMS:
		var row := await _play(str(files[0]), str(arm), 0, false)
		if row.is_empty():
			printerr("dry run could not seed from %s" % str(files[0]))
			quit(2)
			return
		_rows.append(row)
		_report_arm(row)
	_verdict_dry()


func _live(files: Array) -> void:
	_load()
	print("=== SWARM-F: %d arms x %d matches x %d turns ===\n"
		% [ARMS.size(), MATCHES, MATCH_TURNS])
	for arm in ARMS:
		for m in MATCHES:
			if _recorded(str(arm), m):
				continue
			var row := await _play(str(files[m]), str(arm), m, true)
			if row.is_empty():
				continue
			_rows.append(row)
			_save()
			print("  %s match %d/%d: bidders median %.1f, fallback wakes %d"
				% [str(arm), m + 1, MATCHES, _median(row["bidder_counts"]),
					int((row["failures"] as Dictionary)["FALLBACK_WAKES"])])
	_report_live()


func _recorded(arm: String, match_index: int) -> bool:
	for r in _rows:
		if str(r["arm"]) == arm and int(r["match"]) == match_index:
			return true
	return false


# ----------------------------------------------------------------- reporting

func _report_arm(row: Dictionary) -> void:
	var arm := str(row["arm"])
	var sizes: Array = row["active_sizes"]
	var counts: Array = row["bidder_counts"]
	var scored_obs := {}
	var mismatches := 0
	for i in counts.size():
		if i < SCORE_FROM:
			continue
		var n := int(sizes[i])
		var got := int(counts[i])
		var key := "n=%d" % n
		if not scored_obs.has(key):
			scored_obs[key] = {}
		var seen: Dictionary = scored_obs[key]
		seen[got] = int(seen.get(got, 0)) + 1
		if PREDICTED_BIDDERS.has(n) and got != int(PREDICTED_BIDDERS[n]):
			mismatches += 1
	var f: Dictionary = row["failures"]
	print("  %s  active sizes %s" % [arm, str(_distinct(sizes))])
	print("      bidders on scored turns: %s" % str(scored_obs))
	var tag := "" if STEADY_ARMS.has(arm) else "  (descriptive: transient arm)"
	print("      mismatches vs prediction: %d%s    fallback wakes: %d    NO_BIDS: %d"
		% [mismatches, tag, int(f["FALLBACK_WAKES"]), int(f["NO_BIDS"])])
	print("      stat4 %d   stat5 %d   max silence %d"
		% [int(row["stat4_violations"]), int(row["stat5_violations"]),
			int(row["max_silence"])])


func _verdict_dry() -> void:
	print("\n--- dry-run schedule check ---\n")
	var bad := 0
	for row in _rows:
		var arm := str(row["arm"])
		var sizes := _distinct(row["active_sizes"])
		var want: Array = []
		match arm:
			"F0": want = [5]
			"F1": want = [4]
			"F2": want = [3]
			"F5": want = [2]
			"F3": want = [4, 5]
			"F4": want = [4, 5]
		if str(sizes) != str(want):
			printerr("  FAIL %s: active sizes %s, expected %s"
				% [arm, str(sizes), str(want)])
			bad += 1
	if bad > 0:
		printerr("\nSCHEDULE WRONG. Do not spend GPU time on this.")
		quit(1)
		return
	print("  schedule OK: every arm held the roster sizes its design requires.")
	print("  read the bidder rows above against 5->3, 4->2, 3->1, 2->0.")
	quit(0)


func _report_live() -> void:
	print("\n--- SWARM-F ---\n")
	for arm in ARMS:
		var counts: Array = []
		var mism := 0
		var scored := 0
		var wakes := 0
		var nb := 0
		var mal := 0
		var s4 := 0
		var s5 := 0
		var sil: Array = []
		var n_matches := 0
		for r in _rows:
			if str(r["arm"]) != arm:
				continue
			n_matches += 1
			var sizes: Array = r["active_sizes"]
			var bc: Array = r["bidder_counts"]
			for i in bc.size():
				if i < SCORE_FROM:
					continue
				scored += 1
				counts.append(int(bc[i]))
				var n := int(sizes[i])
				if PREDICTED_BIDDERS.has(n) and int(bc[i]) != int(PREDICTED_BIDDERS[n]):
					mism += 1
			var f: Dictionary = r["failures"]
			wakes += int(f["FALLBACK_WAKES"])
			nb += int(f["NO_BIDS"])
			mal += int(f["MALFORMED_BID"])
			s4 += int(r["stat4_violations"])
			s5 += int(r["stat5_violations"])
			sil.append(int(r["max_silence"]))
		if n_matches == 0:
			continue
		var turns := n_matches * MATCH_TURNS
		print("  %s  %d matches" % [arm, n_matches])
		print("      mean bidders on scored turns  %.2f   (%d scored)"
			% [_mean(counts), scored])
		print("      mismatches vs prediction      %d%s"
			% [mism, "" if STEADY_ARMS.has(arm) else "   (descriptive, not scored)"])
		print("      MALFORMED_BID (stat 1)        %d" % mal)
		print("      fallback wakes (stat 2)       %d of %d turns  (%.1f%%)"
			% [wakes, turns, 100.0 * float(wakes) / float(maxi(turns, 1))])
		print("      NO_BIDS                       %d" % nb)
		print("      stat4 / stat5 violations      %d / %d" % [s4, s5])
		print("      max consecutive silence       %d" % _max_of(sil))
	print("\n  S (from F0 only) = %d" % _s_from_f0())
	print("\n  Read against docs/EXPERIMENT_SWARM_F.md. No bar is moved here.")
	quit(0)


func _s_from_f0() -> int:
	var sil: Array = []
	for r in _rows:
		if str(r["arm"]) == "F0":
			sil.append(int(r["max_silence"]))
	return _max_of(sil)


# --------------------------------------------------------------- local views

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


# --------------------------------------------------------------------- stats

func _max_silence(speakers: Array, watched: Array) -> int:
	var worst := 0
	for agent in watched:
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


func _distinct(values: Array) -> Array:
	var seen := {}
	for v in values:
		seen[int(v)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


func _max_of(values: Array) -> int:
	var m := 0
	for v in values:
		m = maxi(m, int(v))
	return m


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	var n := v.size()
	if n % 2 == 1:
		return float(v[n / 2])
	return (float(v[n / 2 - 1]) + float(v[n / 2])) / 2.0


# ---------------------------------------------------------------- generation

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


func _load() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.READ)
	if fh == null:
		return
	var p = JSON.parse_string(fh.get_as_text())
	fh.close()
	if typeof(p) == TYPE_DICTIONARY:
		for row in p.get("rows", []):
			_rows.append(row)


func _save() -> void:
	var fh := FileAccess.open(RESULTS, FileAccess.WRITE)
	if fh == null:
		return
	fh.store_string(JSON.stringify({"rows": _rows}, "\t"))
	fh.close()
