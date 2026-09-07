extends RefCounted
class_name AsyncRepresentation

## ASYNC-B representation layer. Per-agent ORDER and LABEL frames over ONE
## physical world.
##
##     canonical available set S(t)
##             |  ORDER MAP O_a        (presentation order)
##     ordered canonical list
##             |  LABEL MAP L_a        (canonical -> displayed alias)
##     displayed aliases
##
## The model returns a displayed alias. The host applies inverse(L_a) to recover
## the canonical resource. The model never receives canonical identity.
##
## THE WORLD IS NOT TOUCHED. Canonical ids stay exactly what AsyncWorld already
## uses, and the alias vocabulary is the SAME fixed-width set of strings. A
## private label frame is a different bijection, never a different token
## vocabulary: handing one agent `apple_7` and another `xqz_foo` would confound
## label mapping with morphology and tokenization.
##
## WHY CANONICAL IDENTITY MUST NEVER LEAK INTO ANALYSIS KEYS. The contention
## graph is computed on canonical resources. If it were computed on displayed
## aliases, PRIVATE_LABELS would "abolish" contention by renaming things in the
## analysis rather than changing any behaviour. That would be a spectacularly
## cheap scientific achievement, so `decode()` exists and is the only bridge.

const N := 16

## Canonical ids, identical to the world's own resource ids.
static func canonical_ids() -> Array:
	var out: Array = []
	for i in N:
		out.append("r_%02d" % i)
	return out


## The alias vocabulary. Deliberately the SAME strings as the canonical ids --
## what varies between agents is the mapping, not the token shape.
static func alias_vocabulary() -> Array:
	return canonical_ids()


var agent_id: String = ""
## order[i] = rank at which canonical resource i is presented. Lower is earlier.
var order: Array = []
## label[i] = index into the alias vocabulary shown for canonical resource i.
var label: Array = []


static func identity(a_id: String) -> AsyncRepresentation:
	var r := AsyncRepresentation.new()
	r.agent_id = a_id
	for i in N:
		r.order.append(i)
		r.label.append(i)
	return r


## Deterministic permutation from a string key. Fisher-Yates over a seeded RNG,
## so the same key always yields the same permutation on any machine.
static func _perm(key: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(key.sha256_text().substr(0, 15).hex_to_int())
	var p: Array = []
	for i in N:
		p.append(i)
	for i in range(N - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = p[i]
		p[i] = p[j]
		p[j] = t
	return p


## Build one agent's frame.
##
## `shared_order` / `shared_labels` select whether the permutation key includes
## the agent id. A shared frame keys on the seed alone, so every agent derives
## the identical permutation -- shared-ness is a property of the KEY, which
## makes it impossible to accidentally hand two agents "shared" maps that differ.
static func make(seed_id: int, a_id: String, shared_order: bool,
		shared_labels: bool, sub: int = 0) -> AsyncRepresentation:
	var r := AsyncRepresentation.new()
	r.agent_id = a_id
	var ok := "B|seed=%d|order|%s|sub=%d" % [
		seed_id, "SHARED" if shared_order else a_id, sub]
	var lk := "B|seed=%d|label|%s|sub=%d" % [
		seed_id, "SHARED" if shared_labels else a_id, sub]
	r.order = _perm(ok)
	r.label = _perm(lk)
	return r


## Render the canonical available set as this agent sees it.
## Returns the displayed alias list, in this agent's presentation order.
func render(canonical_available: Array) -> Array:
	var pairs: Array = []
	var ids := canonical_ids()
	for cid in canonical_available:
		var idx := ids.find(str(cid))
		if idx < 0:
			continue
		pairs.append([int(order[idx]), idx])
	pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var vocab := alias_vocabulary()
	var out: Array = []
	for p in pairs:
		out.append(str(vocab[int(label[int(p[1])])]))
	return out


## Displayed alias -> canonical id. Returns "" when the alias is not in the
## vocabulary at all, which is a SEMANTIC_INVALID candidate and not a decode
## failure of the instrument.
func decode(alias: String) -> String:
	var vocab := alias_vocabulary()
	var ai := vocab.find(alias)
	if ai < 0:
		return ""
	var ci := label.find(ai)
	if ci < 0:
		return ""
	return str(canonical_ids()[ci])


## Canonical id -> displayed alias. Used by witnesses and telemetry only.
func encode(canonical: String) -> String:
	var ci := canonical_ids().find(canonical)
	if ci < 0:
		return ""
	return str(alias_vocabulary()[int(label[ci])])


## Presentation rank of a canonical id within a given available set.
func rank_of(canonical: String, canonical_available: Array) -> int:
	return render(canonical_available).find(encode(canonical))


func _perm_hash(p: Array) -> String:
	var parts: Array = []
	for v in p:
		parts.append(str(int(v)))
	return ("|".join(PackedStringArray(parts))).sha256_text().substr(0, 16)


func order_hash() -> String:
	return _perm_hash(order)


func label_hash() -> String:
	return _perm_hash(label)


func is_bijection() -> bool:
	var so := {}
	var sl := {}
	for i in N:
		so[int(order[i])] = true
		sl[int(label[i])] = true
	return order.size() == N and label.size() == N \
		and so.size() == N and sl.size() == N


## Positions at which two permutations differ. The frozen separation rule is
## >= 12 of 16.
static func hamming(a: Array, b: Array) -> int:
	var d := 0
	for i in N:
		if int(a[i]) != int(b[i]):
			d += 1
	return d
