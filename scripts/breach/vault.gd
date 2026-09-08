extends RefCounted
class_name Vault

## THE MECHANIC THE WHOLE ROUND HANGS ON.
##
## Five physical keys exist. Three DISTINCT keys must be committed at the same
## time. No agent needs its own specific key, and no agent can open it alone.
## That is the entire source of negotiation, leverage, refusal, freeloading and
## reversal -- none of which are implemented, and all of which are possible.
##
## Two properties are deliberate:
##
##   FIVE SLOTS, THREE REQUIRED. A committed key can be withdrawn without the
##   count necessarily dropping below the threshold, so the vault can sit at
##   2/3 forever while agents argue.
##
##   WITHDRAWAL IS NOT OWNERSHIP-CHECKED. Anyone at the vault may withdraw any
##   committed key. The world does not protect a commitment; that exposure IS
##   the leverage. A host that enforced "only the committer may withdraw" would
##   have implemented trust.

const REQUIRED := 3


static func committed_count(world) -> int:
	return world.committed_key_count()


static func distinct_keys(world) -> Array:
	return world.distinct_committed_keys()


static func is_open(world) -> bool:
	return world.vault_open


static func progress(world) -> Dictionary:
	var distinct := world.distinct_committed_keys()
	return {
		"committed": world.committed_key_count(),
		"distinct": distinct.size(),
		"required": REQUIRED,
		"open": world.vault_open,
		"opened_at_tick": world.vault_opened_at_tick,
		"keys": distinct,
	}


## Who committed what, reconstructed from the event log rather than tracked in
## world state. The world stores WHICH key is in a slot, not who put it there --
## attribution is a property of the log, and keeping it there means the world
## cannot be queried for "whose key is this", a question with no mechanical
## meaning.
static func commitment_history(events: Array) -> Array:
	var out: Array = []
	for e in events:
		var op := str(e.get("operation", ""))
		if op != "COMMIT_KEY" and op != "WITHDRAW_KEY":
			continue
		if not bool(e.get("accepted", false)):
			continue
		out.append({
			"tick": e.get("tick", 0),
			"event_id": e.get("event_id", -1),
			"actor": e.get("actor", ""),
			"operation": op,
			"slot": str((e.get("fields", {}) as Dictionary).get("target", "")),
			"effects": e.get("effects", []),
		})
	return out


## A UI progress bar, rendered mechanically. Three filled blocks means open.
static func bar(world) -> String:
	var n := world.distinct_committed_keys().size()
	var s := ""
	for i in REQUIRED:
		s += "#" if i < n else "."
	return "%s  %d / %d" % [s, n, REQUIRED]
