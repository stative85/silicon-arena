extends SceneTree

## How often does the remembered betrayal actually FLIP the outcome, rather than
## merely lowering the probability?
##
## This exists so the live proof does not have to be run at a hand-picked seed
## and presented as typical. It reports the flip rate across many seeds and names
## the first flipping seed, so any single-seed demonstration can be labelled as
## an illustration of a measured rate rather than a lucky draw.

const Ruleset := preload("res://scripts/arena/systemic_ruleset.gd")

func _init() -> void:
	var neutral := {}
	for axis in Ruleset.WEIGHTS:
		neutral[axis] = 0.0
	var betrayed := neutral.duplicate()
	betrayed["trust"] = -0.25
	betrayed["resentment"] = 0.25
	betrayed["suspicion"] = 0.25

	var n := 5000
	var flips := 0
	var reverse := 0
	var same := 0
	var first_flip := -1
	for i in n:
		var seed_value := 177101 + i
		var a: Dictionary = Ruleset.resolve_alliance({"axes": neutral}, {},
			seed_value, "agent-02", "agent-01", 1)
		var b: Dictionary = Ruleset.resolve_alliance({"axes": betrayed}, {},
			seed_value, "agent-02", "agent-01", 1)
		if a["accepted"] and not b["accepted"]:
			flips += 1
			if first_flip < 0:
				first_flip = seed_value
		elif not a["accepted"] and b["accepted"]:
			reverse += 1
		else:
			same += 1

	print("flip scan over %d seeds (neutral vs betrayed, same seed each pair)" % n)
	print("  outcome unchanged            %5d  (%.2f%%)" % [same, 100.0 * same / n])
	print("  accepted -> refused          %5d  (%.2f%%)" % [flips, 100.0 * flips / n])
	print("  refused  -> accepted         %5d  (%.2f%%)" % [reverse, 100.0 * reverse / n])
	print("  first seed that flips: %d" % first_flip)
	print("")
	print("The betrayal changes the ODDS. It decides nothing: in %.1f%% of seeds the" % (100.0 * same / n))
	print("outcome is identical either way, which is what 'soft' means.")
	print("A flip is never guaranteed and must not be filmed as if it were.")
	quit(0)
