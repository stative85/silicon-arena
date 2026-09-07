extends SceneTree

## ASYNC-B representation witness. RUN BEFORE ANY MEASURED CELL.
##
##   godot --headless --path . --script tools/async_b_witness.gd
##
## NO MODEL CALLS. The representation layer is a new causal instrument, and the
## prereg is explicit that it does not get to certify itself by looking
## plausible. This does three things:
##
##   1. MAP TEETH        every seed x cell: bijective, mutually distinct,
##                       >= 12/16 separated, shared frames actually shared
##   2. IDENTITY WITNESS with identity maps the layer must reproduce the
##                       untransformed machinery on prompt bytes, decoded
##                       action, and world outcome
##   3. SABOTAGE         each deliberate break must turn the witness RED
##
## Section completion is tracked explicitly. A crashed section can otherwise
## skip its remaining checks and let the suite print OK -- that exact failure
## happened once already in this project.

const R := preload("res://scripts/arena/async_representation.gd")
const C := preload("res://scripts/arena/async_contract.gd")
const W := preload("res://scripts/arena/async_world.gd")

const SEEDS := [0, 1, 2, 3, 4, 5, 6, 7]
const CELLS := {
	"A": [true, true], "B": [false, true],
	"C": [true, false], "D": [false, false],
}
const AGENTS := ["agent_0", "agent_1", "agent_2"]
const MIN_SEPARATION := 12

var _fail := 0
var _checks := 0
var _done: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
		print("  FAIL %s %s" % [label, detail])


func _section(name: String) -> void:
	print("\n[%s]" % name)
	_done[name] = false


func _end(name: String) -> void:
	_done[name] = true


func _run() -> void:
	print("=== ASYNC-B representation witness ===")
	print("No model calls. Instrument only.")

	_map_teeth()
	_identity_witness()
	_structural_invariant()
	_orthogonality()
	_factor_independence()
	_sabotage()

	print("\n[SUMMARY]")
	var incomplete: Array = []
	for k in _done:
		if not bool(_done[k]):
			incomplete.append(k)
	print("  checks   %d" % _checks)
	print("  failures %d" % _fail)
	if not incomplete.is_empty():
		print("  INCOMPLETE SECTIONS: %s" % str(incomplete))
		print("\nWITNESS RED (a section did not finish)")
		quit(1)
		return
	if _fail > 0:
		print("\nWITNESS RED")
		quit(1)
		return
	print("\nWITNESS GREEN -- the representation layer may be used")
	quit(0)


# ------------------------------------------------------------------ map teeth

func _map_teeth() -> void:
	_section("MAP TEETH")
	for s in SEEDS:
		for cell in CELLS:
			var f: Array = CELLS[cell]
			var so: bool = bool(f[0])
			var sl: bool = bool(f[1])
			var reps := {}
			for a in AGENTS:
				reps[a] = R.make(int(s), a, so, sl)
			for a in AGENTS:
				var r= reps[a]
				_ok("bijection", r.is_bijection(),
					"seed %d cell %s agent %s" % [s, cell, a])
			# Shared frames must be IDENTICAL across agents; private frames must
			# be mutually distinct AND far apart.
			var r0= reps[AGENTS[0]]
			for i in range(1, AGENTS.size()):
				var ri= reps[AGENTS[i]]
				if so:
					_ok("shared_order identical",
						r0.order_hash() == ri.order_hash(),
						"seed %d cell %s" % [s, cell])
				else:
					var d := R.hamming(r0.order, ri.order)
					_ok("private_order separated", d >= MIN_SEPARATION,
						"seed %d cell %s pair 0-%d hamming %d" % [s, cell, i, d])
				if sl:
					_ok("shared_labels identical",
						r0.label_hash() == ri.label_hash(),
						"seed %d cell %s" % [s, cell])
				else:
					var d2 := R.hamming(r0.label, ri.label)
					_ok("private_labels separated", d2 >= MIN_SEPARATION,
						"seed %d cell %s pair 0-%d hamming %d" % [s, cell, i, d2])
	print("  %d seeds x %d cells checked" % [SEEDS.size(), CELLS.size()])
	_end("MAP TEETH")


# ----------------------------------------------------------- identity witness

func _identity_witness() -> void:
	_section("IDENTITY WITNESS")
	var ids := R.canonical_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# 1. prompt bytes
	var prompt_equal := true
	for trial in 200:
		var avail: Array = []
		for id in ids:
			if rng.randf() < 0.6:
				avail.append(id)
		if avail.is_empty():
			continue
		var rep := R.identity("agent_0")
		var raw := C.prompt(avail)
		var via := C.prompt(rep.render(avail))
		if raw.to_utf8_buffer() != via.to_utf8_buffer():
			prompt_equal = false
			break
	_ok("identity prompt bytes", prompt_equal,
		"identity representation changed the prompt")

	# 2. decoded action
	var decode_ok := true
	for id in ids:
		var rep2 := R.identity("agent_0")
		if rep2.decode(id) != id or rep2.encode(id) != id:
			decode_ok = false
	_ok("identity decode round trip", decode_ok)

	# 3. world outcome
	#    A deterministic action sequence applied to two worlds: one raw, one
	#    routed through the identity representation. Same journal, same final
	#    hash, or the layer is not transparent.
	var w1 := W.make(16, 4)
	var w2 := W.make(16, 4)
	var h1: Array = []
	var h2: Array = []
	rng.seed = 99
	for step in 300:
		var obs1 := w1.observe()
		var obs2 := w2.observe()
		var vt1: Array = obs1["valid_targets"]
		var vt2: Array = obs2["valid_targets"]
		if vt1.is_empty() or vt2.is_empty():
			w1.advance()
			w2.advance()
			continue
		var pick := rng.randi_range(0, vt1.size() - 1)
		var agent := "agent_%d" % (step % 3)
		var rep3 := R.identity(agent)
		# raw path
		var o1 := w1.apply(agent, str(vt1[pick]), obs1)
		# represented path: render, pick the SAME displayed position, decode
		var shown: Array = rep3.render(vt2)
		var alias := str(shown[pick])
		var canon := rep3.decode(alias)
		var o2 := w2.apply(agent, canon, obs2)
		h1.append("%s:%s" % [str(o1["outcome"]), str(o1["target"])])
		h2.append("%s:%s" % [str(o2["outcome"]), str(o2["target"])])
		w1.advance()
		w2.advance()
	_ok("identity world outcome", h1 == h2,
		"journals diverged at step %d" % _first_diff(h1, h2))
	_ok("identity final world hash", w1.canonical_hash() == w2.canonical_hash(),
		"%s vs %s" % [w1.canonical_hash(), w2.canonical_hash()])
	_end("IDENTITY WITNESS")


func _first_diff(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1


# -------------------------------------------------------- structural invariant

func _structural_invariant() -> void:
	_section("STRUCTURAL INVARIANT")
	## decode(render(S)) must equal S for every agent in every cell. This is
	## what stops PRIVATE_ORDER from quietly becoming PRIVATE_WORLD: agents may
	## see different orders and different names, never a different set.
	var ids := R.canonical_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad := 0
	for s in SEEDS:
		for cell in CELLS:
			var f: Array = CELLS[cell]
			for trial in 25:
				var avail: Array = []
				for id in ids:
					if rng.randf() < 0.5:
						avail.append(id)
				var decoded_sets: Array = []
				for a in AGENTS:
					var rep := R.make(int(s), a, bool(f[0]), bool(f[1]))
					var shown: Array = rep.render(avail)
					var back: Array = []
					for al in shown:
						back.append(rep.decode(str(al)))
					back.sort()
					decoded_sets.append(back)
				var want: Array = avail.duplicate()
				want.sort()
				for d in decoded_sets:
					if d != want:
						bad += 1
	_ok("decode(render(S)) == S for all agents/cells", bad == 0,
		"%d violations" % bad)
	_end("STRUCTURAL INVARIANT")


# ------------------------------------------------------------- orthogonality

func _orthogonality() -> void:
	_section("ORDER/LABEL ORTHOGONALITY")
	## ORDER must survive LABELING. The nasty failure is a renderer that applies
	## a private order, applies labels, and then sorts the aliases for tidy
	## prompt formatting -- which silently erases PRIVATE_ORDER while every
	## other check still passes.
	##
	## Two representations that share a label map but carry deliberately
	## OPPOSITE order maps must render the same available set as exact reverses
	## of each other, at the level of the final displayed alias sequence.
	var ids := R.canonical_ids()
	var fwd := R.identity("agent_0")
	var rev := R.identity("agent_1")
	for i in R.N:
		rev.order[i] = R.N - 1 - int(fwd.order[i])
	# same label map on both, so ONLY order differs
	var lab := R.make(0, "agent_0", true, true).label
	fwd.label = lab.duplicate()
	rev.label = lab.duplicate()

	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var reversed_ok := true
	var trials := 0
	for t in 100:
		var avail: Array = []
		for id in ids:
			if rng.randf() < 0.7:
				avail.append(id)
		if avail.size() < 2:
			continue
		trials += 1
		var a: Array = fwd.render(avail)
		var b: Array = rev.render(avail)
		var b_rev: Array = b.duplicate()
		b_rev.reverse()
		if a != b_rev:
			reversed_ok = false
			break
	_ok("opposite order maps produce reversed alias sequences", reversed_ok,
		"a post-label sort would break this")
	_ok("orthogonality tooth actually ran", trials > 50,
		"only %d usable trials" % trials)

	## And the displayed sequence must genuinely depend on order: two different
	## private orders over the same labels must not render identically.
	var differ := 0
	for t in 50:
		var avail2: Array = []
		for id in ids:
			if rng.randf() < 0.7:
				avail2.append(id)
		if avail2.size() < 2:
			continue
		if fwd.render(avail2) != rev.render(avail2):
			differ += 1
	_ok("order changes the displayed sequence", differ > 0)
	_end("ORDER/LABEL ORTHOGONALITY")


# -------------------------------------------------------- factor independence

func _factor_independence() -> void:
	_section("FACTOR INDEPENDENCE")
	## The 2x2 requires ORDER and LABEL to be structurally independent, not
	## merely called independent in the analysis. Deriving both from one PRNG
	## stream -- seed once, draw order, draw labels -- couples the two factors by
	## construction. They are drawn from DOMAIN-SEPARATED keys instead:
	##
	##     H(seed, "ORDER", agent_id | "SHARED")
	##     H(seed, "LABEL", agent_id | "SHARED")
	##
	## so neither factor can carry information about the other.
	var same := 0
	var total := 0
	for s in SEEDS:
		for cell in CELLS:
			var f: Array = CELLS[cell]
			for a in AGENTS:
				var r = R.make(int(s), a, bool(f[0]), bool(f[1]))
				total += 1
				if r.order == r.label:
					same += 1
				# The two maps must not even be hash-equal.
				_ok("order/label maps distinct",
					r.order_hash() != r.label_hash(),
					"seed %d cell %s agent %s" % [s, cell, a])
	_ok("no agent received identical order and label maps", same == 0,
		"%d of %d coincided" % [same, total])

	## Private frames must also differ from the SHARED frame they replace,
	## otherwise a "private" cell is silently a shared one.
	for s in SEEDS:
		for a in AGENTS:
			var priv = R.make(int(s), a, false, false)
			var shared = R.make(int(s), a, true, true)
			var do := R.hamming(priv.order, shared.order)
			var dl := R.hamming(priv.label, shared.label)
			_ok("private order != shared order", do >= MIN_SEPARATION,
				"seed %d agent %s hamming %d" % [s, a, do])
			_ok("private labels != shared labels", dl >= MIN_SEPARATION,
				"seed %d agent %s hamming %d" % [s, a, dl])
	_end("FACTOR INDEPENDENCE")


# ------------------------------------------------------------------- sabotage

func _sabotage() -> void:
	_section("SABOTAGE -- each break MUST be caught")
	var ids := R.canonical_ids()

	# S1. non-bijective label map
	var s1 := R.identity("agent_0")
	s1.label[3] = 4
	_ok("S1 non-bijective caught", not s1.is_bijection())

	# S2. "private" maps that are actually identical
	var s2a := R.identity("agent_0")
	var s2b := R.identity("agent_1")
	_ok("S2 identical private maps caught",
		R.hamming(s2a.order, s2b.order) < MIN_SEPARATION)

	# S3. off-by-one inverse mapper
	var s3 := R.make(0, "agent_0", false, false)
	var round_trip_broken := false
	for id in ids:
		var alias := s3.encode(str(id))
		# deliberately wrong inverse: shift the alias by one
		var vocab := R.alias_vocabulary()
		var wrong := str(vocab[(vocab.find(alias) + 1) % R.N])
		if s3.decode(wrong) != id:
			round_trip_broken = true
	_ok("S3 off-by-one inverse caught", round_trip_broken)

	# S4. renderer drops an element -> decoded set no longer equals world set
	var s4 := R.make(1, "agent_0", false, false)
	var avail := ids.slice(0, 8)
	var shown: Array = s4.render(avail)
	shown.remove_at(0)                      # the sabotage
	var back: Array = []
	for al in shown:
		back.append(s4.decode(str(al)))
	back.sort()
	var want := avail.duplicate()
	want.sort()
	_ok("S4 dropped element caught", back != want)

	# S5. order map applied where the label map belongs
	var s5 := R.make(2, "agent_0", false, false)
	var swapped := R.identity("agent_0")
	swapped.order = s5.order.duplicate()
	swapped.label = s5.order.duplicate()    # wrong map in the label slot
	var differs := swapped.label_hash() != s5.label_hash()
	_ok("S5 swapped order/label maps caught", differs)

	# S6. identity witness itself must be falsifiable: a NON-identity map must
	#     change the prompt. If this passes trivially the witness proves nothing.
	var s6 := R.make(3, "agent_0", false, false)
	var raw := C.prompt(ids)
	var via := C.prompt(s6.render(ids))
	# S7. post-label sort erases PRIVATE_ORDER
	var s7a := R.identity("agent_0")
	var s7b := R.identity("agent_1")
	for i in R.N:
		s7b.order[i] = R.N - 1 - int(s7a.order[i])
	var lab7 := R.make(5, "agent_0", true, true).label
	s7a.label = lab7.duplicate()
	s7b.label = lab7.duplicate()
	var av7 := ids.slice(0, 10)
	var r7a: Array = s7a.render(av7)
	var r7b: Array = s7b.render(av7)
	r7a.sort()                              # the sabotage: sort after labelling
	r7b.sort()
	_ok("S7 post-label sort caught", r7a == r7b,
		"sorting after labelling must make two OPPOSITE orders identical, "
		+ "which is exactly why the orthogonality tooth exists")

	# S8. ORDER and LABEL drawn from the same permutation
	var s8 := R.make(6, "agent_0", false, false)
	var coupled := R.identity("agent_0")
	coupled.order = s8.order.duplicate()
	coupled.label = s8.order.duplicate()    # same permutation in both slots
	_ok("S8 coupled order/label caught",
		coupled.order_hash() == coupled.label_hash(),
		"the independence tooth must reject this")

	_ok("S6 non-identity map changes the prompt",
		raw.to_utf8_buffer() != via.to_utf8_buffer(),
		"a private frame rendered identically to canonical -- the identity "
		+ "witness would be vacuous")
	_end("SABOTAGE -- each break MUST be caught")
