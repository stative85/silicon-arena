extends Node
class_name CoherenceEngine

# COHERENCE ENGINE — the echo-chamber detector.
#
# WHY THIS EXISTS
# Multi-agent LLM debates have one reliable failure mode: the models converge.
# They start agreeing, then agreeing more politely, and the debate flatlines
# while still producing fluent text. It looks fine on screen and it is dead.
#
# This engine measures that directly, using the result from orchor_sim.py:
# as a coupled-oscillator system's order parameter r climbs toward 1, the
# entropy of what it emits collapses. Measured there: r 0.02 -> 1.00 drove
# min-entropy 0.995 -> 0.022 bits/bit. Perfect synchrony is perfect silence.
#
# So: agents are phase oscillators (Kuramoto), the existing agreement matrix
# is the coupling, and r is consensus. High r + low novelty = echo chamber,
# and the arena gets told to break it.
#
# HONESTY REQUIREMENT
# This must be able to say "the debate is fine." A detector that always fires
# measures nothing. Both numbers are exposed every turn so you can watch it
# NOT fire — and `self_test()` runs a synthetic echo chamber and a synthetic
# real argument through the same math to prove it separates them.

signal coherence_updated(r: float, novelty: float, h_min: float)
signal echo_chamber_detected(r: float, novelty: float, h_min: float)
signal coherence_recovered(r: float)

# --- thresholds -------------------------------------------------------------
const R_ECHO := 0.85           # order parameter above which agents are locked
const NOVELTY_FLOOR := 0.35    # below this, turns are lexical retreads
const H_MIN_FLOOR := 0.75      # bits/bit of stance entropy
const SUSTAIN_TURNS := 3       # must hold this long — one dull turn is not a trend
const NOVELTY_WINDOW := 6      # turns of history to compare against
const BIT_WINDOW := 24         # stance bits kept for the entropy estimate

# --- oscillator state -------------------------------------------------------
var _phase: Dictionary = {}        # agent name -> float radians
var _omega: Dictionary = {}        # agent name -> natural frequency
var _recent_text: Array = []       # recent turn token-sets
var _stance_bits: Array = []       # 0/1 per turn: did this agent net-agree?
var _r_history: Array = []
var _echo_streak := 0
var _in_echo := false
var _rng := RandomNumberGenerator.new()

# Last computed values, for HUD readout.
var last_r := 0.0
var last_novelty := 1.0
var last_h_min := 1.0


func _init() -> void:
	_rng.randomize()


func reset_for_roster(agent_names: Array) -> void:
	_phase.clear()
	_omega.clear()
	_recent_text.clear()
	_stance_bits.clear()
	_r_history.clear()
	_echo_streak = 0
	_in_echo = false
	for n in agent_names:
		# Spread starting phases so a fresh roster begins incoherent, which is
		# the correct initial condition for a debate that hasn't happened yet.
		_phase[n] = _rng.randf_range(0.0, TAU)
		# Natural frequency = how fast this agent's stance drifts on its own.
		# Spread matters: identical omegas sync trivially and would make the
		# detector fire on every roster regardless of content.
		_omega[n] = _rng.randf_range(0.8, 1.2)
	last_r = 0.0
	last_novelty = 1.0
	last_h_min = 1.0


# --- the measurement --------------------------------------------------------

func ingest_turn(agent_name: String, content: String, agreement_matrix: Dictionary,
		agent_names: Array) -> Dictionary:
	if not _phase.has(agent_name):
		_phase[agent_name] = _rng.randf_range(0.0, TAU)
		_omega[agent_name] = _rng.randf_range(0.8, 1.2)

	var coupling := _mean_coupling(agreement_matrix, agent_names)
	_advance_phases(coupling, agent_names)

	last_r = order_parameter(agent_names)
	last_novelty = _novelty(content)
	_push_stance_bit(agent_name, agreement_matrix, agent_names)
	last_h_min = _stance_min_entropy()

	_r_history.append(last_r)
	if _r_history.size() > 40:
		_r_history.pop_front()

	coherence_updated.emit(last_r, last_novelty, last_h_min)
	_evaluate_echo()

	return {"r": last_r, "novelty": last_novelty, "h_min": last_h_min,
			"echo": _in_echo, "coupling": coupling}


func _mean_coupling(agreement_matrix: Dictionary, agent_names: Array) -> float:
	# Coupling strength is how much the agents currently agree. Agreement is
	# what pulls phases together, so it IS K. Disagreement is negative K and
	# actively pushes them apart, which is what a healthy debate looks like.
	if agent_names.size() < 2:
		return 0.0
	var total := 0.0
	var count := 0
	for a in agent_names:
		for b in agent_names:
			if a == b:
				continue
			var key: String = String(a) + "->" + String(b)
			if agreement_matrix.has(key):
				total += float(agreement_matrix[key])
				count += 1
	if count == 0:
		return 0.0
	return total / float(count)


func _advance_phases(coupling: float, agent_names: Array) -> void:
	# One Kuramoto step per turn. dt is 1 turn — this is a discrete social
	# clock, not physical time, and the sim's timescale caveat applies here
	# too: the cadence is declared, the statistics are what's measured.
	var dt := 0.35
	var mean_sin := 0.0
	var mean_cos := 0.0
	for n in agent_names:
		var p: float = float(_phase.get(n, 0.0))
		mean_sin += sin(p)
		mean_cos += cos(p)
	var count := float(max(agent_names.size(), 1))
	mean_sin /= count
	mean_cos /= count
	var psi := atan2(mean_sin, mean_cos)
	var r := sqrt(mean_sin * mean_sin + mean_cos * mean_cos)

	# K scaled so realistic agreement values land either side of the sync
	# transition instead of pinning the meter at one end.
	var k: float = coupling * 6.0
	for n in agent_names:
		var p: float = float(_phase.get(n, 0.0))
		var w: float = float(_omega.get(n, 1.0))
		var dp: float = (w + k * r * sin(psi - p)) * dt
		# Thermal noise: agents are not clean oscillators. Without this the
		# lattice locks artificially and the detector cries wolf.
		dp += _rng.randfn(0.0, 0.12)
		_phase[n] = fposmod(p + dp, TAU)


func order_parameter(agent_names: Array) -> float:
	# r in [0,1]. 0 = everyone arguing their own line. 1 = one voice in six mouths.
	if agent_names.is_empty():
		return 0.0
	var s := 0.0
	var c := 0.0
	for n in agent_names:
		var p: float = float(_phase.get(n, 0.0))
		s += sin(p)
		c += cos(p)
	s /= float(agent_names.size())
	c /= float(agent_names.size())
	return sqrt(s * s + c * c)


func _novelty(content: String) -> float:
	# Jaccard distance against the recent corpus. 1.0 = all new ground,
	# 0.0 = this turn is a rewording of what already got said.
	var tokens := _tokenize(content)
	if tokens.is_empty():
		return 1.0
	var worst_distance := 1.0
	for prior in _recent_text:
		var inter := 0
		for t in tokens:
			if prior.has(t):
				inter += 1
		var union_size: int = tokens.size() + prior.size() - inter
		if union_size <= 0:
			continue
		var distance: float = 1.0 - (float(inter) / float(union_size))
		worst_distance = minf(worst_distance, distance)
	_recent_text.append(tokens)
	if _recent_text.size() > NOVELTY_WINDOW:
		_recent_text.pop_front()
	return worst_distance


func _tokenize(content: String) -> Dictionary:
	# Content words only. Stopwords would make every turn look similar and
	# would quietly bias novelty toward zero for all rosters.
	const STOP := ["the", "and", "that", "this", "with", "for", "you", "are",
			"but", "not", "have", "was", "what", "your", "they", "them",
			"its", "our", "can", "will", "all", "just", "from", "has",
			"would", "could", "should", "there", "their", "been", "than"]
	var out := {}
	var lowered := content.to_lower()
	for ch in [",", ".", "!", "?", ";", ":", "\"", "'", "(", ")", "—", "-", "\n"]:
		lowered = lowered.replace(ch, " ")
	for w in lowered.split(" ", false):
		var word := String(w).strip_edges()
		if word.length() < 4:
			continue
		if word in STOP:
			continue
		out[word] = true
	return out


func _push_stance_bit(agent_name: String, agreement_matrix: Dictionary,
		agent_names: Array) -> void:
	# One bit per turn: did this agent come down net-positive on the others?
	# A real argument produces a mixed stream. An echo chamber produces a
	# constant, and a constant has no entropy.
	var net := 0.0
	for other in agent_names:
		if String(other) == agent_name:
			continue
		var key := agent_name + "->" + String(other)
		net += float(agreement_matrix.get(key, 0.0))
	_stance_bits.append(1 if net >= 0.0 else 0)
	if _stance_bits.size() > BIT_WINDOW:
		_stance_bits.pop_front()


func _stance_min_entropy() -> float:
	# SP 800-90B most-common-value estimate, same math as the sim's test suite.
	# Reported in bits per bit: 1.0 is a fair coin, 0.0 is a stuck output.
	var n := _stance_bits.size()
	if n < 4:
		return 1.0
	var ones := 0
	for b in _stance_bits:
		if int(b) == 1:
			ones += 1
	var p_max: float = float(max(ones, n - ones)) / float(n)
	p_max = clampf(p_max, 0.5, 1.0)
	return -log(p_max) / log(2.0)


func _evaluate_echo() -> void:
	var locked: bool = last_r > R_ECHO and (last_novelty < NOVELTY_FLOOR or last_h_min < H_MIN_FLOOR)
	if locked:
		_echo_streak += 1
		if _echo_streak >= SUSTAIN_TURNS and not _in_echo:
			_in_echo = true
			echo_chamber_detected.emit(last_r, last_novelty, last_h_min)
	else:
		if _in_echo:
			_in_echo = false
			coherence_recovered.emit(last_r)
		_echo_streak = 0


func clear_echo_state() -> void:
	# Called after the arena applies a disruption, so the detector can re-arm
	# and honestly report whether the disruption actually worked.
	_in_echo = false
	_echo_streak = 0


func status_line() -> String:
	return "SYNC %d%%  NOV %d%%  H %.2f" % [
		int(last_r * 100), int(last_novelty * 100), last_h_min]


func is_echo_chamber() -> bool:
	return _in_echo


# --- self test --------------------------------------------------------------

func self_test() -> Dictionary:
	# Runs a synthetic echo chamber and a synthetic real argument through the
	# same math. If both come out the same, this engine measures nothing and
	# the result says so. Call from a debug key; costs nothing at runtime.
	var names := ["A", "B", "C", "D"]

	var echo_matrix := {}
	for a in names:
		for b in names:
			if a != b:
				echo_matrix[a + "->" + b] = 0.9      # everyone agrees hard

	var argue_matrix := {}
	var flip := false
	for a in names:
		for b in names:
			if a != b:
				argue_matrix[a + "->" + b] = 0.7 if flip else -0.8
				flip = not flip

	var echo_r := _drive(names, echo_matrix, "we all agree the lattice is coherent", 12)
	var argue_r := _drive(names, argue_matrix, "", 12)

	var separated: bool = echo_r["r"] > argue_r["r"] + 0.2
	return {
		"echo_r": echo_r["r"], "echo_h": echo_r["h"],
		"argue_r": argue_r["r"], "argue_h": argue_r["h"],
		"separated": separated,
	}


func _drive(names: Array, matrix: Dictionary, repeat_text: String, turns: int) -> Dictionary:
	reset_for_roster(names)
	var r := 0.0
	var h := 1.0
	for i in range(turns):
		var speaker: String = String(names[i % names.size()])
		var text: String = repeat_text
		if text == "":
			# Distinct content per turn, so novelty stays high the way a real
			# argument's does.
			text = "position %d diverges sharply from the prior claim about %s" % [i, speaker]
		var out := ingest_turn(speaker, text, matrix, names)
		r = float(out["r"])
		h = float(out["h_min"])
	return {"r": r, "h": h}
