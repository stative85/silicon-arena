extends SceneTree

## THE FLOWSCAR4 RUNNER. Executes exactly the preregistered budget, or refuses.
##
##   godot --headless --path . --script tools/flowscar4_run.gd -- \
##       --manifest <path> --decider mock|live --out <dir>
##
## REFUSES BEFORE IT LOADS ANYTHING if the worktree is dirty, if HEAD differs
## from the manifest's apparatus commit, or if any bound file's hash differs.
## A run stamped against an apparatus that is not the one on disk is not
## evidence, it is a story.
##
## THE BUDGET IS THE BUDGET. Rounds and ticks come from the manifest. A rung-3
## witness does not buy another round to strengthen it; zero witnesses do not
## buy another round to find one.
##
## INTERRUPTION: a round that does not reach its tick budget is written with
## outcome ABORTED, preserved, and counted in the audit trail but NOT in the
## completed-round denominator. A restart uses the identical seed.
##
## Artifacts are written temp-then-rename, so a kill mid-write cannot leave a
## half-file that reads as a result. Every exit path unloads every model.

const RoundScript := preload("res://scripts/breach/breach_round.gd")
const SP := preload("res://scripts/breach/state_profile.gd")
const FC := preload("res://scripts/breach/flow_contract.gd")
const CO := preload("res://scripts/breach/canonical_operation.gd")
const OB := preload("res://scripts/breach/observation_builder.gd")
const SoloJit := preload("res://scripts/breach/solo_jit_decider.gd")

var _manifest_path := ""
var _decider_kind := "mock"
var _out_dir := "scratch/flowscar4"
var _manifest: Dictionary = {}
var _manifest_sha := ""
var _profile = null
var _http: HTTPRequest = null
var _fail := 0
var _mock_tick := 0
var _abort_round := 0
var _abort_tick := 0
var _mock_profile := "mixed"
var _live = null
var _live_abort := ""
var _residency_violations: Array = []


func say(s: String) -> void:
	print(s)


func refuse(reason: String) -> void:
	print("")
	print("RUN REFUSED: %s" % reason)
	print("Nothing was executed and no artifact was written.")
	_cleanup()
	quit(2)


func _cleanup() -> void:
	## FINALLY. Runs on success, on refusal, on failure and on abort.
	if _decider_kind == "live":
		SoloJit.unload_all()
		print("  cleanup: all models unloaded")


func _parse_args() -> void:
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		match argv[i]:
			"--manifest": _manifest_path = str(argv[i + 1])
			"--decider": _decider_kind = str(argv[i + 1])
			"--out": _out_dir = str(argv[i + 1])
			## DRY-RUN ONLY. Simulates an interruption so the ABORTED path is
			## exercised by the mock pass rather than discovered during a live
			## overnight run. Refused for the live decider below.
			"--simulate-abort-round": _abort_round = int(argv[i + 1])
			"--simulate-abort-tick": _abort_tick = int(argv[i + 1])
			## mixed: a realistic spread of operations.
			## drain: MOVE almost every turn, so agents exhaust and leave
			## shells inside the budget. Dry-run only; proves shell counting,
			## the on-channel tally and the ledger under the real runner.
			"--mock-profile": _mock_profile = str(argv[i + 1])


static func _sha_text(text: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(text.to_utf8_buffer())
	return c.finish().hex_encode()


func _sha_file(rel: String) -> String:
	var fh := FileAccess.open("res://" + rel, FileAccess.READ)
	if fh == null:
		return ""
	var b := fh.get_buffer(fh.get_length())
	fh.close()
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode()


func _git(args: Array) -> String:
	var out: Array = []
	OS.execute("git", args, out, true)
	return "\n".join(out.map(func(x): return str(x))).strip_edges()


## EVERY refusal happens here, before a model is loaded or a tick is run.
func _verify_apparatus() -> void:
	var fh := FileAccess.open(_manifest_path, FileAccess.READ)
	if fh == null:
		refuse("manifest not readable: " + _manifest_path)
		return
	var text := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		refuse("manifest is not a JSON object")
		return
	_manifest = d
	_manifest_sha = str(_manifest.get("manifest_sha256", ""))
	if _manifest_sha.is_empty():
		refuse("manifest carries no manifest_sha256")
		return

	var dirty := _git(["status", "--porcelain"])
	if not dirty.is_empty():
		refuse("worktree is not clean:\n" + dirty.substr(0, 400))
		return
	var head := _git(["rev-parse", "HEAD"])
	var want := str(_manifest.get("apparatus_commit", ""))
	if head != want:
		refuse("HEAD %s is not the manifest's apparatus commit %s"
			% [head.substr(0, 12), want.substr(0, 12)])
		return

	var bound: Dictionary = _manifest.get("bound_files", {})
	var drifted: Array = []
	for rel in bound.keys():
		if _sha_file(str(rel)) != str(bound[rel]):
			drifted.append(str(rel))
	if not drifted.is_empty():
		refuse("bound files differ from the manifest: " + str(drifted))
		return

	say("  apparatus verified: HEAD %s, %d bound files, manifest %s"
		% [head.substr(0, 12), bound.size(), _manifest_sha.substr(0, 16)])


## ATOMIC. Temp file, flush, close, rename. A kill mid-write leaves the temp
## behind and never a half-artifact that reads as a result.
func _write_atomic(path: String, payload: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var fh := FileAccess.open(tmp, FileAccess.WRITE)
	if fh == null:
		return false
	fh.store_string(JSON.stringify(payload, "\t"))
	fh.flush()
	fh.close()
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_out := ProjectSettings.globalize_path(path)
	var da := DirAccess.open(path.get_base_dir())
	if da == null:
		return false
	if FileAccess.file_exists(path):
		da.remove(path.get_file())
	return da.rename(tmp.get_file(), path.get_file()) == OK


## Roster order comes from the manifest; identity comes from the frozen species
## file. Display names are decoration with no authority (ARENA_IDENTITY_LAYERS),
## so they are mapped here and decide nothing but turn order.
func _roster() -> Array:
	var order: Array = _manifest.get("roster_order", [])
	var species: Array = _manifest.get("species", [])
	var out: Array = []
	for nm in order:
		for sp in species:
			var s: Dictionary = sp
			if _display_for(str(s["species_id"])) == str(nm):
				out.append({"display_name": str(nm),
					"model_id": str(s["model_id"]),
					"species_id": str(s["species_id"]),
					"instance_id": "%s#1" % str(s["model_id"])})
	return out


func _display_for(species_id: String) -> String:
	match species_id:
		"danube2": return "BRINE"
		"qwen35": return "GEMMATRON"
		"falconh1": return "KESTREL"
		"rwkv7": return "OZONIOUS"
		"lfm25": return "VANTA"
	return species_id.to_upper()


## MOCK DECIDER. Deterministic, no model, no GPU. Exists so the runner's
## control flow -- budget, hard stop, atomic writes, ABORTED handling, cleanup,
## denominator -- is proven before any inference is paid for.
func _mock_raw(actor: String) -> String:
	_mock_tick += 1
	## A deliberate mix: valid operations, and a garbage line every seventh turn
	## so the NO_OP path is exercised by the dry run rather than discovered live.
	if _mock_tick % 7 == 0:
		return "I think I will wait for now."
	if _mock_profile == "drain":
		## 28 turns per agent over 140 ticks, MOVE at 4 energy, START_ENERGY
		## 100: an agent that keeps moving exhausts around turn 25. Death is
		## reachable inside the budget, which is the property that matters.
		return "{\"operation\": \"MOVE\", \"target\": \"commons_north\"}"
	if _mock_tick % 3 == 0:
		return "{\"operation\": \"OBSERVE\", \"target\": \"vault_ring\"}"
	## MOVE drains energy, so agents eventually exhaust and leave shells. That
	## exercises shell counting, the on-channel tally and the mass ledger in the
	## dry pass instead of meeting them for the first time live.
	if _mock_tick % 2 == 0:
		return "{\"operation\": \"MOVE\", \"target\": \"commons_north\"}"
	return "{\"operation\": \"WAIT\"}"


func _init() -> void:
	_parse_args()
	print("=== FLOWSCAR4 RUNNER (%s) ===" % _decider_kind)
	if _decider_kind != "mock" and _decider_kind != "live":
		refuse("unknown decider: " + _decider_kind)
		return
	if _decider_kind == "live" and _abort_round > 0:
		refuse("--simulate-abort-round is a dry-run instrument and may not be "
			+ "used with the live decider")
		return
	_verify_apparatus()
	if _manifest.is_empty():
		return
	var pr: Dictionary = SP.open(str(_manifest["contract_binding"]["state_profile"]))
	if not bool(pr["ok"]):
		refuse(str(pr["reason"]))
		return
	_profile = pr["profile"]
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	root.add_child(_http)
	if _decider_kind == "live":
		var fh2 := FileAccess.open("res://config/action-schema.v1.json",
			FileAccess.READ)
		if fh2 == null:
			refuse("action schema unreadable")
			return
		var schema_text := fh2.get_as_text().strip_edges()
		fh2.close()
		_live = SoloJit.new(schema_text, _http,
			int(_manifest["generation"]["context_length"]))
		_live.temperature = float(_manifest["generation"]["temperature"])
		_live.max_tokens = int(_manifest["generation"]["max_tokens"])
	_run.call_deferred()


func _run() -> void:
	var budget: Dictionary = _manifest["run_budget"]
	var rounds := int(budget["rounds"])
	var ticks := int(budget["ticks_per_round"])
	var seeds: Dictionary = _manifest["seeds"]
	var roster := _roster()
	say("  budget %d rounds x %d ticks, roster %s"
		% [rounds, ticks, str(roster.map(func(r): return r["display_name"]))])
	if roster.size() != 5:
		refuse("roster did not resolve to five species: " + str(roster.size()))
		return

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_out_dir))

	var completed: Array = []
	var aborted: Array = []
	var shells_total := 0
	var shells_on_channel := 0

	for r in range(1, rounds + 1):
		var rid := "FLOWSCAR4-r%d" % r
		var seed_entry: Dictionary = seeds.get(rid, {})
		var seed := int(seed_entry.get("seed", 0))
		## THE SEED THAT RAN MUST BE THE SEED THAT WAS PUBLISHED. Godot's JSON
		## parser reads numbers as float; a seed above 2^53 loses its low bits
		## on the way in, and the round would silently use a different number
		## than the manifest names. Seeds are masked to 52 bits upstream, and
		## this refuses rather than trusting that.
		if float(seed) != float(seed_entry.get("seed", 0)) or seed <= 0:
			refuse("seed for %s did not survive the manifest read: %d"
				% [rid, seed])
			return
		if seed >= (1 << 53):
			refuse("seed for %s is above the float64-exact range: %d"
				% [rid, seed])
			return
		say("")
		say("  [%s] seed %d" % [rid, seed])
		seed(seed)

		var rd = RoundScript.new(rid, roster, {}, ticks, null, 2)
		if rd.ended:
			say("    ignition refused: %s" % rd.abort_reason)
			aborted.append({"round_id": rid, "outcome": "ABORTED",
				"reason": rd.abort_reason, "ticks_completed": 0})
			continue
		rd.world.flow_channel = FC.channel()
		var start_hash: String = _profile.state_hash(rd.world)
		say("    starting-state hash %s" % start_hash.substr(0, 16))

		var committed := 0
		var shells: Array = []
		## THE REPLAYABLE LOG. Operations only -- actor, verb, fields, tick and
		## event id. This is what the counterfactual replays; models are never
		## re-queried, so the analysis is deterministic and can be re-run by
		## anyone holding the artifact.
		var oplog: Array = []
		var abort_reason := ""
		for t in ticks:
			if _abort_round == r and _abort_tick == t:
				abort_reason = ("simulated interruption at tick %d "
					+ "(dry-run instrument)") % t
				break
			if rd.ended:
				abort_reason = "round ended early: " + rd.end_reason
				break
			var ev: Dictionary = await _one_turn(rd, roster)
			if ev.is_empty():
				if not _live_abort.is_empty():
					abort_reason = _live_abort
					_live_abort = ""
				else:
					abort_reason = ("no event produced at tick %d (%s)"
						% [t, rd.end_reason])
				break
			committed += 1
			oplog.append({"event_id": int(ev.get("event_id", -1)),
				"tick": int(ev.get("tick", -1)),
				"actor": str(ev.get("actor", "")),
				"operation": str(ev.get("operation", "")),
				"fields": (ev.get("fields", {}) as Dictionary).duplicate(),
				"accepted": bool(ev.get("accepted", false))})
			## mass_created lives under generation_params, where breach_round
			## records it. Reading the top level silently found nothing and the
			## dry run reported 0 shells for three rounds -- a false negative
			## that would have looked exactly like a real null result.
			var gp: Dictionary = ev.get("generation_params", {})
			for rec in (gp.get("mass_created", []) as Array):
				var mr: Dictionary = rec
				if str(mr.get("kind", "")) == "shell":
					shells.append(mr)

		var nodes := {}
		for n in rd.world.flow_channel:
			nodes[str(n)] = true
		var on_channel := 0
		for sh in shells:
			if nodes.has(str((sh as Dictionary).get("location", ""))):
				on_channel += 1
		shells_total += shells.size()
		shells_on_channel += on_channel

		## A round that runs out of agents or opens the vault has ENDED, not
		## been interrupted. Only an interruption is ABORTED: conflating them
		## would drop legitimate rounds out of the denominator and quietly
		## shrink the experiment.
		var ended_naturally: bool = rd.end_reason == RoundScript.END_TIME_HORIZON 			or rd.end_reason == RoundScript.END_VAULT_OPENED 			or rd.end_reason == RoundScript.END_NO_AGENT_CAN_ACT
		var full_budget: bool = committed == ticks
		var natural_stop: bool = ended_naturally 			and abort_reason.begins_with("round ended early")
		var outcome := "ABORTED"
		if full_budget or natural_stop:
			outcome = "COMPLETED"
			abort_reason = "" if full_budget else 				"ended naturally: " + rd.end_reason
		var artifact := {
			"artifact_kind": "FLOWSCAR4_ROUND",
			"round_id": rid,
			"outcome": outcome,
			"abort_reason": abort_reason,
			"manifest_sha256": _manifest_sha,
			"apparatus_commit": str(_manifest["apparatus_commit"]),
			"regime": "FLOWSCAR4",
			"residency": _manifest["residency"]["regime"],
			"decider_kind": _decider_kind,
			"seed": seed,
			"ticks_ceiling": ticks,
			"ticks_ceiling_note":
				"140 is a HARD CEILING, not a required length. A round that "
				+ "ends NO_AGENT_CAN_ACT or VAULT_OPENED before the ceiling is "
				+ "COMPLETED, not aborted.",
			"ticks_committed": committed,
			"starting_state_hash": start_hash,
			"final_state_hash": _profile.state_hash(rd.world),
			"final_causal_hash": _profile.causal_hash(rd.world,
				SP.membership(rd.world, [])),
			"roster_order": _manifest["roster_order"],
			"oplog": oplog,
			"shells": shells,
			"shells_on_channel": on_channel,
			"ledger_violation": rd.ledger_violation,
			"residency_violations": _residency_violations.duplicate(),
			"end_reason": rd.end_reason,
		}
		var path := "%s/%s.json" % [_out_dir, rid]
		if not _write_atomic(path, artifact):
			refuse("could not write artifact atomically: " + path)
			return
		say("    %s: %d/%d ticks, %d shell(s), %d on channel -> %s"
			% [outcome, committed, ticks, shells.size(), on_channel, path])
		if outcome == "COMPLETED":
			completed.append(artifact)
		else:
			aborted.append(artifact)

	_denominator(completed, aborted, shells_total, shells_on_channel)
	_cleanup()
	quit(0 if _fail == 0 else 1)


func _one_turn(rd, roster: Array) -> Dictionary:
	var actor_name: String = rd.scheduler.next_able_actor(rd.agents)
	if actor_name.is_empty():
		return {}
	if _decider_kind == "mock":
		_mock_tick += 1
		rd.deciders[actor_name] = _MockDecider.new(_mock_raw(actor_name),
			_mock_profile, _mock_tick % 7 == 0)
		return rd.step()

	## LIVE. breach_round.step() is synchronous, so the inference cannot happen
	## inside it: calling an awaiting decider from there returns a coroutine and
	## the round would record an empty string as the model's answer. With NO
	## decider wired at all it records exactly the same thing -- 420 NO_OPs that
	## look like a clean null result.
	##
	## So the request is made HERE, awaited, and the finished text is handed to
	## step() through a canned decider. The observation is built with the same
	## ObservationBuilder call step() will make, from state that cannot change
	## in between, so the model sees the packet that gets recorded.
	var actor = rd.agents[actor_name]
	var obs: Dictionary = OB.build(rd.world, rd.agents, actor_name, rd.bus,
		rd.public_lines)
	var model_id := str(actor.model_id)
	var spoken: Dictionary = await _live.decide(JSON.stringify(obs, "	"),
		SoloJit.contract_text(), model_id)
	if not bool(spoken.get("residency_ok", true)):
		_residency_violations.append(spoken)
		_live_abort = str(spoken.get("reason", "RESIDENCY_VIOLATION"))
		return {}
	rd.deciders[actor_name] = _CannedDecider.new(str(spoken.get("raw", "")),
		int(spoken.get("latency_ms", -1)), model_id,
		(spoken.get("resident", []) as Array))
	return rd.step()


func _denominator(completed: Array, aborted: Array, shells: int,
		on_channel: int) -> void:
	say("")
	say("  === DENOMINATOR, in full ===")
	say("    rounds completed           %d" % completed.size())
	say("    rounds aborted             %d  (audit only, not the denominator)"
		% aborted.size())
	say("    shells created             %d" % shells)
	say("    shells on a channel node   %d" % on_channel)
	say("    causally leveraged shells  0  (gate not run in this pass)")
	say("    rung-3 witnesses           0  (counterfactual not run in this pass)")
	for a in aborted:
		say("    ABORTED %s: %s" % [str((a as Dictionary).get("round_id", "?")),
			str((a as Dictionary).get("abort_reason", ""))])


## Hands step() a finished string. The inference already happened; this exists
## only because step() is synchronous.
class _CannedDecider:
	var raw: String = ""
	var latency_ms: int = -1
	var model_id: String = ""
	var resident: Array = []

	func _init(p_raw: String, p_latency: int, p_model: String,
			p_resident: Array) -> void:
		raw = p_raw
		latency_ms = p_latency
		model_id = p_model
		resident = p_resident

	func decide(_observation: Dictionary, _agent) -> Dictionary:
		return {"raw": raw, "latency_ms": latency_ms,
			"params": {"decider": "SOLO_JIT_LIVE", "model_id": model_id,
				"resident_at_request": resident}}


class _MockDecider:
	## A mock that ignores the observation cannot drain an agent: it emits MOVE
	## to a room that is not adjacent, the reducer refuses, and refusal is
	## INERT -- no energy spent, no state changed. The first drain profile did
	## exactly that and "proved" a shell path that never ran. So the drain
	## profile reads the actual exits out of the observation packet, which is
	## also what a real model has to do.
	var raw: String = ""
	var profile: String = "mixed"
	var garbage: bool = false

	func _init(p_raw: String, p_profile: String = "mixed",
			p_garbage: bool = false) -> void:
		raw = p_raw
		profile = p_profile
		garbage = p_garbage

	func decide(observation: Dictionary, _agent) -> Dictionary:
		if garbage:
			return {"raw": "I think I will wait for now.", "latency_ms": 0,
				"params": {"decider": "mock", "profile": profile}}
		if profile == "drain":
			var loc: Dictionary = observation.get("location", {})
			var exits: Array = loc.get("exits", [])
			if not exits.is_empty():
				return {"raw": "{\"operation\": \"MOVE\", \"target\": \"%s\"}"
					% str(exits[0]), "latency_ms": 0,
					"params": {"decider": "mock", "profile": profile}}
		return {"raw": raw, "latency_ms": 0,
			"params": {"decider": "mock", "profile": profile}}
