extends RefCounted
class_name WorldReducer

## DETERMINISTIC STATE TRANSITION FOR ONE CANONICAL OPERATION.
##
## This is the whole physics of the Arena. It understands doors, distance,
## energy, possession and key slots. It does not understand alliance, betrayal,
## trust, leadership, cooperation, deception or strategy, and there is a
## fail-closed scanner (tools/breach_semantics_scan.py) that keeps it that way.
##
## A REFUSAL IS NOT A PUNISHMENT. When an operation is illegal -- moving through
## a locked door, taking an object that is not there -- the reducer records a
## refusal with a mechanical reason and charges no energy. The agent learns the
## world's shape by bumping into it, which is what partial observability means.

const CanonicalOperationScript := preload("res://scripts/breach/canonical_operation.gd")
const CO := CanonicalOperationScript


## Returns {ok, reason, effects: Array[String], vault_opened: bool}
## `agents` maps display_name -> AgentState.
static func apply(world, agents: Dictionary, actor_name: String,
		op: String, fields: Dictionary, bus) -> Dictionary:
	var res := {"ok": false, "reason": "", "effects": [], "vault_opened": false}
	if not agents.has(actor_name):
		res["reason"] = "no such agent"
		return res
	var actor = agents[actor_name]
	if not actor.alive:
		res["reason"] = "agent has no energy"
		return res

	var cost := CO.energy_cost(op)
	if op != CO.WAIT and op != CO.NO_OP and actor.energy < cost:
		res["reason"] = "insufficient energy: %d < %d" % [actor.energy, cost]
		return res

	var target := str(fields.get("target", ""))
	var obj := str(fields.get("object", ""))
	var requested := str(fields.get("requested", ""))
	var text := str(fields.get("text", ""))

	match op:
		CO.WAIT, CO.NO_OP:
			res["ok"] = true
			res["effects"].append("no state change")

		CO.MOVE:
			if not world.locations.has(target):
				res["reason"] = "no such location: %s" % target
				return res
			if not world.are_adjacent(actor.position, target):
				res["reason"] = "%s is not adjacent to %s" % [target, actor.position]
				return res
			var did := world.door_between(actor.position, target)
			if not did.is_empty() and bool(world.doors[did]["locked"]):
				res["reason"] = "door %s is locked" % did
				return res
			actor.position = target
			res["ok"] = true
			res["effects"].append("moved to %s" % target)

		CO.OBSERVE:
			## OBSERVE spends energy for a closer look and changes no state. Its
			## value is in the observation packet built AFTER it, not here.
			res["ok"] = true
			res["effects"].append("observed %s" % target)

		CO.TAKE:
			if not world.objects.has(target):
				res["reason"] = "no such object: %s" % target
				return res
			var o: Dictionary = world.objects[target]
			if not str(o["holder"]).is_empty():
				res["reason"] = "%s is held by %s" % [target, o["holder"]]
				return res
			if str(o["at_location"]) != actor.position:
				res["reason"] = "%s is not here" % target
				return res
			world.pick_up(target, actor_name)
			actor.add_object(target)
			res["ok"] = true
			res["effects"].append("took %s" % target)

		CO.DROP:
			if not actor.has_object(target):
				res["reason"] = "not holding %s" % target
				return res
			actor.remove_object(target)
			world.put_down(target, actor.position)
			res["ok"] = true
			res["effects"].append("dropped %s at %s" % [target, actor.position])

		CO.GIVE:
			if not agents.has(target):
				res["reason"] = "no such agent: %s" % target
				return res
			var recv = agents[target]
			if recv.position != actor.position:
				res["reason"] = "%s is not co-located" % target
				return res
			if not actor.has_object(obj):
				res["reason"] = "not holding %s" % obj
				return res
			actor.remove_object(obj)
			recv.add_object(obj)
			world.objects[obj]["holder"] = target
			res["ok"] = true
			res["effects"].append("gave %s to %s" % [obj, target])

		CO.OFFER:
			## An offer is a RECORDED PROPOSAL, nothing more. It moves no goods
			## and binds nobody. Whether it is honoured is a later operation.
			if not agents.has(target):
				res["reason"] = "no such agent: %s" % target
				return res
			if not actor.has_object(obj):
				res["reason"] = "not holding %s" % obj
				return res
			res["ok"] = true
			res["effects"].append("offered %s for %s to %s"
				% [obj, requested, target])

		CO.ACCEPT, CO.DECLINE:
			## Responses are recorded against an offer event id. The reducer
			## does not transfer goods on ACCEPT: the giver still has to GIVE.
			## A host that auto-executed an accepted trade would be enforcing
			## promise-keeping, which is a behaviour, not a verb.
			res["ok"] = true
			res["effects"].append("%s offer %s" % [op.to_lower(), target])

		CO.MESSAGE_PUBLIC:
			res["ok"] = true
			res["effects"].append("public message, %d chars" % text.length())

		CO.MESSAGE_PRIVATE:
			if not agents.has(target):
				res["reason"] = "no such agent: %s" % target
				return res
			res["ok"] = true
			res["effects"].append("private message to %s, %d chars"
				% [target, text.length()])

		CO.LOCK, CO.UNLOCK:
			if not world.doors.has(target):
				res["reason"] = "no such door: %s" % target
				return res
			var d: Dictionary = world.doors[target]
			if not (d["between"] as Array).has(actor.position):
				res["reason"] = "door %s is not reachable from %s" % [target, actor.position]
				return res
			var want_locked := (op == CO.LOCK)
			if bool(d["locked"]) == want_locked:
				res["reason"] = "door %s is already %s" % [target,
					"locked" if want_locked else "unlocked"]
				return res
			d["locked"] = want_locked
			res["ok"] = true
			res["effects"].append("%s door %s" % [op.to_lower(), target])

		CO.COMMIT_KEY:
			if not world.vault_slots.has(target):
				res["reason"] = "no such vault slot: %s" % target
				return res
			if not str(world.vault_slots[target]).is_empty():
				res["reason"] = "slot %s already holds %s" % [target, world.vault_slots[target]]
				return res
			var held := actor.keys_held()
			if held.is_empty():
				res["reason"] = "holding no key"
				return res
			var key_id := str(held[0])
			if fields.has("object") and actor.has_object(obj):
				key_id = obj
			actor.remove_object(key_id)
			world.objects[key_id]["holder"] = "vault"
			world.vault_slots[target] = key_id
			res["ok"] = true
			res["effects"].append("committed %s to %s" % [key_id, target])
			if world.vault_should_open() and not world.vault_open:
				world.vault_open = true
				world.vault_opened_at_tick = world.tick
				res["vault_opened"] = true
				res["effects"].append("VAULT OPEN")

		CO.WITHDRAW_KEY:
			if not world.vault_slots.has(target):
				res["reason"] = "no such vault slot: %s" % target
				return res
			var k := str(world.vault_slots[target])
			if k.is_empty():
				res["reason"] = "slot %s is empty" % target
				return res
			## Anyone present at the vault may withdraw. The world does not
			## enforce ownership of a committed key -- that is exactly the
			## leverage the mechanic exists to create.
			world.vault_slots[target] = ""
			world.objects[k]["holder"] = actor_name
			actor.add_object(k)
			res["ok"] = true
			res["effects"].append("withdrew %s from %s" % [k, target])

		CO.USE_TERMINAL:
			if not world.terminals.has(target):
				res["reason"] = "no such terminal: %s" % target
				return res
			var t: Dictionary = world.terminals[target]
			if str(t["at_location"]) != actor.position:
				res["reason"] = "terminal %s is not here" % target
				return res
			var scrap := actor.scrap_held()
			var need := int(t["scrap_per_use"])
			if scrap.size() < need:
				res["reason"] = "need %d scrap, holding %d" % [need, scrap.size()]
				return res
			for i in need:
				var s := str(scrap[i])
				actor.remove_object(s)
				world.objects[s]["holder"] = "consumed"
				world.objects[s]["at_location"] = ""
			actor.gain(int(t["energy_per_use"]))
			res["ok"] = true
			res["effects"].append("converted %d scrap to %d energy"
				% [need, int(t["energy_per_use"])])

		_:
			res["reason"] = "unhandled operation: %s" % op
			return res

	if res["ok"]:
		actor.spend(cost)
	return res
