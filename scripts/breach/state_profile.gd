extends RefCounted
class_name BreachStateProfile

## WHICH STATE GETS HASHED -- named by the round, never global, never "latest".
##
## THE DEFECT THIS PREVENTS. flow_channel, flow_material and flow_deposits were
## outside to_dict(), so two worlds differing only in accumulated material
## hashed identically. For FLOWSCAR4 that is disqualifying: the counterfactual's
## whole job is to see that difference.
##
## The wrong fix is to add the fields to the existing payload. Step 1B's
## artifacts were hashed under the old shape, and widening it would silently
## change what a signed result meant. So the payload is chosen by a NAMED
## PROFILE instead:
##
##   BREACH_STATE_V1     the Step 1B payload, byte for byte, frozen forever
##   FLOWSCAR4_STATE_V1  that payload plus every dynamic flow field
##
## Same discipline as the mass contract: an instance owned by the round, opened
## by name, refused if unknown. Nothing reselects it and nothing shares it.

const PATH := "res://config/state-profiles.v1.json"

var name: String = ""
var _spec: Dictionary = {}
var _projections: Dictionary = {}


static func _read() -> Dictionary:
	var fh := FileAccess.open(PATH, FileAccess.READ)
	if fh == null:
		return {}
	var t := fh.get_as_text()
	fh.close()
	var d = JSON.parse_string(t)
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func known() -> Array:
	var out: Array = (_read().get("profiles", {}) as Dictionary).keys()
	out.sort()
	return out


## Returns {"ok": bool, "reason": String, "profile": BreachStateProfile|null}.
static func open(profile_name: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "profile": null}
	var doc := _read()
	if doc.is_empty():
		res["reason"] = "STATE_PROFILES_UNREADABLE: " + PATH
		return res
	var profiles: Dictionary = doc.get("profiles", {})
	if not profiles.has(profile_name):
		res["reason"] = "UNKNOWN_STATE_PROFILE: %s (known: %s)" % [
			profile_name, str(known())]
		return res
	var p := new()
	p.name = profile_name
	p._spec = (profiles[profile_name] as Dictionary).duplicate(true)
	p._projections = (doc.get("counterfactual_projections", {})
		as Dictionary).duplicate(true)
	res["ok"] = true
	res["profile"] = p
	return res


func fields() -> Array:
	return (_spec.get("fields", []) as Array).duplicate()


func includes_flow() -> bool:
	return bool(_spec.get("includes_flow", false))


## CANONICAL SERIALISATION. Godot preserves a Dictionary's INSERTION order, so
## two logically identical states built in different orders would stringify to
## different bytes and hash differently. Keys are sorted recursively before
## hashing: the hash is a function of the state, not of the order the code
## happened to build it in.
##
## Arrays are NOT sorted. Array order is state -- reversing a channel is a
## different world -- so only their elements are canonicalised.
func _canonical(v):
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort()
		var out := {}
		for k in keys:
			out[str(k)] = _canonical(d[k])
		return out
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = []
		for item in (v as Array):
			arr.append(_canonical(item))
		return arr
	return v


func _sha(text: String) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(text.to_utf8_buffer())
	return c.finish().hex_encode()


## THE PAYLOAD. Built from the world's own deterministic projection, then
## widened by the named profile. BREACH_STATE_V1 returns exactly what to_dict()
## returns -- no reordering, no additions -- which is what makes the historical
## hash reproducible rather than merely similar.
func payload(world) -> Dictionary:
	var base: Dictionary = world.to_dict()
	if not includes_flow():
		return base
	var out: Dictionary = base.duplicate(true)
	out["flow_channel"] = (world.flow_channel as Array).duplicate()
	var mat := {}
	var keys: Array = world.flow_material.keys()
	keys.sort()
	for k in keys:
		mat[str(k)] = int(world.flow_material[k])
	out["flow_material"] = mat
	out["flow_deposits"] = int(world.flow_deposits)
	return out


func state_hash(world) -> String:
	return _sha(JSON.stringify(_canonical(payload(world))))


# ------------------------------------------------- counterfactual projections
#
# A single complete hash cannot prove "unrelated state remains invariant",
# because the treatment is EXPECTED to change part of the state. So the payload
# is split in two along a line declared in the frozen regime, not drawn at
# analysis time when the answer is already visible.


## MEMBERSHIP IS FROZEN AT TAU, NEVER DERIVED FROM THE OUTCOME.
##
## THE TRAP THIS CLOSES: classifying an object by where it is in the state being
## hashed. Then an object that moves onto the channel silently becomes causal,
## and one that moves off it silently becomes unrelated -- manufacturing or
## hiding "unrelated" differences according to the result. Membership would be
## a function of the answer.
##
## Computed ONCE, from the world as it stood at the counterfactual boundary tau,
## plus the declared descendant set. The rules:
##
##   * shells and deposits are causal for their ENTIRE LIFECYCLE, by kind,
##     wherever they later move
##   * every other object that existed at tau keeps the membership it had at
##     tau, wherever it later moves
##   * descendants of the removed ancestor are causal wherever they move
##   * an object created after tau that is neither shell, deposit, nor a
##     declared descendant is unrelated
static func membership(world_at_tau, descendant_ids: Array = []) -> Dictionary:
	var nodes := {}
	for n in world_at_tau.flow_channel:
		nodes[str(n)] = true
	var causal := {}
	var unrelated := {}
	var ids: Array = world_at_tau.objects.keys()
	ids.sort()
	for oid in ids:
		var o: Dictionary = world_at_tau.objects[oid]
		var kind := str(o["kind"])
		var loc := str(o["at_location"])
		if kind == "shell" or kind == "deposit" or nodes.has(loc):
			causal[str(oid)] = true
		else:
			unrelated[str(oid)] = true
	var desc := {}
	for d in descendant_ids:
		desc[str(d)] = true
		causal[str(d)] = true
		unrelated.erase(str(d))
	return {"causal": causal, "unrelated": unrelated, "descendants": desc,
		"tau_nodes": nodes}


## Where does this object belong, given frozen membership? Never asks the world
## being hashed where the object currently is.
func _owner(oid: String, kind: String, m: Dictionary) -> String:
	if kind == "shell" or kind == "deposit":
		return "causal"
	if (m.get("descendants", {}) as Dictionary).has(oid):
		return "causal"
	if (m.get("causal", {}) as Dictionary).has(oid):
		return "causal"
	if (m.get("unrelated", {}) as Dictionary).has(oid):
		return "unrelated"
	return "unrelated"


## CAUSAL: the channel, its material, the ratchet, and every object whose frozen
## membership is causal -- shells and deposits for life, plus whatever lay on a
## channel node at tau, plus declared descendants.
func causal_projection(world, m: Dictionary) -> Dictionary:
	var objs := {}
	var okeys: Array = world.objects.keys()
	okeys.sort()
	for oid in okeys:
		var o: Dictionary = world.objects[oid]
		var kind := str(o["kind"])
		if _owner(str(oid), kind, m) == "causal":
			objs[str(oid)] = {"kind": kind,
				"at_location": str(o["at_location"]),
				"holder": str(o["holder"])}
	var mat := {}
	var mkeys: Array = world.flow_material.keys()
	mkeys.sort()
	for k in mkeys:
		mat[str(k)] = int(world.flow_material[k])
	return {"flow_channel": (world.flow_channel as Array).duplicate(),
		"flow_material": mat, "flow_deposits": int(world.flow_deposits),
		"objects": objs}


## UNRELATED: everything else. This must be IDENTICAL between a run and its
## ancestor-removed replay. A difference here means the replay changed
## something the ancestor could not have caused, and the counterfactual is void.
##
## Locations are carried WITHOUT their object lists, which live in the
## partitioned `objects` above -- otherwise a channel node's contents would
## appear in both halves and the unrelated hash would move with the scar.
func unrelated_projection(world, m: Dictionary) -> Dictionary:
	var base: Dictionary = world.to_dict()
	var objs := {}
	var okeys: Array = world.objects.keys()
	okeys.sort()
	for oid in okeys:
		var o: Dictionary = world.objects[oid]
		var kind := str(o["kind"])
		if _owner(str(oid), kind, m) != "unrelated":
			continue
		objs[str(oid)] = {"kind": kind, "at_location": str(o["at_location"]),
			"holder": str(o["holder"])}
	var out := {}
	for k in ["round_id", "doors", "vault_slots", "vault_open",
			"vault_opened_at_tick"]:
		if base.has(k):
			out[k] = base[k]
	var locs := {}
	var lkeys: Array = (base.get("locations", {}) as Dictionary).keys()
	lkeys.sort()
	for lk in lkeys:
		var l: Dictionary = (base["locations"] as Dictionary)[lk]
		locs[str(lk)] = {"name": l["name"], "neighbors": l["neighbors"]}
	out["locations"] = locs
	out["objects"] = objs
	return out


func causal_hash(world, m: Dictionary) -> String:
	return _sha(JSON.stringify(_canonical(causal_projection(world, m))))


func unrelated_hash(world, m: Dictionary) -> String:
	return _sha(JSON.stringify(_canonical(unrelated_projection(world, m))))


## The shape a counterfactual verdict must take. All three, every time: a causal
## difference alongside an unrelated difference is contamination, not causation.
func verdict(before_world, after_world, m: Dictionary) -> Dictionary:
	return {
		"causal_differs":
			causal_hash(before_world, m) != causal_hash(after_world, m),
		"unrelated_identical":
			unrelated_hash(before_world, m) == unrelated_hash(after_world, m),
		"complete_differs":
			state_hash(before_world) != state_hash(after_world),
	}


## PARTITION COMPLETENESS. Every dynamic object must appear in exactly one
## projection: none dropped, none counted twice. Static location metadata is
## shared by declaration and is excluded from the dynamic partition.
func partition_audit(world, m: Dictionary) -> Dictionary:
	var ca: Dictionary = causal_projection(world, m)["objects"]
	var un: Dictionary = unrelated_projection(world, m)["objects"]
	var missing: Array = []
	var both: Array = []
	var ids: Array = world.objects.keys()
	ids.sort()
	for oid in ids:
		var in_c: bool = ca.has(str(oid))
		var in_u: bool = un.has(str(oid))
		if in_c and in_u:
			both.append(str(oid))
		elif not in_c and not in_u:
			missing.append(str(oid))
	return {"ok": missing.is_empty() and both.is_empty(),
		"missing": missing, "in_both": both,
		"counted": ca.size() + un.size(), "total": world.objects.size()}
