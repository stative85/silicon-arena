extends RefCounted
class_name BreachRound

## ONE ROUND OF THE BREACH. The loop that turns observations into events.
##
##   observe -> decide -> parse -> reduce -> record -> route -> advance
##
## Every step is deterministic given the deciders. Nothing here knows what a
## coalition is.
##
## ROUND ENDS ON, and only on:
##     vault opened
##     no agent able to act
##     frozen time horizon reached
##
## VAULT FAILURE IS A VALID RESULT and is reported as one. A round where five
## models fail to coordinate is a finding about five models, not a bug to be
## fixed by making the vault easier.

const CanonicalOperationScript := preload("res://scripts/breach/canonical_operation.gd")
const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const AgentStateScript := preload("res://scripts/breach/agent_state.gd")
const ArenaLayoutScript := preload("res://scripts/breach/arena_layout.gd")
const WorldReducerScript := preload("res://scripts/breach/world_reducer.gd")
const ObservationBuilderScript := preload("res://scripts/breach/observation_builder.gd")
const OutputParserScript := preload("res://scripts/breach/output_parser.gd")
const TurnSchedulerScript := preload("res://scripts/breach/turn_scheduler.gd")
const MassContractScript := preload("res://scripts/breach/mass_contract.gd")
const MessageBusScript := preload("res://scripts/breach/message_bus.gd")
const ReplayLogScript := preload("res://scripts/breach/replay_log.gd")
const EventRecordScript := preload("res://scripts/breach/event_record.gd")
const CO := CanonicalOperationScript

const END_VAULT_OPENED := "VAULT_OPENED"
const END_NO_AGENT_CAN_ACT := "NO_AGENT_CAN_ACT"
const END_TIME_HORIZON := "TIME_HORIZON"
## Not a round outcome. The round never started: the world it was built on does
## not satisfy MASS_CONTRACT_V1.
const END_MASS_CONTRACT_VIOLATION := "MASS_CONTRACT_VIOLATION"

var world
var agents: Dictionary = {}
var bus
var scheduler
var log
var deciders: Dictionary = {}
var next_event_id: int = 1
var horizon_ticks: int = 240
var public_lines: Array = []
var ended: bool = false
var end_reason: String = ""


## `roster` is Array[{display_name, model_id, species_id, instance_id}] in
## canonical order. Order here is roster order, NOT turn order -- the scheduler
## rotates initiative so that roster position confers no advantage.
## p_world exists so a FIXTURE can drive the real ignition path with a world the
## canonical layout would never produce -- an undeclared object kind, say. It is
## not a production parameter: every real round passes nothing and gets the
## canonical layout. Without it the ignition refusal below would be an untested
## branch, and a gate whose abort path has never executed is not a gate.
func _init(round_id: String, roster: Array, p_deciders: Dictionary,
		p_horizon_ticks: int = 240, p_world = null) -> void:
	if p_world == null:
		world = WorldStateScript.new()
		ArenaLayoutScript.build(world, round_id)
	else:
		world = p_world
	bus = MessageBusScript.new()
	log = ReplayLogScript.new(round_id)
	deciders = p_deciders
	horizon_ticks = p_horizon_ticks

	var names: Array = []
	for r in roster:
		var d: Dictionary = r
		var nm := str(d["display_name"])
		names.append(nm)
		agents[nm] = AgentStateScript.new(nm, str(d["model_id"]),
			str(d["species_id"]), str(d["instance_id"]),
			ArenaLayoutScript.START_ENERGY, ArenaLayoutScript.spawn_of(nm))
	scheduler = TurnSchedulerScript.new(names)
	log.declare_roster(agents)

	## IGNITION VALIDATION. Every object in the built world must have a declared
	## mass before the round may advance one tick. An undeclared kind is a
	## CONTRACT VIOLATION, not a light object, and letting it through would mean
	## running physics that the frozen contract does not describe.
	##
	## The abort happens here, before any observation is built and before any
	## turn is taken, so a violating world produces no round state at all --
	## nothing to misread later as a short or unlucky round.
	var violations: Array = MassContractScript.validate_world(world)
	if not violations.is_empty():
		mass_violations = violations
		var parts: Array = []
		for v in violations:
			parts.append("%s (kind '%s')" % [str(v["object"]), str(v["kind"])])
		abort_reason = "MASS_KIND_UNDECLARED: " + ", ".join(parts)
		push_error(abort_reason)
		ended = true
		end_reason = END_MASS_CONTRACT_VIOLATION


## Populated only when ignition validation refused to start the round.
var mass_violations: Array = []
var abort_reason: String = ""


func _agents_dict() -> Dictionary:
	var out := {}
	var names: Array = agents.keys()
	names.sort()
	for n in names:
		out[n] = agents[n].to_dict()
	return out


func state_hash() -> String:
	return EventRecordScript.sha16({"world": world.to_dict(),
		"agents": _agents_dict()})


## Execute a single turn. Returns the EventRecord that was appended.
func step() -> Dictionary:
	if ended:
		return {}
	var actor_name: String = scheduler.next_able_actor(agents)
	if actor_name.is_empty():
		_end(END_NO_AGENT_CAN_ACT)
		return {}

	var actor = agents[actor_name]
	var observation := ObservationBuilderScript.build(world, agents, actor_name,
		bus, public_lines)
	var before := state_hash()

	var decider = deciders.get(actor_name)
	var spoken := {"raw": "", "latency_ms": -1, "params": {}}
	if decider != null:
		spoken = decider.decide(observation, actor)

	var parsed := OutputParserScript.parse(str(spoken.get("raw", "")))

	var ev = EventRecordScript.new()
	ev.event_id = next_event_id
	next_event_id += 1
	ev.tick = world.tick
	ev.actor = actor_name
	ev.model_id = actor.model_id
	ev.species_id = actor.species_id
	ev.instance_id = actor.instance_id
	ev.operation = str(parsed["operation"])
	ev.fields = (parsed["fields"] as Dictionary).duplicate()
	ev.raw_output = str(parsed["raw"])
	ev.parse_failure = str(parsed["parse_failure"])
	ev.parse_detail = str(parsed["parse_detail"])
	ev.observation_hash = EventRecordScript.sha16(observation)
	ev.before_state_hash = before
	ev.initiative = scheduler.initiative_record()
	ev.latency_ms = int(spoken.get("latency_ms", -1))
	ev.generation_params = (spoken.get("params", {}) as Dictionary).duplicate()

	if bool(parsed["ok"]):
		var out := WorldReducerScript.apply(world, agents, actor_name,
			ev.operation, ev.fields, bus)
		ev.accepted = bool(out["ok"])
		ev.refusal_reason = str(out["reason"])
		ev.effects = (out["effects"] as Array).duplicate()
		if ev.accepted:
			_route_messages(actor_name, ev)
			_write_memory(actor, parsed, ev.event_id)
	else:
		## NO_OP: the turn is consumed, no energy charged, raw text retained.
		ev.accepted = false
		ev.refusal_reason = "invalid output: " + ev.parse_failure

	ev.after_state_hash = state_hash()
	log.append(ev)
	_record_public_line(ev)

	world.tick += 1
	scheduler.advance()

	if world.vault_open:
		_end(END_VAULT_OPENED)
	elif world.tick >= horizon_ticks:
		_end(END_TIME_HORIZON)
	elif not scheduler.anyone_can_act(agents):
		_end(END_NO_AGENT_CAN_ACT)
	return ev.to_dict()


func _route_messages(actor_name: String, ev) -> void:
	if ev.operation == CO.MESSAGE_PUBLIC:
		bus.post_public(actor_name, str(ev.fields.get("text", "")),
			world.tick, ev.event_id)
	elif ev.operation == CO.MESSAGE_PRIVATE:
		var to := str(ev.fields.get("target", ""))
		bus.post_private(actor_name, to, str(ev.fields.get("text", "")),
			world.tick, ev.event_id)
		if agents.has(to):
			agents[to].inbox.append({"tick": world.tick, "from": actor_name,
				"text": str(ev.fields.get("text", "")),
				"event_id": ev.event_id})


func _write_memory(actor, parsed: Dictionary, event_id: int) -> void:
	var text := str(parsed.get("memory_write", ""))
	if text.is_empty():
		return
	actor.memory.write(text, [event_id], world.tick,
		int(parsed.get("memory_replace_index", -1)))


## The public stream carries the FACT of a private message, never its body.
func _record_public_line(ev) -> void:
	if not ev.accepted:
		return
	var target := str(ev.fields.get("target", ""))
	var extra := ""
	if ev.operation == CO.MESSAGE_PRIVATE:
		extra = "(body not public)"
	elif ev.operation == CO.MESSAGE_PUBLIC:
		extra = "\"" + str(ev.fields.get("text", "")) + "\""
	public_lines.append(ObservationBuilderScript.public_line(
		ev.tick, ev.actor, ev.operation, target, extra))
	if public_lines.size() > ObservationBuilderScript.PUBLIC_EVENT_WINDOW:
		public_lines.remove_at(0)


func _end(reason: String) -> void:
	ended = true
	end_reason = reason


func run_to_completion(max_steps: int = 2000) -> Dictionary:
	var steps := 0
	while not ended and steps < max_steps:
		step()
		steps += 1
	return outcome()


func outcome() -> Dictionary:
	var per_agent := {}
	var names: Array = agents.keys()
	names.sort()
	for n in names:
		var a = agents[n]
		per_agent[n] = {"energy": a.energy, "position": a.position,
			"inventory": a.inventory.duplicate(), "alive": a.alive,
			"memory_entries": a.memory.size()}
	var no_ops := 0
	var refused := 0
	for e in log.events:
		if str(e["operation"]) == CO.NO_OP:
			no_ops += 1
		elif not bool(e["accepted"]):
			refused += 1
	return {
		"round_id": world.round_id,
		"ended": ended,
		"end_reason": end_reason,
		"ticks": world.tick,
		"vault_open": world.vault_open,
		"vault_opened_at_tick": world.vault_opened_at_tick,
		"events": log.size(),
		"no_op_count": no_ops,
		"refused_count": refused,
		"chain_head": log.head_hash(),
		"agents": per_agent,
	}
