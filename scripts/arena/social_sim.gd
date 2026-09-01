extends Node
class_name SocialSim

# SOCIAL SIM — the Sims layer.
#
# GOAL: you can glance at the arena with the text turned off and READ the
# situation. Who is winning. Who is furious. Who just got humiliated and is
# skulking at the edge. Who has formed a clique.
#
# Everything here is DRIVEN BY AgentMind state, never random. If an agent
# storms to the far wall it is because it is cornered and out of patience,
# and the same state produced the words it just said. Motion that doesn't
# mean anything is a screensaver.
#
# Behaviours, chosen by drive priority each tick:
#   CONFRONT     square up to your grudge, nose to nose
#   HOLD_COURT   high conviction + people owe you: take centre, others orbit
#   RALLY        drift to your ally, shoulder to shoulder
#   WITHDRAW     out of patience: retreat to the rim, face outward
#   STORM_OFF    cornered and furious: break away hard, then sulk
#   MINGLE       default idle circulation

signal behaviour_changed(agent_name: String, behaviour: String)
signal clique_formed(members: Array)
signal confrontation(a: String, b: String)

const ARENA_CENTRE := Vector2(770, 360)
const ARENA_RADIUS := 250.0
const PERSONAL_SPACE := 64.0
const CONFRONT_DISTANCE := 78.0
const ARRIVE_EPSILON := 14.0

const B_CONFRONT := "CONFRONT"
const B_HOLD_COURT := "HOLD_COURT"
const B_RALLY := "RALLY"
const B_WITHDRAW := "WITHDRAW"
const B_STORM_OFF := "STORM_OFF"
const B_MINGLE := "MINGLE"

var actors: Dictionary = {}          # name -> actor dict
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _last_cliques: Array = []


func _init() -> void:
	_rng.randomize()


func reset_for_roster(names: Array) -> void:
	actors.clear()
	_last_cliques.clear()
	var count: int = maxi(names.size(), 1)
	for i in range(names.size()):
		var angle: float = TAU * float(i) / float(count)
		var home := ARENA_CENTRE + Vector2(cos(angle), sin(angle)) * (ARENA_RADIUS * 0.62)
		actors[String(names[i])] = {
			"name": String(names[i]),
			"pos": home,
			"target": home,
			"home": home,
			"facing": ARENA_CENTRE,
			"behaviour": B_MINGLE,
			"behaviour_age": 0.0,
			"speed": 42.0,
			"agitation": 0.0,
			"lean": 0.0,          # -1 recoil .. +1 lean in
			"sulk": 0.0,
		}


func has_actor(name: String) -> bool:
	return actors.has(name)


# ---------------------------------------------------------------------------
# DECIDE — called once per debate turn, from the minds
# ---------------------------------------------------------------------------

func update_from_minds(minds: Dictionary) -> void:
	"""minds: agent_name -> AgentMind."""
	for name in actors:
		if not minds.has(name):
			continue
		var mind = minds[name]
		var body: Dictionary = mind.body_language()
		var actor: Dictionary = actors[name]

		actor["agitation"] = float(body["agitation"])
		var chosen := _choose_behaviour(name, body)

		if chosen != actor["behaviour"]:
			actor["behaviour"] = chosen
			actor["behaviour_age"] = 0.0
			behaviour_changed.emit(name, chosen)

		_apply_behaviour(actor, body, minds)

	_detect_cliques(minds)


func _choose_behaviour(name: String, body: Dictionary) -> String:
	var heat: float = float(body["heat"])
	var conviction: float = float(body["conviction"])
	var stamina: float = float(body["stamina"])
	var mood: String = String(body["mood"])
	var target: String = String(body["target"])
	var ally: String = String(body["ally"])

	# Priority order matters: the strongest drive wins, and a cornered agent
	# that is also tired should storm off, not politely withdraw.
	if mood == "cornered" and heat > 0.65:
		return B_STORM_OFF
	if target != "" and actors.has(target) and heat > 0.45:
		return B_CONFRONT
	if stamina < 0.32:
		return B_WITHDRAW
	if conviction > 0.75 and not body["ally"] == "":
		return B_HOLD_COURT
	if ally != "" and actors.has(ally):
		return B_RALLY
	return B_MINGLE


func _apply_behaviour(actor: Dictionary, body: Dictionary, minds: Dictionary) -> void:
	var name: String = actor["name"]
	match actor["behaviour"]:
		B_CONFRONT:
			var rival: String = String(body["target"])
			if actors.has(rival):
				var rp: Vector2 = actors[rival]["pos"]
				var away: Vector2 = (actor["pos"] - rp)
				if away.length() < 1.0:
					away = Vector2(1, 0)
				actor["target"] = rp + away.normalized() * CONFRONT_DISTANCE
				actor["facing"] = rp
				actor["speed"] = 78.0
				actor["lean"] = 1.0
				actor["sulk"] = 0.0
				confrontation.emit(name, rival)

		B_HOLD_COURT:
			actor["target"] = ARENA_CENTRE
			actor["facing"] = ARENA_CENTRE + Vector2(0, -40)
			actor["speed"] = 34.0
			actor["lean"] = 0.35
			actor["sulk"] = 0.0

		B_RALLY:
			var ally: String = String(body["ally"])
			if actors.has(ally):
				var ap: Vector2 = actors[ally]["pos"]
				var side := Vector2(cos(_tick * 0.4), sin(_tick * 0.4)) * PERSONAL_SPACE
				actor["target"] = ap + side
				actor["facing"] = ARENA_CENTRE
				actor["speed"] = 50.0
				actor["lean"] = 0.2
				actor["sulk"] = 0.0

		B_WITHDRAW:
			var out: Vector2 = (actor["home"] - ARENA_CENTRE)
			if out.length() < 1.0:
				out = Vector2(0, -1)
			actor["target"] = ARENA_CENTRE + out.normalized() * (ARENA_RADIUS * 0.95)
			actor["facing"] = actor["target"] + out.normalized() * 50.0
			actor["speed"] = 30.0
			actor["lean"] = -0.6
			actor["sulk"] = 0.5

		B_STORM_OFF:
			var rival2: String = String(body["target"])
			var flee_from: Vector2 = ARENA_CENTRE
			if actors.has(rival2):
				flee_from = actors[rival2]["pos"]
			var dir: Vector2 = (actor["pos"] - flee_from)
			if dir.length() < 1.0:
				dir = Vector2(0, 1)
			actor["target"] = ARENA_CENTRE + dir.normalized() * ARENA_RADIUS
			actor["facing"] = actor["target"] + dir.normalized() * 60.0
			actor["speed"] = 110.0
			actor["lean"] = -1.0
			actor["sulk"] = 1.0

		_:
			var wobble := Vector2(
				_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)
			) * 46.0
			actor["target"] = actor["home"] + wobble
			actor["facing"] = ARENA_CENTRE
			actor["speed"] = 26.0
			actor["lean"] = 0.0
			actor["sulk"] = maxf(float(actor["sulk"]) - 0.2, 0.0)


# ---------------------------------------------------------------------------
# MOVE — called every frame
# ---------------------------------------------------------------------------

func physics_step(delta: float) -> void:
	_tick += delta
	for name in actors:
		var a: Dictionary = actors[name]
		a["behaviour_age"] = float(a["behaviour_age"]) + delta

		var to_target: Vector2 = a["target"] - a["pos"]
		if to_target.length() > ARRIVE_EPSILON:
			var step: float = float(a["speed"]) * delta
			a["pos"] = a["pos"] + to_target.normalized() * minf(step, to_target.length())

		# Agitation shows as a tremor. Cheap, and instantly readable.
		var ag: float = float(a["agitation"])
		if ag > 0.25:
			a["pos"] = a["pos"] + Vector2(
				sin(_tick * 22.0 + a["pos"].x) , cos(_tick * 19.0 + a["pos"].y)
			) * ag * 1.4 * delta * 60.0 * 0.05

	_separate()
	_clamp_to_arena()


func _separate() -> void:
	# Nobody stands inside anybody. Confronting agents get a tighter radius so
	# a face-off actually reads as a face-off instead of polite distance.
	var names := actors.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: Dictionary = actors[names[i]]
			var b: Dictionary = actors[names[j]]
			var d: Vector2 = b["pos"] - a["pos"]
			var dist: float = d.length()
			var min_d := PERSONAL_SPACE
			if a["behaviour"] == B_CONFRONT or b["behaviour"] == B_CONFRONT:
				min_d = CONFRONT_DISTANCE * 0.7
			if dist < min_d and dist > 0.01:
				var push: Vector2 = d.normalized() * (min_d - dist) * 0.5
				a["pos"] = a["pos"] - push
				b["pos"] = b["pos"] + push
			elif dist <= 0.01:
				a["pos"] = a["pos"] + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2))


func _clamp_to_arena() -> void:
	for name in actors:
		var a: Dictionary = actors[name]
		var off: Vector2 = a["pos"] - ARENA_CENTRE
		if off.length() > ARENA_RADIUS:
			a["pos"] = ARENA_CENTRE + off.normalized() * ARENA_RADIUS


# ---------------------------------------------------------------------------
# CLIQUES — emergent, from proximity plus mutual debt
# ---------------------------------------------------------------------------

func _detect_cliques(minds: Dictionary) -> void:
	var found := []
	var names := actors.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var n1: String = String(names[i])
			var n2: String = String(names[j])
			if actors[n1]["pos"].distance_to(actors[n2]["pos"]) > PERSONAL_SPACE * 1.8:
				continue
			# Proximity alone is not alliance -- two agents mid-confrontation
			# are close too. Require mutual positive regard.
			if not (minds.has(n1) and minds.has(n2)):
				continue
			var m1_debt: float = float(minds[n1].debts.get(n2, 0.0))
			var m2_debt: float = float(minds[n2].debts.get(n1, 0.0))
			if m1_debt > 0.2 and m2_debt > 0.2:
				found.append([n1, n2])

	if found.size() != _last_cliques.size():
		_last_cliques = found
		for pair in found:
			clique_formed.emit(pair)


# ---------------------------------------------------------------------------
# READ-OUT for the renderer
# ---------------------------------------------------------------------------

func position_of(name: String) -> Vector2:
	if actors.has(name):
		return actors[name]["pos"]
	return ARENA_CENTRE


func state_of(name: String) -> Dictionary:
	if actors.has(name):
		return actors[name]
	return {}


func behaviour_of(name: String) -> String:
	if actors.has(name):
		return String(actors[name]["behaviour"])
	return B_MINGLE


func behaviour_caption(behaviour: String) -> String:
	match behaviour:
		B_CONFRONT: return "squares up"
		B_HOLD_COURT: return "holds court"
		B_RALLY: return "closes ranks"
		B_WITHDRAW: return "backs off"
		B_STORM_OFF: return "storms off"
		_: return ""
