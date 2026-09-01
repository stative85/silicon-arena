extends RefCounted
class_name MemoryLedger

var _scars: Dictionary = {}       # agent_name -> Array[Dictionary]
var _beliefs: Dictionary = {}     # agent_name -> Array[String] (compressed operating beliefs)
var _relations: Dictionary = {}   # agent_name -> Dictionary[other_name -> record]
var _myths: Array = []            # arena-scale accepted records
var _id_counter := 0

func reset_for_roster(agents: Array) -> void:
	_scars.clear()
	_beliefs.clear()
	_relations.clear()
	_myths.clear()
	for a in agents:
		var n := str(a.get("name", ""))
		if n == "":
			continue
		_scars[n] = []
		_beliefs[n] = []
		_relations[n] = {}

func ensure_agent(agent_name: String) -> void:
	if not _scars.has(agent_name):
		_scars[agent_name] = []
	if not _beliefs.has(agent_name):
		_beliefs[agent_name] = []
	if not _relations.has(agent_name):
		_relations[agent_name] = {}

func next_id() -> String:
	_id_counter += 1
	return "mem_%06d" % _id_counter

func add_scar(agent_name: String, scar: Dictionary, cap: int) -> void:
	ensure_agent(agent_name)
	var arr: Array = _scars[agent_name]
	arr.append(scar)
	# Keep only the strongest cap — a scar ledger is not a chat log
	if arr.size() > cap:
		arr.sort_custom(func(a, b): return float(a.get("strength", 0.0)) > float(b.get("strength", 0.0)))
		_scars[agent_name] = arr.slice(0, cap)

func scars_of(agent_name: String) -> Array:
	return _scars.get(agent_name, [])

func beliefs_of(agent_name: String) -> Array:
	return _beliefs.get(agent_name, [])

func relations_of(agent_name: String) -> Dictionary:
	return _relations.get(agent_name, {})

func myths() -> Array:
	return _myths

func decay_all(min_strength: float) -> void:
	for aname in _scars.keys():
		var arr: Array = _scars[aname]
		var kept := []
		for s in arr:
			var new_s: float = float(s.get("strength", 0.0)) - float(s.get("decay", 0.04))
			if new_s >= min_strength:
				s["strength"] = new_s
				kept.append(s)
		_scars[aname] = kept

func update_relation(from_agent: String, to_agent: String, trust_delta: float, axis: String, incident: String) -> void:
	ensure_agent(from_agent)
	if from_agent == to_agent or to_agent == "":
		return
	var rels: Dictionary = _relations[from_agent]
	var rec: Dictionary = rels.get(to_agent, {"trust": 0.0, "axis": "", "last_incident": "", "count": 0})
	rec["trust"] = clampf(float(rec.get("trust", 0.0)) + trust_delta, -3.0, 3.0)
	if axis != "":
		rec["axis"] = axis
	if incident != "":
		rec["last_incident"] = incident
	rec["count"] = int(rec.get("count", 0)) + 1
	rels[to_agent] = rec
	_relations[from_agent] = rels

func add_belief(agent_name: String, belief: String, cap: int) -> void:
	if belief.strip_edges() == "":
		return
	ensure_agent(agent_name)
	var arr: Array = _beliefs[agent_name]
	# Dedup: drop any prior belief that is a near-match
	var lo := belief.to_lower()
	var deduped := []
	for b in arr:
		if str(b).to_lower() != lo:
			deduped.append(b)
	deduped.append(belief)
	if deduped.size() > cap:
		deduped = deduped.slice(deduped.size() - cap, deduped.size())
	_beliefs[agent_name] = deduped

func add_myth(text: String) -> void:
	if text.strip_edges() == "":
		return
	# Dedup
	for m in _myths:
		if str(m).to_lower() == text.to_lower():
			return
	_myths.append(text)
	if _myths.size() > 16:
		_myths = _myths.slice(_myths.size() - 16, _myths.size())

func find_active_scars(agent_name: String, trigger_pool: String, max_count: int) -> Array:
	var active := []
	var pool_lower = trigger_pool.to_lower()
	for s in scars_of(agent_name):
		var tlist = s.get("triggers", [])
		if tlist.is_empty():
			active.append(s)
			continue
		for t in tlist:
			if pool_lower.find(str(t).to_lower()) >= 0:
				active.append(s)
				break
	active.sort_custom(func(a, b): return float(a.get("strength", 0.0)) > float(b.get("strength", 0.0)))
	if active.size() > max_count:
		active = active.slice(0, max_count)
	return active

# Render a compact prompt block for injection. Pure formatting, no state change.
func render_block(agent_name: String, topic: String, max_scars: int) -> String:
	ensure_agent(agent_name)
	var parts := []
	var active = find_active_scars(agent_name, topic, max_scars)
	if not active.is_empty():
		var lines := []
		for s in active:
			var marker := "■"
			if str(s.get("source", "self")).begins_with("rumor"):
				marker = "⚠ RUMOR"
			var behv := str(s.get("behavior_change", ""))
			if behv != "":
				lines.append("%s %s — %s" % [marker, s.get("content", ""), behv])
			else:
				lines.append("%s %s" % [marker, s.get("content", "")])
		parts.append("SCAR STATE (what YOU remember; others may not):\n- " + "\n- ".join(lines))
	var bel = beliefs_of(agent_name)
	if not bel.is_empty():
		parts.append("YOUR OPERATING BELIEFS:\n- " + "\n- ".join(bel))
	var rels = relations_of(agent_name)
	if not rels.is_empty():
		var rlines := []
		for other_name in rels.keys():
			var rec = rels[other_name]
			var trust = float(rec.get("trust", 0.0))
			var tag = "neutral"
			if trust >= 0.6: tag = "ally"
			elif trust >= 0.2: tag = "warming"
			elif trust <= -0.6: tag = "rival"
			elif trust <= -0.2: tag = "suspicious"
			var axis = str(rec.get("axis", ""))
			var extra = ""
			if axis != "":
				extra = " (" + axis + ")"
			rlines.append("%s: %s%s" % [other_name, tag, extra])
		parts.append("RELATION MAP:\n- " + "\n- ".join(rlines))
	if not _myths.is_empty():
		parts.append("ARENA MYTHS (canon — everyone knows these):\n- " + "\n- ".join(_myths.slice(max(0, _myths.size() - 4), _myths.size())))
	if parts.is_empty():
		return ""
	return "\n\n".join(parts)

func to_dict() -> Dictionary:
	return {
		"scars": _scars.duplicate(true),
		"beliefs": _beliefs.duplicate(true),
		"relations": _relations.duplicate(true),
		"myths": _myths.duplicate(true),
	}
