extends SceneTree

# Headless qualification for CoherenceEngine.
# Run:  godot --headless --script scripts/arena/coherence_selftest.gd
#
# This gate used to seed from entropy and evaluate a fixed criterion against a
# single random draw, so it answered differently on identical code and could
# trip the night supervisor's integrity stop at 3 a.m. for no defect. It now
# runs a FIXED seed set and gates on the WORST case.
#
# The seeds, the 0.2 criterion and the decision tree were frozen in
# docs/results/COHERENCE_GATE_PREREG.md before this file was written.
#
# Exit 0  every seed separates by more than 0.2
# Exit 2  at least one does not -- a real finding, not a threshold to widen

const CoherenceEngineScript = preload("res://scripts/arena/coherence_engine.gd")

# Preregistered: the first twenty positive integers, named before any was run.
# Changing, adding or dropping one is an amendment and needs its own commit.
const SEEDS: Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
					  11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
const MARGIN_REQUIRED := 0.2


func _init() -> void:
	var engine = CoherenceEngineScript.new()
	var res: Dictionary = engine.self_test_suite(SEEDS)

	print("--------------------------------------------------------")
	print("COHERENCE ENGINE QUALIFICATION -- %d fixed seeds" % SEEDS.size())
	print("--------------------------------------------------------")
	print("  seed    echo r   argue r   margin   sep")
	for row in res["rows"]:
		print("  %4d    %6.3f   %7.3f   %6.3f   %s" % [
			int(row["seed"]), float(row["echo_r"]), float(row["argue_r"]),
			float(row["margin"]), "yes" if bool(row["separated"]) else "NO"])
	print("")
	print("  worst margin  %.3f  (seed %d)" % [
		float(res["worst_margin"]), int(res["worst_seed"])])
	print("  required      > %.3f" % MARGIN_REQUIRED)
	print("")

	# Determinism is part of the qualification, not an assumption about it:
	# re-run the worst seed and require the identical number back. A gate that
	# claims to be reproducible should have to prove it every time it runs.
	var repeat: Dictionary = engine.self_test(int(res["worst_seed"]))
	var repeat_margin: float = float(repeat["echo_r"]) - float(repeat["argue_r"])
	if not is_equal_approx(repeat_margin, float(res["worst_margin"])):
		print("  RESULT: NOT DETERMINISTIC — re-running seed %d gave %.6f, not"
			% [int(res["worst_seed"]), repeat_margin])
		print("  %.6f. The seeding does not fully determine the run; some other"
			% float(res["worst_margin"]))
		print("  entropy source is still in the path. DO NOT wire this in.")
		# `quit()` QUEUES the exit; it does not return. Without this `return`,
		# execution fell through to the separation branch below and the final
		# quit(0) overrode this one -- a red gate exiting GREEN. Found by
		# sabotage, not by reading the code.
		quit(2)
		return
	print("  determinism   seed %d reproduced exactly" % int(res["worst_seed"]))

	if bool(res["all_separated"]):
		print("")
		print("  RESULT: SEPARATED on every seed. Worst-case margin clears 0.2.")
		print("  The detector can tell an echo chamber from a real argument on")
		print("  every preregistered input, and says so identically each run.")
		quit(0)
	else:
		print("")
		print("  RESULT: NOT SEPARATED on at least one seed. Per the frozen")
		print("  decision tree this stays RED: the threshold does not move, no")
		print("  seed is dropped, N is not reduced. The detector fails to")
		print("  separate on some inputs and must not be wired into the arena.")
		quit(2)
