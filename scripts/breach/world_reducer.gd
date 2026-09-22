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

	## ENCUMBRANCE. Every operation costs its constant except MOVE, which costs
	## the base plus one per unit of carried mass over capacity. The cost is
	## computed BEFORE the affordability gate below, so an overloaded agent that
	## cannot pay is refused rather than moved and then billed.
	var cost := CO.energy_cost(op)
	if op == CO.MOVE:
		cost = actor.move_cost(world)
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
			var did: String = world.door_between(actor.position, target)
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
			## PHYSICAL ACT: you must be at the vault. No key teleportation.
			if actor.position != world.vault_location:
				res["reason"] = "must be at %s to commit; standing in %s" % [world.vault_location, actor.position]
				return res
			if not world.vault_slots.has(target):
				res["reason"] = "no such vault slot: %s" % target
				return res
			if not str(world.vault_slots[target]).is_empty():
				res["reason"] = "slot %s already holds %s" % [target, world.vault_slots[target]]
				return res
			var held: Array = actor.keys_held()
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
			## PHYSICAL ACT, same rule. Anyone STANDING AT THE VAULT may withdraw
			## any committed key -- possession transfers to them explicitly, and
			## the key never moves without someone being there to move it. That
			## is the leverage: exposure to whoever is present, not to whoever
			## thinks of it first from across the map.
			if actor.position != world.vault_location:
				res["reason"] = "must be at %s to withdraw; standing in %s" % [world.vault_location, actor.position]
				return res
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
			var scrap: Array = actor.scrap_held()
			var need := int(t["scrap_per_use"])
			if scrap.size() < need:
				res["reason"] = "need %d scrap, holding %d" % [need, scrap.size()]
				return res
			## MASS CONVERSION, not mass destruction. The object stays in
			## state with its kind and its mass and is marked consumed: it
			## leaves active_mass and enters consumed_mass, and accounted_mass
			## does not move. MASS_CONVERSION is host-authored -- not a verb,
			## not a turn, never in ACTION_SCHEMA_V1 -- and it names every
			## object so the ledger can be replayed.
			var converted: Array = []
			var converted_mass := 0
			for i in need:
				var s := str(scrap[i])
				converted_mass += world.object_mass(s)
				actor.remove_object(s)
				world.objects[s]["holder"] = "consumed"
				world.objects[s]["at_location"] = ""
				converted.append(s)
			var gained := int(t["energy_per_use"])
			actor.gain(gained)
			res["ok"] = true
			res["effects"].append("converted %d scrap to %d energy"
				% [need, gained])
			res["effects"].append("MASS_CONVERSION at %s: %s (mass %d) -> %d energy"
				% [target, ", ".join(converted), converted_mass, gained])
			res["mass_conversion"] = {"terminal": target, "agent": actor_name,
				"objects": converted, "mass": converted_mass,
				"energy_gained": gained}

		_:
			res["reason"] = "unhandled operation: %s" % op
			return res

	if res["ok"]:
		actor.spend(cost)
		## ATOMIC DEATH SPILL. The accepted action has already completed. If it
		## took the agent to zero, it is now dead -- and everything it was
		## carrying would otherwise be unreachable forever, held by a body that
		## can never be scheduled again.
		##
		## So the world takes it back, in one step, at the position the agent
		## died in. Mass is conserved through the transition: the objects move
		## from an inventory to a floor, they are not destroyed.
		##
		## DEATH_SPILL IS NOT A VERB. It is host-authored, it is not a turn, it
		## is not in ACTION_SCHEMA_V1, and no agent may choose it. It is
		## recorded as its own effect precisely so an analyst never reads it as
		## a dead agent acting -- the host moved the objects, nobody chose to.
		if not actor.alive:
			## DEATH_SPILL: transfers existing inventory to the floor. It
			## CREATES NOTHING. Kept a separate record from the shell so a
			## reader can never mistake a spilled key for created matter.
			if not actor.inventory.is_empty():
				var spilled: Array = actor.inventory.duplicate()
				spilled.sort()
				for oid in spilled:
					actor.remove_object(str(oid))
					world.put_down(str(oid), actor.position)
				res["effects"].append("DEATH_SPILL at %s: %s"
					% [actor.position, ", ".join(spilled)])
				res["death_spill"] = {"at": actor.position,
					"objects": spilled, "mass_created": 0}

			## SHELL_APPEARED: the agent itself becomes inert matter. This is a
			## MASS CREATION and is recorded as one, separately from the spill.
			##
			## ORDERING, INHERITED AND NOT DECIDED HERE: the shell exists before
			## this tick's flow_advance, so a death obstructs on the DEATH TICK
			## rather than the next one (FLOWSCAR3 breach_round.step()).
			##
			## The id is name-derived, which is sound ONLY because FLOWSCAR4
			## permits one lifecycle per agent and no revival. death_event_id is
			## carried regardless, and is unique whatever the id scheme.
			## THE SHELL IS FLOWSCAR4 PHYSICS, NOT V1 PHYSICS, and the loaded
			## contract decides -- not a flag and not a build constant. V1 never
			## declares the shell kind, so a round that named V1 gets V1's death
			## transition exactly as Step 1B measured it. V2 declares it, so a
			## FLOWSCAR4 round gets a shell. The behaviour follows the contract
			## the round asked for, which is the whole point of naming one.
			var sid := "shell_%s" % actor_name.to_lower()
			if world.contract.is_declared("shell") 					and not world.objects.has(sid):
				world.add_object(sid, "shell", actor.position)
				res["effects"].append("SHELL_APPEARED at %s: %s"
					% [actor.position, sid])
				res["shell_appeared"] = {"event": "SHELL_APPEARED",
					"object_id": sid, "kind": "shell",
					"mass": world.object_mass(sid),
					"location": actor.position, "tick": world.tick,
					"cause": "energy_exhausted", "death_event_id": -1}
	return res
