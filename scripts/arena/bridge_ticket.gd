extends RefCounted
class_name BridgeTicket

## The ONLY view the scheduler is allowed to have of a request.
##
## THE LOCALITY BOUNDARY. The bridge controls scarce machinery. It must never
## become the invisible game master. A scheduler that can read the prompt can
## decide that one agent's thought is more interesting than another's, and at
## that moment the arena stops being a substrate and starts being an author.
##
## So the payload -- messages, prompt, schema, whatever the agent is actually
## asking -- is held SEPARATELY, keyed by request_id, and is opaque until
## dispatch. The scheduler sees resource facts and timing only:
##
##   ALLOWED_KEYS = [request_id, agent_id, model_id, compute_class,
##                   latency_class, submitted_at_ms, attempts]
##
## This mirrors the blind resolver in the compute arbiter, and it is enforced
## structurally rather than by discipline: `scheduling_view()` builds a fresh
## dictionary containing exactly these keys, so a semantic field added to a
## request later cannot leak into a scheduling decision by accident.
##
## NOT ALLOWED, ever: prompt text, messages, explanation, agent intent, agent
## name-as-meaning, priority-because-important, or any field describing WHY.

const ALLOWED_KEYS := ["request_id", "agent_id", "model_id", "compute_class",
	"latency_class", "submitted_at_ms", "attempts"]

## Resource classes. These describe COST, not merit.
const CLASS_SMALL := "SMALL"
const CLASS_NORMAL := "NORMAL"
const CLASS_HEAVY := "HEAVY"
const COMPUTE_CLASSES := [CLASS_SMALL, CLASS_NORMAL, CLASS_HEAVY]

## Latency classes. These describe whether anything is WAITING on the result,
## which is a scheduling fact, not a statement about value.
const LATENCY_INTERACTIVE := "INTERACTIVE"
const LATENCY_BACKGROUND := "BACKGROUND"
const LATENCY_CLASSES := [LATENCY_INTERACTIVE, LATENCY_BACKGROUND]

var request_id: String = ""
var agent_id: String = ""
var model_id: String = ""
var compute_class: String = CLASS_NORMAL
var latency_class: String = LATENCY_INTERACTIVE
var submitted_at_ms: int = 0
var attempts: int = 0

## The opaque payload. The scheduler never reads this; only dispatch does.
var _payload: Dictionary = {}


static func make(rid: String, agent: String, model: String,
		payload: Dictionary, compute: String = CLASS_NORMAL,
		latency: String = LATENCY_INTERACTIVE) -> BridgeTicket:
	var t := BridgeTicket.new()
	t.request_id = rid
	t.agent_id = agent
	t.model_id = model
	t.compute_class = compute if COMPUTE_CLASSES.has(compute) else CLASS_NORMAL
	t.latency_class = (latency if LATENCY_CLASSES.has(latency)
		else LATENCY_INTERACTIVE)
	t.submitted_at_ms = Time.get_ticks_msec()
	t._payload = payload.duplicate(true)
	return t


## What the scheduler may look at. A fresh dictionary of exactly ALLOWED_KEYS.
func scheduling_view() -> Dictionary:
	return {
		"request_id": request_id,
		"agent_id": agent_id,
		"model_id": model_id,
		"compute_class": compute_class,
		"latency_class": latency_class,
		"submitted_at_ms": submitted_at_ms,
		"attempts": attempts,
	}


## Handed to the transport at dispatch, never to a scheduling decision.
func payload() -> Dictionary:
	return _payload.duplicate(true)


func age_ms(now_ms: int) -> int:
	return maxi(now_ms - submitted_at_ms, 0)
