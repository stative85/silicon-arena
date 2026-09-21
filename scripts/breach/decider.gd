extends RefCounted
class_name Decider

## WHERE A MODEL WOULD SPEAK, AND THE OFFLINE STAND-IN FOR IT.
##
## `Decider` is the seam between the world and inference. The world hands it an
## observation packet and it returns RAW TEXT -- not an operation. The text goes
## through OutputParser exactly as a model's would, so the offline path and the
## live path share one parser, one NO_OP rule, one event shape.
##
## That is Law 3 (Production-Path Equivalence) applied before there is a
## production path to diverge from: a scripted decider that returned a clean
## Dictionary would let the whole pipeline be qualified without ever exercising
## the parser that real models will break.
##
## ScriptedDecider exists so the ENTIRE ROUND can be qualified with zero
## inference and zero LM Studio contact -- deterministic, repeatable, and safe
## to run while another experiment owns the GPU.


## Base seam. `decide` returns {raw: String, latency_ms: int, params: Dictionary}
func decide(_observation: Dictionary, _agent) -> Dictionary:
	return {"raw": "", "latency_ms": -1, "params": {}}


class ScriptedDecider extends Decider:
	## Deterministic offline agent. Not a model, not a simulation of one, and
	## not a baseline to compare models against -- it exists to prove the
	## machinery transports operations correctly.
	##
	## It emits real JSON text, including deliberately malformed text on a fixed
	## schedule, so the NO_OP path is exercised by qualification rather than
	## being discovered live.

	var lines: Array = []        ## Array[String] raw outputs, cycled
	var cursor: int = 0

	func _init(p_script: Array) -> void:
		lines = p_script.duplicate()

	func decide(_observation: Dictionary, _agent) -> Dictionary:
		if lines.is_empty():
			return {"raw": "{\"operation\":\"WAIT\"}", "latency_ms": 0,
				"params": {"decider": "scripted"}}
		var raw := str(lines[cursor % lines.size()])
		cursor += 1
		return {"raw": raw, "latency_ms": 0, "params": {"decider": "scripted"}}


class LiveModelDecider extends Decider:
	## THE LIVE SEAM. NOT WIRED, BY DESIGN.
	##
	## Deliberately left unimplemented while RUNTIME-MEMORY owns the runtime:
	## implementing it would invite executing it. When it is wired it must:
	##
	##   * send exactly the observation packet, serialised, and nothing else
	##   * add NO system prompt containing behavioural suggestion -- no "you
	##     are competitive", no "work together", no persona. Identical base
	##     instructions for all five agents, which is what keeps the species
	##     comparison free of PERSONA_CONFOUND
	##   * record real latency_ms and the exact generation parameters
	##   * return raw text UNMODIFIED, including when it is garbage
	##
	## The VRAM question in docs/BREACH_IGNITION_0.md section 0 must be settled
	## before this runs: five models do not fit at context 8192 on an 8 GiB card
	## on the measured evidence.

	var model_id: String = ""
	var instance_id: String = ""

	func _init(p_model: String, p_instance: String) -> void:
		model_id = p_model
		instance_id = p_instance

	func decide(_observation: Dictionary, _agent) -> Dictionary:
		push_error("LiveModelDecider is not wired; see BREACH_IGNITION_0.md s0")
		return {"raw": "", "latency_ms": -1,
			"params": {"model_id": model_id, "instance_id": instance_id}}
