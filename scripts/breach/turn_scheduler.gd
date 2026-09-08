extends RefCounted
class_name TurnScheduler

## ROTATING INITIATIVE, RECORDED.
##
## Five agents acting in a fixed order gives the first mover a structural
## advantage that is INDISTINGUISHABLE FROM A MODEL DIFFERENCE. With one round
## and no replication of position, turn order is not estimable -- the same
## problem as arm order in RUNTIME-MEMORY, where it is a stated limitation and
## never a covariate (Amendment 3).
##
## Fixing it costs nothing now and is unrecoverable afterwards: rotate the
## starting agent every cycle and write the order into every event. Then
## "GEMMATRON opened the vault" can never quietly mean "GEMMATRON went first".
##
## Rotation is deterministic, not random. A replay must reproduce the exact
## order, and an RNG in the scheduler would be one more thing that has to be
## seeded, recorded and trusted.

var roster: Array = []          ## display names, fixed canonical order
var cycle: int = 0              ## complete passes through the roster
var index_in_cycle: int = 0


func _init(p_roster: Array) -> void:
	roster = p_roster.duplicate()


## The order for the current cycle: the roster rotated left by `cycle`.
func current_order() -> Array:
	var n := roster.size()
	if n == 0:
		return []
	var out: Array = []
	for i in n:
		out.append(roster[(i + cycle) % n])
	return out


func current_actor() -> String:
	var order := current_order()
	if order.is_empty():
		return ""
	return str(order[index_in_cycle % order.size()])


## Advance one turn. Returns true when a full cycle completed.
func advance() -> bool:
	index_in_cycle += 1
	if index_in_cycle >= roster.size():
		index_in_cycle = 0
		cycle += 1
		return true
	return false


## Skip agents that cannot act, without consuming the world clock. Returns the
## next actor able to act, or "" when nobody can -- which is a round-end
## condition, not an error.
func next_able_actor(agents: Dictionary) -> String:
	var attempts := 0
	while attempts < roster.size():
		var name := current_actor()
		if agents.has(name) and agents[name].can_act():
			return name
		advance()
		attempts += 1
	return ""


func anyone_can_act(agents: Dictionary) -> bool:
	for n in roster:
		if agents.has(n) and agents[n].can_act():
			return true
	return false


## Written into every event so initiative is auditable after the fact.
func initiative_record() -> Dictionary:
	return {"cycle": cycle, "index_in_cycle": index_in_cycle,
		"order": current_order()}
