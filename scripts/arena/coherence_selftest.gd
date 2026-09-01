extends SceneTree

# Headless harness for CoherenceEngine.self_test().
# Run:  Godot_v4.6-stable_win64_console.exe --headless --script scripts/arena/coherence_selftest.gd
#
# Exits 0 only if the engine separates a synthetic echo chamber from a
# synthetic real argument. Exit 2 means the detector measures nothing and
# must not be wired into the arena.

const CoherenceEngineScript = preload("res://scripts/arena/coherence_engine.gd")


func _init() -> void:
	var engine = CoherenceEngineScript.new()
	var res: Dictionary = engine.self_test()

	print("--------------------------------------------------------")
	print("COHERENCE ENGINE SELF-TEST")
	print("--------------------------------------------------------")
	print("  echo chamber  (all agents agree, same text repeated):")
	print("      order r   = %.3f" % float(res["echo_r"]))
	print("      H_min     = %.3f bits/bit" % float(res["echo_h"]))
	print("  real argument (agents disagree, distinct text):")
	print("      order r   = %.3f" % float(res["argue_r"]))
	print("      H_min     = %.3f bits/bit" % float(res["argue_h"]))
	print("")
	if bool(res["separated"]):
		print("  RESULT: SEPARATED — echo r exceeds argument r by >0.2.")
		print("  The detector can tell the two apart. Safe to wire in.")
		quit(0)
	else:
		print("  RESULT: NOT SEPARATED — the detector cannot distinguish an")
		print("  echo chamber from a real argument. It would fire at random.")
		print("  DO NOT wire this into the arena until the math is fixed.")
		quit(2)
