extends SceneTree

## Can local policies allocate the slot, on states the cage produced?
##
##   godot --headless --path . --script tools/swarm_walk.gd -- --runs 10
##
## Pre-registered in docs/EXPERIMENT_SWARM.md at 85d34f2, amended before any
## allocation was recorded.
##
## NO GENERATION. Nothing is executed, no model is loaded, no request is issued.
## Both schedulers only PROPOSE a speaker against real history, and the state
## then advances to the real next turn rather than to either proposal:
##
##     real canonical state at turn t
##       round-robin picks          local agents bid -> blind resolver picks
##       record both.  NEITHER PICK ADVANCES ANYTHING.
##     move to canonical turn t+1
##
## That preserves the pairing every trusted result on this project came from.
## The cost is scope, and the metric names carry it: these are COUNTERFACTUAL
## proposals on cage-generated states. If an agent goes 18 opportunities without
## being proposed, that is a fact about its local policy under this history, not
## a claim that it would starve for 18 turns under a real swarm -- after the
## first divergent allocation its local view would evolve differently. Whole-
## match behaviour is SWARM-B and its data may never be pooled with this.
##
## THREE ARMS, because rule 4 asks what a metric reports when the thing it
## detects is absent:
##
##     CAGE     round-robin over the roster
##     SWARM    bids from each agent's own local view
##     RANDOM   bids carrying no local information, same abstention floor
##
## RANDOM is the placebo. If it diverges from the cage as much as SWARM does and
## concentrates as much, then local information is not what produced the
## behaviour and the bid function is decoration.

const B := preload("res://scripts/arena/swarm_bid.gd")
const R := preload("res://scripts/arena/swarm_resolver.gd")

const TRANSCRIPT_DIR := "user://live_matches"
const RESULTS := "user://swarm_walk.json"
const TARGET := 400

## Window over which an agent accounts for its own airtime.
const AIRTIME_WINDOW := 20
## Window for reporting counterfactual selection concentration.
const CONCENTRATION_WINDOW := 20
## How far back an agent can observe being named.
const NAMED_WINDOW := 3

var _rows: Array[Dictionary] = []
var _runs := 10
var _slice := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a := str(args[i])
		if a == "--runs" and i + 1 < args.size():
			_runs = int(args[i + 1])
		if a == "--slice" and i + 1 < args.size():
			_slice = int(args[i + 1])
		if a == "--reset":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS))

	var files := _transcripts()
	if files.is_empty():
		printerr("no transcripts in %s" % TRANSCRIPT_DIR)
		quit(2)
		return

	print("=== swarm walk: CAGE / SWARM / RANDOM ===")
	print("target: %d allocation opportunities" % TARGET)
	print("no generation, no model, no requests")

	_load()
	if not _rows.is_empty():
		print("resuming with %d opportunities already recorded" % _rows.size())

	var base := _slice * 10
	var used := 0
	for f in files.slice(base, base + _runs * 2):
		if _rows.size() >= TARGET or used >= _runs:
			break
		var turns := _load_turns(f)
		if turns.size() < 30:
			continue
		used += 1
		_walk(turns)
		_save()

	_save()
	_report()


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


## Roster in order of first appearance, so round-robin has a fixed rotation
## that does not depend on how names happen to sort.
func _roster(turns: Array) -> Array:
	var seen := {}
	var out: Array = []
	for t in turns:
		var s := str(t["speaker"])
		if not seen.has(s):
			seen[s] = true
			out.append(s)
	return out


## The addressing form agents actually use: the leading word of a display name,
## which is the model family. Observed by the AGENT in what it can see.
func _handle(display_name: String) -> String:
	var parts := display_name.split(" ", false)
	if parts.is_empty():
		return display_name.to_lower()
	return str(parts[0]).to_lower()


# ------------------------------------------------------------------ the walk

func _walk(turns: Array) -> void:
	var roster := _roster(turns)
	if roster.size() < 2:
		return

	for i in turns.size():
		if _rows.size() >= TARGET:
			return
		if i < AIRTIME_WINDOW:
			continue

		var history: Array = turns.slice(0, i)
		var prev := str(turns[i - 1]["speaker"])

		# CAGE: round-robin successor of the previous speaker.
		var cage: String = roster[(roster.find(prev) + 1) % roster.size()]

		# Each agent assembles a view of ITSELF. The harness builds them one at
		# a time and hands each agent only its own -- it never assembles a table
		# and scores across it, which is the load balancer this design exists to
		# not be.
		var swarm_bids: Array = []
		var random_bids: Array = []
		var participation := {}
		for agent_v in roster:
			var agent := str(agent_v)
			var view := _local_view(agent, history, i)
			var eligible: bool = agent != prev

			var bid := B.compute(view)
			var submits := B.should_bid(view)
			# Telemetry may distinguish a broken policy from a chosen silence.
			# The resolver may not, and never receives either.
			var why := "bid"
			if is_nan(bid):
				why = "malformed"
			elif not submits:
				why = "abstained"
			participation[agent] = {"why": why, "bid": (0.0 if is_nan(bid) else bid),
				"eligible": eligible}
			if submits:
				swarm_bids.append({"agent_id": agent, "eligible": eligible, "bid": bid})

			# RANDOM: a bid carrying no local information, deterministic in the
			# opportunity so the walk stays reproducible and pairable.
			var rb := _noise(agent, int(turns[i]["turn"]))
			if rb >= B.ABSTAIN_BELOW:
				random_bids.append({"agent_id": agent, "eligible": eligible, "bid": rb})

		var s_out: Dictionary = R.resolve(swarm_bids)
		var r_out: Dictionary = R.resolve(random_bids)

		_rows.append({
			"turn": int(turns[i]["turn"]),
			"actual": str(turns[i]["speaker"]),
			"cage": cage,
			"swarm_ok": bool(s_out.get("ok", false)),
			"swarm": str(s_out.get("agent_id", "")),
			"swarm_code": str(s_out.get("code", R.OK)),
			"random_ok": bool(r_out.get("ok", false)),
			"random": str(r_out.get("agent_id", "")),
			"random_code": str(r_out.get("code", R.OK)),
			"participation": participation,
		})


func _local_view(agent: String, history: Array, now_index: int) -> Dictionary:
	var since := 0
	var found := false
	for k in range(history.size() - 1, -1, -1):
		if str(history[k]["speaker"]) == agent:
			since = (history.size() - 1) - k
			found = true
			break
	if not found:
		since = history.size()

	var window_start := maxi(history.size() - AIRTIME_WINDOW, 0)
	var mine := 0
	var total := 0
	for k in range(window_start, history.size()):
		total += 1
		if str(history[k]["speaker"]) == agent:
			mine += 1
	var share := 0.0 if total == 0 else float(mine) / float(total)

	var handle := _handle(agent)
	var named := false
	for k in range(maxi(history.size() - NAMED_WINDOW, 0), history.size()):
		if str(history[k]["speaker"]) == agent:
			continue
		if str(history[k]["text"]).to_lower().find(handle) != -1:
			named = true
			break

	return B.local_view(since, named, share)


## A bid with no local content. FNV-1a so it is deterministic across runs and
## independent of any engine RNG, and so the placebo is reproducible.
func _noise(agent: String, turn: int) -> float:
	var h := 2166136261
	for byte in (agent + "#" + str(turn)).to_utf8_buffer():
		h = (h ^ int(byte)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return float(h % 1000) / 999.0


# ----------------------------------------------------------------- reporting

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


func _pct(n: int, d: int) -> float:
	return 0.0 if d == 0 else 100.0 * float(n) / float(d)


## Top-agent share of proposals over a sliding window, averaged. Named
## COUNTERFACTUAL because the proposed speakers never took those turns.
func _concentration(key: String) -> float:
	if _rows.size() < CONCENTRATION_WINDOW:
		return 0.0
	var total := 0.0
	var windows := 0
	for start in range(0, _rows.size() - CONCENTRATION_WINDOW + 1):
		var counts := {}
		for k in range(start, start + CONCENTRATION_WINDOW):
			var who := str(_rows[k][key])
			if who == "":
				continue
			counts[who] = int(counts.get(who, 0)) + 1
		var top := 0
		for c in counts.values():
			top = maxi(top, int(c))
		total += 100.0 * float(top) / float(CONCENTRATION_WINDOW)
		windows += 1
	return 0.0 if windows == 0 else total / float(windows)


## Longest run of opportunities in which an agent was never proposed. A fact
## about the local policy under THIS history, not a starvation claim.
func _drought(key: String) -> int:
	var last := {}
	var worst := 0
	for i in _rows.size():
		var who := str(_rows[i][key])
		if who == "":
			continue
		if last.has(who):
			worst = maxi(worst, i - int(last[who]) - 1)
		last[who] = i
	return worst


func _report() -> void:
	var n := _rows.size()

	# The teeth, as in the source probe. No flag reaches past this.
	if n < TARGET:
		print("\n  %d of %d opportunities." % [n, TARGET])
		print("  NOT DECIDABLE. No rate is printed before the pre-registered")
		print("  target is reached, and there is no override.")
		quit(0)
		return

	var s_ok := 0
	var r_ok := 0
	var codes := {}
	var agree_cage := 0
	var random_agree_cage := 0
	var agree_actual := 0
	for row in _rows:
		if bool(row["swarm_ok"]):
			s_ok += 1
			if str(row["swarm"]) == str(row["cage"]):
				agree_cage += 1
			if str(row["swarm"]) == str(row["actual"]):
				agree_actual += 1
		else:
			var c := str(row["swarm_code"])
			codes[c] = int(codes.get(c, 0)) + 1
		if bool(row["random_ok"]):
			r_ok += 1
			if str(row["random"]) == str(row["cage"]):
				random_agree_cage += 1

	print("\n--- %d allocation opportunities, no generation ---\n" % n)
	print("  VIABILITY (the only bar)")
	print("    valid allocation rate   %.1f%%   (bar 95.0%%)" % _pct(s_ok, n))
	print("\n  SWARM AUTONOMY FAILURES")
	for c in [R.NO_BIDS, R.NO_ELIGIBLE_BIDS, R.MALFORMED_BID]:
		print("    %-20s %5.1f%%" % [c, _pct(int(codes.get(c, 0)), n)])

	print("\n  BEHAVIOURAL DIVERGENCE FROM ROUND-ROBIN (not quality)")
	print("    swarm agrees with cage   %.1f%%" % _pct(agree_cage, maxi(s_ok, 1)))
	print("    RANDOM agrees with cage  %.1f%%   <- the placebo floor"
		% _pct(random_agree_cage, maxi(r_ok, 1)))
	print("    swarm matches the actual speaker  %.1f%%" % _pct(agree_actual, maxi(s_ok, 1)))

	print("\n  COUNTERFACTUAL SELECTION CONCENTRATION (top share of %d)" % CONCENTRATION_WINDOW)
	print("    cage    %.1f%%" % _concentration("cage"))
	print("    swarm   %.1f%%" % _concentration("swarm"))
	print("    random  %.1f%%   <- the placebo floor" % _concentration("random"))

	print("\n  COUNTERFACTUAL PROPOSAL DROUGHT (longest unproposed run)")
	print("    cage %d   swarm %d   random %d"
		% [_drought("cage"), _drought("swarm"), _drought("random")])

	# Anatomy, deliberately not combined into a fairness score. An agent that
	# bids constantly and rarely wins is an arbitration story; one that almost
	# never bids is a local-policy story, and a single number would hide which.
	print("\n  PER-AGENT ANATOMY (never summed into a score)")
	print("    %-26s %6s %6s %6s %6s %9s"
		% ["agent", "seen", "bids", "abst", "wins", "mean bid"])
	var agents := {}
	for row in _rows:
		for a in row["participation"].keys():
			if not agents.has(a):
				agents[a] = {"seen": 0, "bids": 0, "abst": 0, "malformed": 0,
					"wins": 0, "sum": 0.0}
			var rec = agents[a]
			var p = row["participation"][a]
			rec["seen"] += 1
			match str(p["why"]):
				"bid":
					rec["bids"] += 1
					rec["sum"] += float(p["bid"])
				"abstained":
					rec["abst"] += 1
				"malformed":
					rec["malformed"] += 1
			if str(row["swarm"]) == str(a):
				rec["wins"] += 1
	var malformed_total := 0
	for a in agents.keys():
		var rec = agents[a]
		malformed_total += int(rec["malformed"])
		var mean := 0.0 if int(rec["bids"]) == 0 else float(rec["sum"]) / float(rec["bids"])
		print("    %-26s %6d %6d %6d %6d %9.3f"
			% [a, rec["seen"], rec["bids"], rec["abst"], rec["wins"], mean])
	print("    malformed local views across all agents: %d" % malformed_total)

	print("\nFROZEN DECISION (docs/EXPERIMENT_SWARM.md)")
	if _pct(s_ok, n) >= 95.0:
		print("  VIABLE - local bidding allocates the slot unassisted")
		print("  this says nothing about whole-match fairness or real starvation")
	else:
		print("  NOT VIABLE - local bidding cannot carry the slot without help")
	quit(0)
