extends SceneTree

## FLOWSCAR4 STEP 1 -- NULL STABILITY. Passed before any treatment counts.
##
##   godot --headless --path . --script tools/flow_null_stability.gd
##
## A mechanism can be locally correct and experimentally useless because its
## UNTREATED dynamics collapse before the treatment arrives. FLOWSCAR2 proved
## exactly that: the 12-tick witness answered its question correctly, and the
## 140-tick live run showed the control world had already fallen into a
## saturated attractor by t=50. By the time a shell landed at t=92 there was no
## causal leverage left, and the counterfactual correctly reported NO EFFECT.
## Good instrument, bad regime.
##
## So the untreated channel must survive the experimental horizon, or nothing
## measured on top of it means anything. No shells, no agents, no models: just
## the channel running alone for longer than a round lasts.
##
## THE BAR, predeclared in FLOW_SCAR_CONTRACT_V1:
##   200 ticks
##   source_rate < unobstructed minimum capacity
##   zero spontaneous deposits
##   all channel nodes remain transmissive
##   no capacity collapse

const WorldStateScript := preload("res://scripts/breach/world_state.gd")
const FC := preload("res://scripts/breach/flow_contract.gd")

var _fail := 0


func ck(label: String, cond: bool) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail += 1


func _init() -> void:
	print("=== FLOWSCAR4 NULL STABILITY -- the untreated channel ===")
	var channel: Array = FC.channel()
	var ticks := FC.null_ticks()
	var rate := FC.source_rate()
	var base := FC.base_capacity()
	print("  channel %s" % str(channel))
	print("  source_rate %d, base_capacity %d, deposit_threshold %d, %d ticks"
		% [rate, base, FC.deposit_threshold(), ticks])
	print("  budget: %d rounds x %d ticks -- the null must outlast a round"
		% [FC.rounds(), FC.ticks_per_round()])
	print("")

	ck("the null horizon outlasts a live round (%d >= %d)"
		% [ticks, FC.ticks_per_round()], ticks >= FC.ticks_per_round())

	var world = WorldStateScript.new()
	world.round_id = "FLOWSCAR4_NULL"
	for i in channel.size():
		var prev: Array = [] if i == 0 else [str(channel[i - 1])]
		world.add_location(str(channel[i]), str(channel[i]), prev)
	world.flow_channel = channel.duplicate()

	## THE ARITHMETIC BAR, checked before the simulation rather than after: on an
	## empty channel every node passes base_capacity, so a source below that can
	## never accumulate. If this fails the run is pointless and the loop below
	## would only decorate the failure with 200 ticks of data.
	var min_cap := -1
	for node in channel:
		var c: int = world.flow_capacity_at(str(node))
		min_cap = c if min_cap < 0 else mini(min_cap, c)
	ck("unobstructed minimum capacity is the base (%d)" % min_cap,
		min_cap == base)
	ck("source rate is BELOW unobstructed minimum capacity (%d < %d)"
		% [rate, min_cap], rate < min_cap)

	var max_material := 0
	var worst_node := ""
	var first_deposit := -1
	var non_transmissive := []
	for t in range(1, ticks + 1):
		var out: Dictionary = world.flow_advance(t)
		if not (out["created"] as Array).is_empty() and first_deposit < 0:
			first_deposit = t
		for node in channel:
			var loc := str(node)
			var m: int = int(world.flow_material.get(loc, 0))
			if m > max_material:
				max_material = m
				worst_node = loc
			if world.flow_capacity_at(loc) <= 0 \
					and not non_transmissive.has(loc):
				non_transmissive.append(loc)

	print("")
	ck("zero spontaneous deposits across %d ticks (first at %s)"
		% [ticks, "never" if first_deposit < 0 else str(first_deposit)],
		first_deposit < 0)
	ck("no node ever became non-transmissive (%s)"
		% ("none" if non_transmissive.is_empty() else str(non_transmissive)),
		non_transmissive.is_empty())
	ck("peak accumulation stayed below the deposit threshold (%d < %d, at %s)"
		% [max_material, FC.deposit_threshold(),
			worst_node if not worst_node.is_empty() else "nowhere"],
		max_material < FC.deposit_threshold())
	ck("no capacity collapse: every node still at base at the horizon",
		_all_at_base(world, channel, base))

	## The channel must still be CARRYING, not merely unblocked. A channel that
	## silently stopped receiving would pass every check above.
	var total := 0
	for node in channel:
		total += int(world.flow_material.get(str(node), 0))
	print("  material in the channel at the horizon: %d" % total)
	ck("the channel is still live at the horizon", total > 0)

	print("")
	if _fail == 0:
		print("NULL STABILITY OK -- the untreated regime survives the horizon")
		quit(0)
	else:
		print("NULL STABILITY FAILED: %d check(s)." % _fail)
		print("Do not run FLOWSCAR4. A treatment measured on a collapsing")
		print("control measures the collapse. The constants do NOT move to")
		print("fix this -- they are frozen, and a failure here is a finding.")
		quit(1)


func _all_at_base(world, channel: Array, base: int) -> bool:
	for node in channel:
		if world.flow_capacity_at(str(node)) != base:
			return false
	return true
