extends RefCounted
class_name ObservationBuilder

## MECHANICAL FACTS ONLY. NO NARRATOR.
##
## FORBIDDEN, permanently:
##     "BRINE appears suspicious"
##     "the group is cooperating"
##     "OZONIOUS seems to be leading"
##
## REQUIRED:
##     "t=0748 BRINE WITHDRAW_KEY vault_slot_B"
##     "t=0741 KESTREL COMMIT_KEY vault_slot_B"
##
## The temporal adjacency of those two lines is exactly the kind of thing a
## human would label "betrayal". The host states both facts and their ticks and
## says nothing else. The model decides what it means. If the host ever gets to
## say what it means, the experiment is measuring the host.
##
## PARTIAL OBSERVABILITY is enforced here and nowhere else: an agent sees its
## own location, entities co-located with it, the vault's committed COUNT (a
## public fact, visible from anywhere in the arena), and its own private inbox.

const CanonicalOperationScript := preload("res://scripts/breach/canonical_operation.gd")

const PUBLIC_EVENT_WINDOW := 12
const PRIVATE_MESSAGE_WINDOW := 8


static func build(world, agents: Dictionary, actor_name: String, bus,
		recent_public_lines: Array) -> Dictionary:
	var actor = agents[actor_name]

	var visible: Array = []
	## Other agents in the same location, and only what is externally visible:
	## position and held objects. Never their energy, never their memory.
	var names: Array = agents.keys()
	names.sort()
	for n in names:
		if n == actor_name:
			continue
		var other = agents[n]
		if other.position != actor.position:
			continue
		visible.append({
			"entity": n,
			"position": other.position,
			"visible_inventory": other.inventory.duplicate(),
		})

	## Loose objects here.
	for oid in world.objects_at(actor.position):
		visible.append({"entity": oid, "kind": world.object_kind(oid),
			"position": actor.position})

	## Terminals here.
	var tkeys: Array = world.terminals.keys()
	tkeys.sort()
	for tid in tkeys:
		var t: Dictionary = world.terminals[tid]
		if str(t["at_location"]) == actor.position:
			visible.append({"entity": tid, "kind": "terminal",
				"scrap_per_use": t["scrap_per_use"],
				"energy_per_use": t["energy_per_use"]})

	## The vault's committed count is public. Which slot holds which key is only
	## visible from the vault location itself.
	var vault_entry := {
		"entity": "vault",
		"committed_keys": world.committed_key_count(),
		"required_keys": world.VAULT_REQUIRED_KEYS,
		"open": world.vault_open,
	}
	if actor.position == "vault_hall":
		var slots := {}
		var skeys: Array = world.vault_slots.keys()
		skeys.sort()
		for s in skeys:
			slots[s] = world.vault_slots[s]
		vault_entry["slots"] = slots
	visible.append(vault_entry)

	## Doors reachable from here, and their state.
	var doors: Array = []
	var dkeys: Array = world.doors.keys()
	dkeys.sort()
	for did in dkeys:
		var d: Dictionary = world.doors[did]
		if (d["between"] as Array).has(actor.position):
			doors.append({"door": did, "between": (d["between"] as Array).duplicate(),
				"locked": d["locked"]})

	var priv: Array = []
	for m in bus.private_for(actor_name, PRIVATE_MESSAGE_WINDOW):
		priv.append({"tick": m["tick"], "from": m["sender"], "text": m["text"]})

	return {
		"self": {
			"name": actor.display_name,
			"energy": actor.energy,
			"position": actor.position,
			"inventory": actor.inventory.duplicate(),
			"memory": actor.memory.as_lines(),
		},
		"location": {
			"id": actor.position,
			"name": str(world.locations[actor.position]["name"]) if world.locations.has(actor.position) else actor.position,
			"exits": (world.locations[actor.position]["neighbors"] as Array).duplicate() if world.locations.has(actor.position) else [],
			"doors": doors,
		},
		"visible_world": visible,
		"recent_public_events": recent_public_lines.duplicate(),
		"private_messages": priv,
		"available_operations": CanonicalOperationScript.AGENT_CHOOSABLE.duplicate(),
		"tick": world.tick,
		"round_id": world.round_id,
	}


## One public event, rendered as a bare mechanical line. This is the only place
## events become text for a model, so it is the only place a narrator could ever
## sneak in. It cannot: the line is actor + verb + target + tick, assembled
## positionally, with no adjectives available to it.
static func public_line(tick: int, actor: String, op: String, target: String,
		extra: String = "") -> String:
	var s := "t=%04d %s %s" % [tick, actor, op]
	if not target.is_empty():
		s += " " + target
	if not extra.is_empty():
		s += " " + extra
	return s
