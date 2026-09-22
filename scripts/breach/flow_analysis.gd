extends RefCounted
class_name BreachFlowAnalysis

## THE LEVERAGE GATE AND THE ANCESTOR-REMOVAL COUNTERFACTUAL.
##
## Committed and hashed BEFORE any live result exists. Building an analyzer
## after seeing the shells would let the shells shape the instrument that
## measures them.
##
## THE LEVERAGE CRITERION is ported unchanged from the closed FLOWSCAR3 regime
## and evaluated on the PRE-TREATMENT state, before the ancestor event:
##
##     C0 > 0                      the node could pass material
##     C1 < C0                     the shell's mass would reduce that
##     pre-treatment supply        material actually reaches the node
##     pre-treatment receiver      a downstream node can accept it
##
## A shell that lands on a saturated or dead channel has NO leverage. That is
## reported as NO_CAUSAL_LEVERAGE -- a legitimate outcome, not a failure of the
## physics and not a failure of the instrument.
##
## THE COUNTERFACTUAL replays the recorded operation log deterministically with
## ONE change: the ancestor's shell is suppressed. Everything else -- the same
## actors, the same verbs, the same fields, the same order -- is identical, so
## any divergence is attributable to the shell's mass and to nothing else.
## Models are NEVER re-queried. A stochastic rerun is not a counterfactual.

const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const BusScript := preload("res://scripts/breach/message_bus.gd")
const Reducer := preload("res://scripts/breach/world_reducer.gd")
const SP := preload("res://scripts/breach/state_profile.gd")
const FC := preload("res://scripts/breach/flow_contract.gd")

const NO_LEVERAGE := "NO_CAUSAL_LEVERAGE"
const NO_EFFECT := "NO_EFFECT"
const QUALIFIED := "QUALIFIED"
const REFUSED := "REFUSED"


## C0: capacity at the node BEFORE the shell. C1: capacity it would have WITH
## the shell's mass added. Both from the one generic capacity law.
static func leverage(world_pre, node: String, shell_mass: int) -> Dictionary:
	var res := {"eligible": false, "reason": "", "c0": 0, "c1": 0,
		"supply": false, "receiver": false, "node": node}
	var channel: Array = world_pre.flow_channel
	var idx := channel.find(node)
	if idx < 0:
		res["reason"] = "shell is not on a channel node"
		return res
	var c0: int = world_pre.flow_capacity_at(node)
	var base: int = FC.base_capacity()
	var block: int = FC.mass_block()
	var c1: int = maxi(0, c0 - block * shell_mass)
	res["c0"] = c0
	res["c1"] = c1
	if c0 <= 0:
		res["reason"] = "C0 is zero: the node had already collapsed"
		return res
	if c1 >= c0:
		res["reason"] = "C1 is not below C0: the shell would not reduce capacity"
		return res

	## SUPPLY: material must actually reach this node pre-treatment. The head
	## always receives from the source; a later node needs material upstream or
	## already present.
	var supply := false
	if idx == 0:
		supply = FC.source_rate() > 0
	else:
		if int(world_pre.flow_material.get(node, 0)) > 0:
			supply = true
		for i in idx:
			if int(world_pre.flow_material.get(str(channel[i]), 0)) > 0:
				supply = true
	res["supply"] = supply
	if not supply:
		res["reason"] = "no pre-treatment supply reaches the node"
		return res

	## RECEIVER: a downstream node must be able to accept. The tail discharges
	## out of the channel, which always accepts.
	var receiver := false
	if idx == channel.size() - 1:
		receiver = true
	else:
		receiver = world_pre.flow_capacity_at(str(channel[idx + 1])) > 0
	res["receiver"] = receiver
	if not receiver:
		res["reason"] = "no downstream node can receive pre-treatment"
		return res

	res["eligible"] = true
	res["reason"] = "C0 %d > 0, C1 %d < C0, supply, receiver" % [c0, c1]
	return res


## Rebuild a world from a layout description. Deterministic and model-free.
static func _build(contract, spec: Dictionary):
	var w = WorldStateScript.new()
	w.contract = contract
	w.round_id = str(spec.get("round_id", "REPLAY"))
	for loc in spec.get("locations", []):
		var l: Dictionary = loc
		w.add_location(str(l["id"]), str(l.get("name", l["id"])),
			(l.get("neighbors", []) as Array).duplicate())
	for obj in spec.get("objects", []):
		var o: Dictionary = obj
		w.add_object(str(o["id"]), str(o["kind"]), str(o["at"]))
	w.flow_channel = (spec.get("flow_channel", []) as Array).duplicate()
	return w


## THE ANCESTOR-REMOVAL REPLAY.
##
## Replays the SAME operation log twice: once as recorded (treated), once with
## the ancestor's shell suppressed (counterfactual). Descendants of the removed
## ancestor never come into existence in the second pass, because the flow that
## would have produced them never happens -- they are not stripped by name,
## they simply are not caused.
##
## Returns both worlds plus the verdict. Refuses rather than guessing when the
## inputs do not support a replay.
static func counterfactual(contract, profile, spec: Dictionary,
		oplog: Array, ancestor: Dictionary) -> Dictionary:
	var res := {"status": REFUSED, "reason": "", "verdict": {},
		"tau": -1, "ancestor_event_id": -1}
	if ancestor.is_empty():
		res["reason"] = "no ancestor supplied"
		return res
	var agent := str(ancestor.get("agent", ""))
	var tau := int(ancestor.get("tau", -1))
	var anc_event := int(ancestor.get("causing_event_id", -1))
	if agent.is_empty() or tau < 0:
		res["reason"] = "ancestor is missing agent or tau"
		return res
	if anc_event < 0:
		res["reason"] = "ancestor has no causing_event_id: ancestry is tampered or absent"
		return res
	if spec.is_empty() or (spec.get("locations", []) as Array).is_empty():
		res["reason"] = "no starting snapshot to replay from"
		return res
	var seen_event := false
	for op in oplog:
		if int((op as Dictionary).get("event_id", -1)) == anc_event:
			seen_event = true
	if not seen_event:
		res["reason"] = ("ancestor event %d is not in the oplog: ancestry is "
			+ "tampered or the log is truncated") % anc_event
		return res
	res["tau"] = tau
	res["ancestor_event_id"] = anc_event

	var treated = _replay(contract, spec, oplog, "")
	var counter = _replay(contract, spec, oplog, agent)
	if treated == null or counter == null:
		res["reason"] = "replay failed"
		return res

	var m: Dictionary = SP.membership(treated["world_at_tau"], [])
	var v: Dictionary = profile.verdict(counter["world"], treated["world"], m)
	res["verdict"] = v
	res["treated"] = {
		"complete": profile.state_hash(treated["world"]),
		"causal": profile.causal_hash(treated["world"], m),
		"unrelated": profile.unrelated_hash(treated["world"], m),
	}
	res["counterfactual"] = {
		"complete": profile.state_hash(counter["world"]),
		"causal": profile.causal_hash(counter["world"], m),
		"unrelated": profile.unrelated_hash(counter["world"], m),
	}
	if not bool(v["unrelated_identical"]):
		res["status"] = REFUSED
		res["reason"] = ("unrelated state diverged: the replay changed "
			+ "something the ancestor could not have caused")
		return res
	if bool(v["causal_differs"]) and bool(v["complete_differs"]):
		res["status"] = QUALIFIED
		res["reason"] = "removing the ancestor eliminated the later difference"
	else:
		res["status"] = NO_EFFECT
		res["reason"] = "removing the ancestor changed nothing"
	return res


## One deterministic pass. suppress_shell_for names the agent whose shell is
## withheld; empty means the treated world.
static func _replay(contract, spec: Dictionary, oplog: Array,
		suppress_shell_for: String):
	var w = _build(contract, spec)
	var agents := {}
	for ag in spec.get("agents", []):
		var a: Dictionary = ag
		agents[str(a["name"])] = AgentStateScript.new(str(a["name"]),
			str(a.get("model_id", "replay")), str(a.get("species_id", "replay")),
			str(a.get("instance_id", "replay#1")), int(a.get("energy", 100)),
			str(a["at"]))
	var bus = BusScript.new()
	var tau_snapshot = null
	var tau := int(spec.get("tau", -1))
	for op in oplog:
		var o: Dictionary = op
		var actor := str(o.get("actor", ""))
		if not agents.has(actor):
			continue
		var before_alive: bool = agents[actor].alive
		Reducer.apply(w, agents, actor, str(o.get("operation", "")),
			(o.get("fields", {}) as Dictionary), bus,
			int(o.get("event_id", -1)))
		## SUPPRESSION: the counterfactual is a world where this body left no
		## mass. Nothing else about the turn changes.
		if suppress_shell_for != "" and actor == suppress_shell_for \
				and before_alive and not agents[actor].alive:
			var sid := "shell_%s" % actor.to_lower()
			if w.objects.has(sid):
				w.objects.erase(sid)
				for lk in w.locations.keys():
					(w.locations[lk]["objects"] as Array).erase(sid)
		if not w.flow_channel.is_empty():
			w.flow_advance(w.tick)
		if w.tick == tau:
			tau_snapshot = _clone(contract, w)
		w.tick += 1
	return {"world": w, "world_at_tau":
		tau_snapshot if tau_snapshot != null else w}


static func _clone(contract, w):
	var c = WorldStateScript.new()
	c.contract = contract
	c.round_id = w.round_id
	c.tick = w.tick
	c.locations = w.locations.duplicate(true)
	c.doors = w.doors.duplicate(true)
	c.objects = w.objects.duplicate(true)
	c.vault_slots = w.vault_slots.duplicate(true)
	c.flow_channel = (w.flow_channel as Array).duplicate()
	c.flow_material = w.flow_material.duplicate(true)
	c.flow_deposits = w.flow_deposits
	return c
