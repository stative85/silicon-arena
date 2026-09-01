extends SceneTree

## Rung 15 inspector: render the canonical proof payload, and refuse to certify
## one that is incomplete.
##
##   Godot --headless --path . --script scripts/arena/proof_dump.gd -- [--json FILE]
##
## Exit codes are the verdict:
##   0 PASS         every required element present and internally consistent
##   1 FAIL         an element is present but wrong
##   2 NO_EVIDENCE  no proof state on disk at all
##   3 PARTIAL      the run is incomplete (missing steps, missing decisions)
##
## A dump that always prints success measures nothing.

const ScarScript := preload("res://scripts/arena/scar_lattice.gd")
const ProofScript := preload("res://scripts/arena/continuity_proof.gd")

const ROOT := "user://scar_alliance_proof"

func _init() -> void:
	var json_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--json" and i + 1 < args.size(): json_path = args[i + 1]

	var state_path := "%s/continuity_proof.json" % ROOT
	if not FileAccess.file_exists(state_path):
		print("RUNG15 NO_EVIDENCE — no proof state on disk at %s" % state_path)
		quit(2)
		return

	var scar = ScarScript.new()
	scar.configure(ROOT)
	scar.load_all()
	var proof = ProofScript.new()
	proof.configure(scar, "silicon_arena", "proof", "rung15-alliance")

	var f := FileAccess.open(state_path, FileAccess.READ)
	var st = JSON.parse_string(f.get_as_text())
	f.close()
	if st is Dictionary:
		proof._steps = st.get("steps", [])
		proof._decisions = st.get("decisions", {})
		proof._axes_before = st.get("axes_before", {})
		proof.set_model_id(str(st.get("model_id", "")))

	var bid := ""
	for e in scar.events_for("silicon_arena"):
		if str(e.get("type", "")) == "BETRAYAL":
			bid = str(e.get("event_id", ""))
	var p: Dictionary = proof.build(bid, "agent-01", "agent-02")

	if json_path != "":
		var jf := FileAccess.open(json_path, FileAccess.WRITE)
		if jf != null:
			jf.store_string(JSON.stringify(p, "  "))
			jf.close()

	# ── render, grouped by the AUTHORITATIVE nine elements ─────────────────
	print("RUNG 15 — WATCH MODE TRUTH SURFACE")
	print("  proof %s   ruleset %s" % [str(p["proof_id"]), str(p["ruleset"])])
	print("  model %s" % str(p["model_id"]))
	print("")
	print("[A1] WHAT HAPPENED")
	print("     %s" % str(p["event"]["summary"]))
	print("     event %s   type %s" % [str(p["event"]["event_id"]), str(p["event"]["type"])])
	print("[A9] ORIGIN: %s%s" % [str(p["event"]["origin"]),
		"  (STAGED — not emergent)" if p["event"]["origin_is_controlled"] else ""])
	print("")
	print("[A2] WHO WITNESSED IT")
	print("     saw it:      %s" % ", ".join(p["witnesses"]["witness_ids"]))
	print("     did NOT:     %s" % (", ".join(p["witnesses"]["non_witness_ids"])
		if not p["witnesses"]["non_witness_ids"].is_empty() else "(nobody)"))
	print("")
	print("[A3] WHO WAS AFFECTED: %s — %s" % [str(p["affected"]["status"]),
		str(p["affected"]["note"])])
	print("")
	print("[A4/A5] WHAT EACH AGENT REMEMBERS, AND AS WHAT KIND OF CLAIM")
	for fr in p["frames"]["entries"]:
		if not fr["holds_memory"]:
			print("     %-10s %s — %s" % [str(fr["agent_id"]), str(fr["status"]),
				str(fr["note"])])
			continue
		print("     %-10s %s / %s / %s" % [str(fr["agent_id"]), str(fr["claim_kind"]),
			str(fr["acquisition_mode"]), str(fr["support_status"])])
		print("                could see: %s" % str(fr["observable_portion"]))
		print("                could not: %s" % (", ".join(fr["hidden_variables"])
			if not fr["hidden_variables"].is_empty() else "nothing withheld"))
		print("                hash %s  evidence %s" % [str(fr["content_hash"]).substr(0, 16),
			", ".join(fr["evidence_event_ids"])])
	print("")
	print("[A6] WHAT WAS PREDICTED: %s" % str(p["predictions"]["status"]))
	print("[A7] OPEN CONTRADICTIONS: %s (%d open)" % [str(p["contradictions"]["status"]),
		int(p["contradictions"]["open"])])
	print("")
	print("[A8] WHAT SYSTEMIC CONSEQUENCE CHANGED")
	var rel: Dictionary = p["relationship"]
	for axis in rel["delta"]:
		if not is_equal_approx(float(rel["delta"][axis]), 0.0):
			print("     %-14s %+.3f -> %+.3f   (delta %+.3f)" % [axis,
				float(rel["axes_before"].get(axis, 0.0)),
				float(rel["axes_after"].get(axis, 0.0)),
				float(rel["delta"][axis])])
	var b: Dictionary = p["decision_before"]
	var a: Dictionary = p["decision_after"]
	print("     BEFORE  p %.4f  influence %+.4f  seed %d  roll %.4f  -> %s" % [
		float(b.get("probability", 0.0)), float(b.get("relationship_influence", 0.0)),
		int(b.get("decision_seed", 0)), float(b.get("roll", 0.0)),
		"ACCEPTED" if b.get("accepted", false) else "REFUSED"])
	print("     AFTER   p %.4f  influence %+.4f  seed %d  roll %.4f  -> %s" % [
		float(a.get("probability", 0.0)), float(a.get("relationship_influence", 0.0)),
		int(a.get("decision_seed", 0)), float(a.get("roll", 0.0)),
		"ACCEPTED" if a.get("accepted", false) else "REFUSED"])
	print("     same seed %s   same roll %s   only influence changed %s" % [
		str(p["causal"]["same_seed"]), str(p["causal"]["same_roll"]),
		str(p["causal"]["only_influence_changed"])])
	print("")
	print("TRUTH LABELS")
	for t in p["truth_labels"]:
		print("     %-42s %s" % [str(t["claim"]), str(t["status"])])
	print("")

	# ── the verdict, which must be able to say no ──────────────────────────
	var problems := []
	var seen := []
	for s in p["steps"]:
		seen.append(str(s["step"]))
	for required in ProofScript.STEPS:
		if not seen.has(required):
			problems.append("missing timeline step %s" % required)
	if str(b.get("status", "")) != "RECORDED":
		problems.append("no BEFORE decision recorded")
	if str(a.get("status", "")) != "RECORDED":
		problems.append("no AFTER decision recorded")
	if not p["errors"].is_empty():
		for e in p["errors"]:
			problems.append("feed error: %s" % str(e.get("message", "")))

	var wrong := []
	if str(p["event"]["event_id"]) == ProofScript.UNKNOWN:
		wrong.append("no objective event resolved")
	if not p["event"]["origin_is_controlled"]:
		wrong.append("origin is not labelled controlled_fixture")
	if not p["causal"]["same_seed"]:
		wrong.append("BEFORE and AFTER did not use the same seed")
	if not p["causal"]["same_roll"]:
		wrong.append("BEFORE and AFTER did not use the same roll")
	if not p["causal"]["only_influence_changed"]:
		wrong.append("something other than relationship influence changed")
	if p["witnesses"]["non_witness_ids"].is_empty():
		wrong.append("no non-witnesses: the negative control is missing")
	var cold := false
	for s in p["steps"]:
		if bool(s.get("cold_load", false)):
			cold = true
	if not cold:
		wrong.append("no evidence-backed COLD_LOAD step")

	if not wrong.is_empty():
		for w in wrong:
			print("  FAIL %s" % w)
		print("RUNG15 FAIL")
		quit(1)
		return
	if not problems.is_empty():
		for pr in problems:
			print("  PARTIAL %s" % pr)
		print("RUNG15 PARTIAL")
		quit(3)
		return
	print("RUNG15 PASS — all nine authoritative elements present and consistent.")
	quit(0)
