extends RefCounted
class_name MessageBus

## PUBLIC AND PRIVATE CHANNELS, WITH EXACT PROVENANCE.
##
## The bus routes and records. It does not summarise, rank, filter by relevance,
## or mark anything as important -- a host that decided which message mattered
## would be authoring the behaviour it claims to be observing.
##
## A private message is delivered to exactly one recipient and is invisible to
## everyone else, including in the public event stream, where it appears only as
## the FACT that a private message occurred (sender, recipient, tick) with no
## body. That asymmetry is the point of BREACH-1 later: you cannot disable
## something the world never actually had.

var public_log: Array = []      ## Array[{tick, sender, text, event_id}]
var private_log: Array = []     ## Array[{tick, sender, recipient, text, event_id}]


func post_public(sender: String, text: String, tick: int,
		event_id: int) -> Dictionary:
	var rec := {"tick": tick, "sender": sender, "text": text,
		"event_id": event_id}
	public_log.append(rec)
	return rec


func post_private(sender: String, recipient: String, text: String, tick: int,
		event_id: int) -> Dictionary:
	var rec := {"tick": tick, "sender": sender, "recipient": recipient,
		"text": text, "event_id": event_id}
	private_log.append(rec)
	return rec


## Public messages an agent can see, most recent last.
func public_since(tick_from: int, limit: int = 12) -> Array:
	var out: Array = []
	for m in public_log:
		if int(m["tick"]) >= tick_from:
			out.append(m)
	if out.size() > limit:
		out = out.slice(out.size() - limit, out.size())
	return out


## Private messages addressed to this agent only. Never anyone else's.
func private_for(recipient: String, limit: int = 12) -> Array:
	var out: Array = []
	for m in private_log:
		if str(m["recipient"]) == recipient:
			out.append(m)
	if out.size() > limit:
		out = out.slice(out.size() - limit, out.size())
	return out


## What the PUBLIC stream is allowed to know about a private message: that it
## happened, between whom, and when. Not what it said.
func private_metadata_since(tick_from: int, limit: int = 12) -> Array:
	var out: Array = []
	for m in private_log:
		if int(m["tick"]) >= tick_from:
			out.append({"tick": m["tick"], "sender": m["sender"],
				"recipient": m["recipient"], "event_id": m["event_id"]})
	if out.size() > limit:
		out = out.slice(out.size() - limit, out.size())
	return out


func to_dict() -> Dictionary:
	return {"public_count": public_log.size(),
		"private_count": private_log.size()}
