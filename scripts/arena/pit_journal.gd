extends RefCounted
class_name PitJournal

## The append-only record a PIT A trajectory is reconstructed from.
##
## Pre-registered in docs/EXPERIMENT_PIT_A.md at 15f30e9, amended at e4faf3e.
##
## APPEND EVERY CYCLE, NOT EVERY RUN. One crash at cycle 89 must cost one cycle,
## not five hours. Every row is flushed before the next generation is requested.
##
## THE JOURNAL IS THE EXPERIMENT. Canonical state is derivable from it and is
## never the source of truth: replaying the accepted patches from genesis must
## reproduce the final hash exactly, which is a pre-registered tooth.
##
## SEPARATE FILES ARE WHERE SHARED MUTABLE STATE COMES BACK. In memory, species
## trajectories are separate dictionaries and cannot touch each other. On disk
## they are files, and a resume that opened the wrong one would silently
## continue another species' history under this species' name. Every row carries
## its species, and load() REFUSES a journal whose rows do not all belong to the
## species asking for it. That refusal is a tooth, not a warning.

const W := preload("res://scripts/arena/pit_world.gd")

const CONTAMINATED := "SPECIES_MISMATCH"
const REPLICATE_MISMATCH := "REPLICATE_MISMATCH"
const BROKEN_CHAIN := "BROKEN_HASH_CHAIN"


static func path(species: String, replicate: int) -> String:
	return "user://pit_a/%s__r%d.jsonl" % [species.replace("/", "_"), replicate]


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://pit_a"))


## One cycle, flushed immediately. Opening in READ_WRITE and seeking to the end
## rather than APPEND, because APPEND on some platforms buffers in ways that
## lose the last rows on a hard kill -- which is the exact scenario this exists
## to survive.
static func append(species: String, replicate: int, row: Dictionary) -> void:
	ensure_dir()
	var p := path(species, replicate)
	var fh := FileAccess.open(p, FileAccess.READ_WRITE)
	if fh == null:
		fh = FileAccess.open(p, FileAccess.WRITE)
	if fh == null:
		return
	fh.seek_end()
	fh.store_line(JSON.stringify(row))
	fh.flush()
	fh.close()


## Returns {"ok": bool, "code": String, "rows": Array}.
##
## A journal is refused if any row names a different species or replicate, or if
## the recorded hash chain does not link. A contaminated resume is worse than no
## resume: it produces a trajectory that looks valid and belongs to nobody.
static func load_rows(species: String, replicate: int) -> Dictionary:
	var rows: Array = []
	var fh := FileAccess.open(path(species, replicate), FileAccess.READ)
	if fh == null:
		return {"ok": true, "code": "OK", "rows": rows}
	while not fh.eof_reached():
		var line := fh.get_line()
		if line.strip_edges() == "":
			continue
		var d = JSON.parse_string(line)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		rows.append(d)
	fh.close()

	for r in rows:
		if str(r.get("species", "")) != species:
			return {"ok": false, "code": CONTAMINATED, "rows": []}
		if int(r.get("replicate", -1)) != replicate:
			return {"ok": false, "code": REPLICATE_MISMATCH, "rows": []}

	# The chain must link: each row's pre-state hash is the previous row's
	# post-state hash. A gap means rows were lost, reordered, or came from
	# somewhere else.
	for i in range(1, rows.size()):
		if str((rows[i] as Dictionary).get("pre_state_hash", "")) \
				!= str((rows[i - 1] as Dictionary).get("post_state_hash", "")):
			return {"ok": false, "code": BROKEN_CHAIN, "rows": []}

	return {"ok": true, "code": "OK", "rows": rows}


## Rebuild the world from an accepted-patch history. The journal, not the saved
## state, is what a resume trusts.
static func replay(rows: Array) -> Dictionary:
	var state := W.genesis()
	for r in rows:
		if not bool((r as Dictionary).get("accepted", false)):
			continue
		state = W.apply(state, (r as Dictionary).get("patch", {}))
	return state


## The cycle a resume should continue from. Every recorded row consumed an
## opportunity, accepted or not, so this counts rows rather than accepted ones.
static func next_cycle(rows: Array) -> int:
	return rows.size()
