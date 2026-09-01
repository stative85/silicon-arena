extends SceneTree

## Rung 1 inspector: show what each agent actually holds about ONE objective
## event, from REAL match data on disk. Read-only. Writes nothing.
##
##   Godot --headless --path . --script scripts/arena/scar_frames_dump.gd \
##       -- [--mode silicon_arena] [--match <id>]
##
## The point is not that the accounts agree. It is that they differ, they are
## all valid, and the engine calls none of them a lie.

const ScarScript := preload("res://scripts/arena/scar_lattice.gd")

func _init() -> void:
	var mode := "silicon_arena"
	var want_match := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--mode" and i + 1 < args.size(): mode = args[i + 1]
		if args[i] == "--match" and i + 1 < args.size(): want_match = args[i + 1]

	var s = ScarScript.new()
	var report: Dictionary = s.load_all()
	print("loaded: %s" % str(report))

	var events: Array = s.events_for(mode)
	if events.is_empty():
		print("no objective events recorded in mode '%s'" % mode)
		quit(1)
		return
	if want_match != "":
		var filtered := []
		for e in events:
			if str(e.get("match_id", "")) == want_match: filtered.append(e)
		events = filtered

	var shown := 0
	var framed := 0
	var unframed := 0
	var frame_ids := {}
	for ev in events:
		var witnesses: Array = ev.get("witnesses", [])
		if witnesses.size() < 3:
			continue   # a rung-1 demonstration needs at least three vantage points
		shown += 1
		print("\n" + "=".repeat(72))
		print("OBJECTIVE EVENT  %s" % str(ev.get("event_id", "")))
		print("  match %s  turn %s  type %s" % [
			str(ev.get("match_id", "")), str(ev.get("turn", "")), str(ev.get("type", ""))])
		print("  what happened: %s" % str(ev.get("summary", "")))
		print("  (this record is never rewritten by any account below)")
		print("-".repeat(72))
		for wid in witnesses:
			var held := {}
			for m in s.memories_for(str(wid), mode):
				if m.get("provenance", {}).get("evidence_event_ids", []).has(ev.get("event_id")):
					held = m
			if held.is_empty():
				print("\n  %s — holds NO memory of this event" % str(wid))
				continue
			var o: Dictionary = held.get("observation", {})
			if o.is_empty():
				unframed += 1
				print("    PRE-FRAME RECORD — written before Rung 1 existed. No")
				print("    observation block, and NOT backfilled: inventing a vantage")
				print("    point after the fact would be fabricated provenance.")
			else:
				framed += 1
				frame_ids[str(o.get("frame_id", ""))] = true
			var name := str(s.get_identity(str(wid)).get("canonical_name", wid))
			print("\n  %s (%s)" % [name, str(wid)])
			print("    frame        %s" % str(o.get("frame_id", "—")))
			print("    directness   %s" % str(o.get("directness", "—")))
			print("    could see    %s" % str(o.get("observable_portion", "—")))
			var hid: Array = o.get("hidden_variables", [])
			print("    could NOT    %s" % ("nothing withheld" if hid.is_empty() else ", ".join(hid)))
			print("    chain        %s" % ", ".join(o.get("transformation_chain", [])))
			print("    local seq    %s" % str(o.get("local_sequence", "—")))
			print("    reads as     \"%s\"" % s.render_observation(
				held, str(wid), func(a): return str(s.get_identity(str(a)).get("canonical_name", a))))
			print("    flagged false? %s" % ("NO" if held.get("superseded_by", null) == null else "YES"))
		if shown >= 3:
			break

	if shown == 0:
		print("\nno event in mode '%s' had three or more witnesses" % mode)
		quit(1)
		return
	print("\n" + "=".repeat(72))
	print("%d objective event(s) shown  ·  %d framed  ·  %d pre-frame" % [shown, framed, unframed])
	print("distinct frame ids across all framed accounts: %d" % frame_ids.size())
	if framed == 0:
		print("RUNG1 NO_EVIDENCE — every account predates the observation frame.")
		print("  Rung 0 (perspective) is shown above. Rung 1 is NOT.")
		quit(2)
		return
	if unframed > 0:
		print("RUNG1 PARTIAL — %d account(s) carry no frame." % unframed)
		quit(3)
		return
	if frame_ids.size() < framed:
		print("RUNG1 FAIL — %d accounts share only %d frame id(s); observers are" % [framed, frame_ids.size()])
		print("  being told they stood in the same place.")
		quit(1)
		return
	print("RUNG1 PASS — %d accounts, %d distinct frames, none flagged false." % [framed, frame_ids.size()])
