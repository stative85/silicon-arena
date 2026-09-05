extends SceneTree

## Preflight B: does the frozen request policy produce a mixture on real states?
##
##   godot --headless --path . --script tools/swarm_mix.gd
##
## Pre-registered in docs/EXPERIMENT_METABOLISM.md at 858f1ab.
##
## NO GENERATION. This replays local views computed from ALREADY-CANONICAL
## transcripts and tallies what the frozen policy would have requested at each
## opportunity. Nothing is asked of a model and no GPU time is spent.
##
## THIS IS A PREFLIGHT AND NOT AN INDEPENDENT VALIDATION, and the difference is
## stated here so it cannot be quietly forgotten later. `named_recently` was
## chosen as the HEAVY trigger BECAUSE SWARM-F had already established it as a
## real local signal carrying a stable +0.94 extra bidder. Confirming that a
## policy keyed to a known-frequent signal produces a non-degenerate mixture is
## a sanity check on the frozen policy. It is not evidence about the world, and
## it must never be reported as one.
##
## Preflight A (scripts/arena/swarm_request_selftest.gd) proves the branches are
## REACHABLE. This proves the policy is not INERT on realistic states. Neither
## is a result, and the experiment has not started.

const B := preload("res://scripts/arena/swarm_bid.gd")
const Q := preload("res://scripts/arena/swarm_request.gd")

const TRANSCRIPT_DIR := "user://live_matches"
const AIRTIME_WINDOW := 20
const NAMED_WINDOW := 3

## Frozen floor. Each class must appear on at least this share of opportunities
## or the policy is inert and METABOLISM-A is VOID before any GPU time.
const FLOOR := 0.10


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== METABOLISM preflight B: natural mix, NO generation ===\n")
	print("replaying canonical local views. this is a preflight, not an")
	print("independent validation: named_recently was chosen as the HEAVY")
	print("trigger because SWARM-F had already measured it.\n")

	var files := _transcripts()
	if files.is_empty():
		printerr("no transcripts in %s" % TRANSCRIPT_DIR)
		quit(2)
		return

	var counts := {Q.SMALL: 0, Q.NORMAL: 0, Q.HEAVY: 0}
	var malformed := 0
	var opportunities := 0
	var matches := 0

	for path in files:
		var turns := _load_turns(str(path))
		if turns.size() < 12:
			continue
		matches += 1
		var roster := _roster(turns)
		# Walk the transcript as history accumulating, exactly as a live match
		# sees it, and ask every eligible agent what it would have requested.
		for t in range(1, turns.size()):
			var history: Array = turns.slice(0, t)
			var prev := str(history[history.size() - 1]["speaker"])
			for agent_v in roster:
				var agent := str(agent_v)
				if agent == prev:
					continue
				opportunities += 1
				var cls := Q.request(_local_view(agent, history))
				if cls == "":
					malformed += 1
				else:
					counts[cls] = int(counts[cls]) + 1

	if opportunities == 0:
		printerr("no request opportunities found")
		quit(2)
		return

	print("  %d transcripts, %d request opportunities\n" % [matches, opportunities])
	var ok := true
	for cls in [Q.SMALL, Q.NORMAL, Q.HEAVY]:
		var n := int(counts[cls])
		var share := float(n) / float(opportunities)
		var verdict := "ok" if share >= FLOOR else "BELOW FLOOR"
		if share < FLOOR:
			ok = false
		print("    %-7s %6d   %5.1f%%   %s" % [cls, n, share * 100.0, verdict])
	print("    %-7s %6d   %5.1f%%" % ["(none)", malformed,
		100.0 * float(malformed) / float(opportunities)])

	print("\n  floor is %.0f%% per class" % (FLOOR * 100.0))
	if not ok:
		printerr("\n  MIX DEGENERATE. METABOLISM-A is VOID before any GPU time,")
		printerr("  and the request policy is redesigned rather than the floor.")
		quit(1)
		return
	print("\n  MIX OK - the frozen policy is not inert on realistic states.")
	print("  This is a preflight. The experiment has not started.")
	quit(0)


## Identical to the live harness. Duplicated deliberately rather than imported
## from a tool, so this preflight cannot drift from what the match computes
## without the drift being visible in a diff.
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
