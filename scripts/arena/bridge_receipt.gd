extends RefCounted
class_name BridgeReceipt

## An immutable record of one request's passage through the bridge.
##
## WHY EVERY REQUEST GETS ONE. The benchmark's most damaging failure was
## invisible: a model 50-100x slow that answered every request successfully and
## reported `fail 0` for five consecutive cases. Nothing in the aggregate could
## show it, because the aggregate had no per-request record of when things
## happened -- only whether they succeeded.
##
## A receipt records timing and residency at the moment of the call, so a
## degradation is reconstructable after the fact instead of inferred. It is the
## bridge's equivalent of the arena's provenance discipline: the scheduler may
## be blind, but it is never unaccountable.
##
## Receipts contain NO payload and NO model output. They are resource facts.
## Storing the prompt here would smuggle semantics into the audit trail and
## give a future scheduler something to read.

const STATUS_OK := "OK"
const STATUS_TIMEOUT := "TIMEOUT"
const STATUS_HTTP_ERROR := "HTTP_ERROR"
const STATUS_REJECTED := "REJECTED"
const STATUS_CANCELLED := "CANCELLED"


static func make(ticket: BridgeTicket) -> Dictionary:
	return {
		"request_id": ticket.request_id,
		"agent_id": ticket.agent_id,
		"model_id": ticket.model_id,
		"compute_class": ticket.compute_class,
		"latency_class": ticket.latency_class,
		"submitted_at_ms": ticket.submitted_at_ms,
		"dispatched_at_ms": 0,
		"first_token_at_ms": 0,
		"finished_at_ms": 0,
		"queue_delay_ms": 0,
		"ttft_ms": -1,
		"total_ms": -1,
		"generated_tokens": 0,
		"decode_tps": 0.0,
		"attempts": ticket.attempts,
		"model_state_before": "",
		"model_state_after": "",
		"resident_set": [],
		"health_verdict": "",
		"recovery_event": "",
		"status": "",
	}


## Seal a receipt. Derived timings are computed once, here, so no two call
## sites can disagree about what "total" means.
static func seal(r: Dictionary, status: String) -> Dictionary:
	var out := r.duplicate(true)
	out["status"] = status
	if int(out["dispatched_at_ms"]) > 0:
		out["queue_delay_ms"] = maxi(
			int(out["dispatched_at_ms"]) - int(out["submitted_at_ms"]), 0)
	if int(out["finished_at_ms"]) > 0 and int(out["dispatched_at_ms"]) > 0:
		out["total_ms"] = maxi(
			int(out["finished_at_ms"]) - int(out["dispatched_at_ms"]), 0)
	if int(out["first_token_at_ms"]) > 0 and int(out["dispatched_at_ms"]) > 0:
		out["ttft_ms"] = maxi(
			int(out["first_token_at_ms"]) - int(out["dispatched_at_ms"]), 0)
	var gen_ms := 0
	if int(out["finished_at_ms"]) > 0 and int(out["first_token_at_ms"]) > 0:
		gen_ms = int(out["finished_at_ms"]) - int(out["first_token_at_ms"])
	if gen_ms > 0 and int(out["generated_tokens"]) > 0:
		out["decode_tps"] = float(out["generated_tokens"]) / (float(gen_ms) / 1000.0)
	return out


## Stable one-line rendering for journals and logs.
static func line(r: Dictionary) -> String:
	return "%s %s %s q=%dms ttft=%dms total=%dms tok=%d %s %s->%s %s" % [
		str(r.get("request_id", "?")), str(r.get("agent_id", "?")),
		str(r.get("model_id", "?")), int(r.get("queue_delay_ms", 0)),
		int(r.get("ttft_ms", -1)), int(r.get("total_ms", -1)),
		int(r.get("generated_tokens", 0)), str(r.get("status", "?")),
		str(r.get("model_state_before", "")),
		str(r.get("model_state_after", "")),
		str(r.get("health_verdict", "")),
	]
