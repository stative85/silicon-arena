extends RefCounted
class_name AgentMind

# AGENT MIND — the fix for "agents go stupid after 5 turns".
#
# THE ACTUAL CAUSE
# Feeding a model a growing transcript makes it worse, not better. By turn 6
# the prompt is mostly its own earlier output, the original persona is buried
# a thousand tokens up, and the model starts averaging toward generic
# assistant-voice. It doesn't "forget" — it drowns.
#
# THE FIX
# Never grow the context. Each agent carries a COMPACT STRUCTURED MIND that is
# rewritten (not appended to) every turn, and re-injected at fixed size. The
# agent is told who it is, what it has committed to, who wronged it and what
# it must not repeat — in ~200 tokens, every single turn, forever.
#
# Turn 50 costs the same as turn 5 and reads just as sharp.
#
# What lives here is state a debate actually turns on:
#   thesis        the line they must not abandon
#   commitments   claims they made and cannot contradict
#   grudges       per-rival heat, decays slowly
#   debts         who conceded to them (fuel for pressing an advantage)
#   wounds        points scored against them they must answer
#   mood          drives voice AND the Sims layer's body language
#   tics          verbal signature that keeps voices distinguishable
#   banned        their own last openers, so they stop repeating themselves

const MAX_COMMITMENTS := 4
const MAX_WOUNDS := 3
const MAX_BEATS := 3
const MAX_BANNED_OPENERS := 5

var agent_name: String = ""
var thesis: String = ""
var tics: Array = []

var commitments: Array = []       # [{claim, turn}]
var wounds: Array = []            # [{by, jab, turn, answered}]
var beats: Array = []             # compressed one-line summaries of recent turns
var grudges: Dictionary = {}      # rival -> float 0..1
var debts: Dictionary = {}        # rival -> float 0..1 (they conceded to us)
var banned_openers: Array = []

var mood: String = "measured"
var heat: float = 0.0             # 0 calm .. 1 furious
var conviction: float = 0.6       # 0 wavering .. 1 immovable
var stamina: float = 1.0          # falls as they speak; low = terse, snappish
var turns_taken: int = 0

const MOODS := ["measured", "needled", "smug", "cornered", "contemptuous", "vindicated"]


func _init(p_name: String = "", p_thesis: String = "", p_tics: Array = []) -> void:
	agent_name = p_name
	thesis = p_thesis
	tics = p_tics.duplicate()


# ---------------------------------------------------------------------------
# INGEST — called once per turn with what this agent said
# ---------------------------------------------------------------------------

func absorb_own_turn(content: String, turn: int) -> void:
	turns_taken += 1
	stamina = maxf(stamina - 0.06, 0.15)

	var claim := _extract_claim(content)
	if claim != "":
		commitments.append({"claim": claim, "turn": turn})
		while commitments.size() > MAX_COMMITMENTS:
			commitments.pop_front()

	var opener := _opener(content)
	if opener != "":
		banned_openers.append(opener)
		while banned_openers.size() > MAX_BANNED_OPENERS:
			banned_openers.pop_front()

	beats.append("T%d you argued: %s" % [turn, _compress(content, 90)])
	while beats.size() > MAX_BEATS:
		beats.pop_front()

	# Speaking your piece steadies you a little.
	heat = maxf(heat - 0.08, 0.0)
	_refresh_mood()


func absorb_rival_turn(rival: String, content: String, agreement: float, turn: int) -> void:
	"""agreement: -1 (attacked us) .. +1 (conceded to us)."""
	if rival == agent_name:
		return

	if agreement < -0.15:
		var g: float = float(grudges.get(rival, 0.0))
		grudges[rival] = clampf(g + absf(agreement) * 0.5, 0.0, 1.0)
		heat = clampf(heat + absf(agreement) * 0.35, 0.0, 1.0)
		conviction = clampf(conviction + 0.05, 0.0, 1.0)   # attacks entrench
		wounds.append({
			"by": rival, "jab": _compress(content, 80),
			"turn": turn, "answered": false,
		})
		while wounds.size() > MAX_WOUNDS:
			wounds.pop_front()
	elif agreement > 0.15:
		var d: float = float(debts.get(rival, 0.0))
		debts[rival] = clampf(d + agreement * 0.4, 0.0, 1.0)
		# Being agreed with is pleasant and slightly corrosive.
		conviction = clampf(conviction + 0.03, 0.0, 1.0)
		heat = maxf(heat - 0.05, 0.0)

	_refresh_mood()


func mark_wounds_answered() -> void:
	for w in wounds:
		w["answered"] = true


func decay(amount: float = 0.04) -> void:
	"""Called each round so old feuds fade if nobody feeds them."""
	for k in grudges.keys():
		grudges[k] = maxf(float(grudges[k]) - amount, 0.0)
		if grudges[k] <= 0.001:
			grudges.erase(k)
	for k in debts.keys():
		debts[k] = maxf(float(debts[k]) - amount * 0.5, 0.0)
		if debts[k] <= 0.001:
			debts.erase(k)
	heat = maxf(heat - amount, 0.0)
	stamina = minf(stamina + amount * 0.8, 1.0)
	_refresh_mood()


# ---------------------------------------------------------------------------
# EMIT — the fixed-size identity block injected every turn
# ---------------------------------------------------------------------------

func to_prompt_block() -> String:
	"""~200 tokens, constant size. This IS the memory. Nothing else is sent."""
	var out := []
	out.append("YOU ARE %s." % agent_name.to_upper())
	if thesis != "":
		out.append("Your line, which you do not abandon: %s" % thesis)

	out.append("State: %s. conviction %s, composure %s, energy %s." % [
		mood, _band(conviction), _band(1.0 - heat), _band(stamina)])

	if commitments.size() > 0:
		var claims := []
		for c in commitments:
			claims.append("\"%s\"" % c["claim"])
		out.append("You already committed to: %s — do not contradict these."
			% ", ".join(claims))

	var open_wounds := []
	for w in wounds:
		if not w["answered"]:
			open_wounds.append("%s hit you with \"%s\"" % [w["by"], w["jab"]])
	if open_wounds.size() > 0:
		out.append("UNANSWERED: %s. Answer it directly this turn."
			% "; ".join(open_wounds))

	var hostile := _top(grudges)
	if hostile != "":
		out.append("You hold a grudge against %s (%s). Go at them, by name."
			% [hostile, _band(float(grudges[hostile]))])

	var owing := _top(debts)
	if owing != "":
		out.append("%s has conceded ground to you. Press it." % owing)

	if beats.size() > 0:
		out.append("Recently: " + " | ".join(beats))

	if banned_openers.size() > 0:
		out.append("Do NOT begin with any of: %s. Find a new opening."
			% ", ".join(banned_openers))

	if tics.size() > 0:
		out.append("Your voice: %s" % ", ".join(tics))

	out.append(_delivery_note())
	return "\n".join(out)


func _delivery_note() -> String:
	if stamina < 0.35:
		return "You are running out of patience. Short sentences. No preamble."
	if heat > 0.7:
		return "You are angry. Be sharp and personal, but stay on the argument."
	if conviction > 0.85:
		return "You are certain. Speak in flat declaratives. Concede nothing."
	if mood == "cornered":
		return "You are on the back foot. Do not fold — counterattack."
	return "Two or three sentences. Make one concrete point. No hedging."


func _refresh_mood() -> void:
	var unanswered := 0
	for w in wounds:
		if not w["answered"]:
			unanswered += 1
	if heat > 0.7 and unanswered > 0:
		mood = "cornered"
	elif heat > 0.6:
		mood = "needled"
	elif debts.size() > 0 and conviction > 0.7:
		mood = "vindicated"
	elif conviction > 0.8:
		mood = "contemptuous"
	elif debts.size() > 0:
		mood = "smug"
	else:
		mood = "measured"


# ---------------------------------------------------------------------------
# Sims layer reads these
# ---------------------------------------------------------------------------

func body_language() -> Dictionary:
	return {
		"mood": mood,
		"heat": heat,
		"conviction": conviction,
		"stamina": stamina,
		"target": _top(grudges),          # who they square up to
		"ally": _top(debts),              # who they drift toward
		"agitation": clampf(heat * 0.7 + (1.0 - stamina) * 0.3, 0.0, 1.0),
	}


func status_chip() -> String:
	return "%s · %s" % [mood, _band(conviction)]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _top(d: Dictionary) -> String:
	var best := ""
	var best_v := 0.25          # floor: weak feelings are not motivations
	for k in d:
		if float(d[k]) > best_v:
			best_v = float(d[k])
			best = String(k)
	return best


func _band(v: float) -> String:
	if v > 0.8: return "high"
	if v > 0.55: return "steady"
	if v > 0.3: return "slipping"
	return "low"


func _compress(text: String, limit: int) -> String:
	var t := text.strip_edges().replace("\n", " ")
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	if t.length() > limit:
		t = t.substr(0, limit).strip_edges() + "…"
	return t


func _opener(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return ""
	var words := t.split(" ", false)
	var take: int = mini(4, words.size())
	var slice := []
	for i in range(take):
		slice.append(words[i])
	return " ".join(slice).to_lower()


func _extract_claim(text: String) -> String:
	# The first assertive sentence is the one they can be held to. Questions
	# and hedges are not commitments -- pinning an agent to "perhaps?" makes
	# it defend nothing and the debate goes limp.
	for raw in text.replace("!", ".").replace("?", "?|").split("."):
		var s := String(raw).strip_edges()
		if s.length() < 25 or s.ends_with("?|") or s.find("?|") >= 0:
			continue
		var low := s.to_lower()
		if low.begins_with("perhaps") or low.begins_with("maybe") \
				or low.begins_with("i wonder") or low.begins_with("it depends"):
			continue
		return _compress(s, 70)
	return ""
