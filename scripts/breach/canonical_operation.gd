extends RefCounted
class_name CanonicalOperation

## THE ENTIRE VOCABULARY THE HOST UNDERSTANDS.
##
## Seventeen verbs. Nothing else is an operation, and there is deliberately no
## verb here that names a behaviour: no ALLY, no BETRAY, no TRUST, no LEAD. If
## those things happen they are SEQUENCES of these verbs, named by an analyst
## afterwards and only if the event log supports it.
##
## WRITE THE VERBS. DO NOT WRITE THE BEHAVIOR.
##
## NO_OP is not a verb an agent may choose. It is what the host records when a
## model emits something that is not a valid operation, and it is permanently
## distinct from WAIT -- see output_parser.gd for why that distinction is load
## bearing.

const MOVE := "MOVE"
const OBSERVE := "OBSERVE"
const TAKE := "TAKE"
const DROP := "DROP"
const GIVE := "GIVE"
const OFFER := "OFFER"
const ACCEPT := "ACCEPT"
const DECLINE := "DECLINE"
const MESSAGE_PUBLIC := "MESSAGE_PUBLIC"
const MESSAGE_PRIVATE := "MESSAGE_PRIVATE"
const LOCK := "LOCK"
const UNLOCK := "UNLOCK"
const COMMIT_KEY := "COMMIT_KEY"
const WITHDRAW_KEY := "WITHDRAW_KEY"
const USE_TERMINAL := "USE_TERMINAL"
const WAIT := "WAIT"

## Host-authored only. An agent that emits "NO_OP" is emitting an invalid
## operation and gets a NO_OP recorded for that reason, not for that name.
const NO_OP := "NO_OP"

## Operations an agent may choose.
const AGENT_CHOOSABLE := [
	MOVE, OBSERVE, TAKE, DROP, GIVE, OFFER, ACCEPT, DECLINE,
	MESSAGE_PUBLIC, MESSAGE_PRIVATE, LOCK, UNLOCK,
	COMMIT_KEY, WITHDRAW_KEY, USE_TERMINAL, WAIT,
]

const ALL := AGENT_CHOOSABLE + [NO_OP]

## Required fields per operation, checked structurally by the parser. "target"
## is the object/agent/location/slot the verb acts on; "text" is message body;
## "requested" is the counter-item in an OFFER.
const REQUIRED_FIELDS := {
	MOVE: ["target"],
	OBSERVE: ["target"],
	TAKE: ["target"],
	DROP: ["target"],
	GIVE: ["target", "object"],
	OFFER: ["target", "object", "requested"],
	ACCEPT: ["target"],
	DECLINE: ["target"],
	MESSAGE_PUBLIC: ["text"],
	MESSAGE_PRIVATE: ["target", "text"],
	LOCK: ["target"],
	UNLOCK: ["target"],
	COMMIT_KEY: ["target"],
	WITHDRAW_KEY: ["target"],
	USE_TERMINAL: ["target"],
	WAIT: [],
	NO_OP: [],
}

## Energy is what makes distance and time cost something, which is what makes a
## promise about future action mean anything. These are world constants, not
## tuning knobs to be adjusted once a round looks boring.
const ENERGY_COST := {
	MOVE: 4,
	OBSERVE: 1,
	TAKE: 2,
	DROP: 1,
	GIVE: 1,
	OFFER: 1,
	ACCEPT: 1,
	DECLINE: 1,
	MESSAGE_PUBLIC: 1,
	MESSAGE_PRIVATE: 1,
	LOCK: 2,
	UNLOCK: 2,
	COMMIT_KEY: 3,
	WITHDRAW_KEY: 3,
	USE_TERMINAL: 2,
	WAIT: 0,
	NO_OP: 0,        ## a model that emitted garbage is not charged for it
}


static func is_agent_choosable(op: String) -> bool:
	return AGENT_CHOOSABLE.has(op)


static func is_known(op: String) -> bool:
	return ALL.has(op)


static func energy_cost(op: String) -> int:
	return int(ENERGY_COST.get(op, 0))


static func required_fields(op: String) -> Array:
	var f: Array = REQUIRED_FIELDS.get(op, [])
	return f.duplicate()
