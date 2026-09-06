extends SceneTree

## Replay the 1,500 Run 2 proposals against candidate contract semantics.
##
##   godot --headless --path . --script tools/pit_replay.gd -- --dir <path>
##
## INSTRUMENT DESIGN ONLY. Run 2 is void (docs/results/PIT_A_RUN2_VOID.md) and
## nothing here is architectural evidence. These 1,500 schema-valid proposals are
## a PRODUCER-SPACE SAMPLE: what five architectures actually emit through a given
## interface, which is precisely what every audit so far failed to test because
## every witness was built by the contract's own constructors.
##
## NO GENERATION. Offline replay of recorded raw proposals.
##
## THE GOAL IS NOT 300/300. Tuning until the animals behave is how an instrument
## becomes a mirror. Each old rejection is classified instead:
##
##   IRRELEVANT-FIELD COUPLING   a sound decision killed by a field the
##                               operation does not read -> should now pass
##   RELEVANT SEMANTIC INVALID   a genuine mistake in a field the operation
##                               DOES read -> must still fail
##   VALID DECISION              should transition
##
## If a species is still structurally incapable of expressing a useful action
## after canonicalisation, this is where that shows -- before any GPU time.

const W := preload("res://scripts/arena/pit_world.gd")
const V := preload("res://scripts/arena/pit_validator.gd")
const K := preload("res://scripts/arena/pit_contract.gd")
const CN := preload("res://scripts/arena/pit_canonical.gd")

var _dir := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--dir" and i + 1 < args.size():
			_dir = str(args[i + 1])
	if _dir == "":
		printerr("need --dir <raw artifact directory>")
		quit(2)
		return

	print("=== PIT A: replay of recorded proposals, INSTRUMENT DESIGN ONLY ===")
	print("source: %s\n" % _dir)

	var d := DirAccess.open(_dir)
	if d == null:
		printerr("cannot open %s" % _dir)
		quit(2)
		return

	var per_species := {}
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".jsonl"):
			_replay_file(_dir.path_join(f), per_species)
		f = d.get_next()

	print("%-32s %6s %6s %6s %6s   %s"
		% ["ARM", "VALID", "COUPL", "REAL", "SHAPE", "operations that now transition"])
	print("-".repeat(112))
	var names: Array = per_species.keys()
	names.sort()
	var totals := {"valid": 0, "coupling": 0, "real": 0, "shape": 0}
	for name in names:
		var s: Dictionary = per_species[name]
		var ops: Array = (s["ops"] as Dictionary).keys()
		ops.sort()
		print("%-32s %6d %6d %6d %6d   %s"
			% [name, int(s["valid"]), int(s["coupling"]), int(s["real"]),
				int(s["shape"]), str(ops)])
		for k in totals:
			totals[k] = int(totals[k]) + int(s[k])
	print("-".repeat(112))
	print("%-32s %6d %6d %6d %6d" % ["TOTAL", int(totals["valid"]),
		int(totals["coupling"]), int(totals["real"]), int(totals["shape"])])

	print("\n  VALID  a decision that now transitions the world")
	print("  COUPL  was rejected ONLY because of a field the operation never reads")
	print("  REAL   still rejected on a field the operation does read - correct")
	print("  SHAPE  unparseable or unknown operation - plumbing, not a decision")
	print("\n  Not a pass/fail bar. A species with 0 VALID after canonicalisation")
	print("  is structurally unable to act through this interface, and that is")
	print("  the finding this replay exists to surface.")
	quit(0)


func _replay_file(path: String, acc: Dictionary) -> void:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return
	var state := W.genesis()
	var name := ""
	while not fh.eof_reached():
		var line := fh.get_line()
		if line.strip_edges() == "":
			continue
		var row = JSON.parse_string(line)
		if typeof(row) != TYPE_DICTIONARY:
			continue
		name = str(row.get("species", "?"))
		if name == "RANDOM":
			fh.close()
			return
		if not acc.has(name):
			acc[name] = {"valid": 0, "coupling": 0, "real": 0, "shape": 0,
				"ops": {}}
		var s: Dictionary = acc[name]

		# The RAW proposal as the model emitted it, not the stored patch.
		var raw = JSON.parse_string(str(row.get("raw_response", "")))
		if typeof(raw) != TYPE_DICTIONARY:
			s["shape"] = int(s["shape"]) + 1
			continue

		var c := CN.canonicalise(raw)
		if not bool(c["ok"]):
			# Failed on a field the operation READS, or is unparseable.
			if str(c["code"]) == K.SHAPE_MALFORMED \
					or str(c["code"]) == K.SHAPE_UNKNOWN_OPERATION:
				s["shape"] = int(s["shape"]) + 1
			else:
				s["real"] = int(s["real"]) + 1
			continue

		var patch: Dictionary = c["patch"]
		var v := V.validate(state, patch)
		if bool(v["ok"]):
			s["valid"] = int(s["valid"]) + 1
			(s["ops"] as Dictionary)[str(patch["operation"])] = true
			state = W.apply(state, patch)
			# Was it ONLY canonicalisation that saved it? Recorded for the
			# coupling count: a proposal that needed normalising to pass was
			# killed by an irrelevant field in Run 2.
			if not (c["normalised"] as Array).is_empty():
				s["coupling"] = int(s["coupling"]) + 1
		else:
			s["real"] = int(s["real"]) + 1
	fh.close()
