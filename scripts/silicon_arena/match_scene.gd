extends Node2D

## SILICON ARENA — the match.
##
## Five local AI agents at one table. Each plays a card face down and claims it
## is a SIGNAL card. The next living agent either lets it stand or calls them a
## liar. Whoever turns out to be wrong picks up the revolver.
##
## One revolver. One live round. Six chambers. The chamber holding it is fixed
## by the match seed before anyone speaks, and recorded in the replay.
##
## AUTHORITY: this script owns the cards, the truth, the challenge outcome, the
## chamber and every elimination. The model supplies dialogue and its own
## CHALLENGE / PASS call. It never decides who dies.
##
##   --seed N        deterministic match
##   --template ID   ceasefire | tribunal | lastlight
##   --replay PATH   write JSONL replay
##   --no-model      scripted dialogue only

const ClientScript := preload("res://scripts/api/lm_studio_client.gd")
const PolicyScript := preload("res://scripts/arena/model_policy.gd")

const ROSTER_PATH := "../extinct_os/config/arena-roster.v1.json"

const W := 1920.0
const H := 1080.0
const SAFE_TOP := 40.0
const SAFE_BOTTOM := 1040.0

const TABLE_C := Vector2(960, 872)
const TABLE_R := Vector2(700, 178)
const LAMP := Vector2(960, 196)

const PAL := {
	"black": Color(0.016, 0.012, 0.012),
	"maroon": Color(0.29, 0.05, 0.12),
	"maroon_hi": Color(0.55, 0.11, 0.20),
	"hemp": Color(0.37, 0.44, 0.27),
	"hemp_hi": Color(0.52, 0.57, 0.37),
	"bone": Color(0.91, 0.86, 0.78),
	"steel": Color(0.42, 0.45, 0.47),
	"amber": Color(0.91, 0.64, 0.24),
	"crit": Color(1.0, 0.17, 0.0),
}

const SEATS := [
	{"id": "agent-01", "name": "OZONIOUS", "tint": Color(1.0, 0.55, 0.45),
	 "dir": "res://assets/craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Orc/PNG/PNG Sequences",
	 "prefix": "0_Orc"},
	{"id": "agent-02", "name": "GEMMATRON", "tint": Color(0.45, 0.85, 1.0),
	 "dir": "res://assets/craftpix-891123-free-golems-chibi-2d-game-sprites2/Golem_1/PNG/PNG Sequences",
	 "prefix": "0_Golem"},
	{"id": "agent-03", "name": "SMOLLIOUS", "tint": Color(1.0, 0.78, 0.45),
	 "dir": "res://assets/craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Goblin/PNG/PNG Sequences",
	 "prefix": "0_Goblin"},
	{"id": "agent-04", "name": "GROKISH", "tint": Color(0.65, 0.55, 1.0),
	 "dir": "res://assets/craftpix-net-935193-free-chibi-necromancer-of-the-shadow-character-sprites/Necromancer_of_the_Shadow_1/PNG/PNG Sequences",
	 "prefix": "0_Necromancer_of_the_Shadow"},
	{"id": "agent-05", "name": "DANOHSHIT", "tint": Color(0.95, 0.42, 0.38),
	 "dir": "res://assets/craftpix-net-140672-free-chibi-skeleton-warrior-character-sprites/Skeleton_Warrior_1/PNG/PNG Sequences",
	 "prefix": "0_Skeleton_Warrior"},
]

const SEAT_POS := [
	Vector2(430, 858), Vector2(695, 812), Vector2(960, 792),
	Vector2(1225, 812), Vector2(1490, 858),
]
const SEAT_SCALE := [0.50, 0.465, 0.45, 0.465, 0.50]

const TEMPLATES := {
	"ceasefire": {
		"title": "THE CEASEFIRE TABLE",
		"premise": "A truce is being signed tonight. One of you already broke it.",
		"demand": "SIGNAL",
	},
	"tribunal": {
		"title": "THE LAST TRIBUNAL",
		"premise": "The archive is corrupted. One of you corrupted it.",
		"demand": "SIGNAL",
	},
	"lastlight": {
		"title": "LAST LIGHT",
		"premise": "The grid dies at dawn. One seat gets the generator.",
		"demand": "SIGNAL",
	},
}

enum Phase { OPENING, CLAIM, RESPONSE, REVEAL, CHAMBER, AFTERMATH, OVER }

## Beat lengths in seconds at speed 1. A challenged exchange runs ~17s, and a
## cylinder guarantees an elimination within six pulls, which lands a five-agent
## match in the four-to-seven minute window.
const T_OPENING := 5.0
const T_CLAIM := 4.2
const T_RESPONSE := 5.2
const T_REVEAL := 2.4
const T_CHAMBER := 3.6
const T_AFTERMATH := 2.8

## How often a claim gets called. High on purpose: an unchallenged claim is a
## dead beat, and the drama lives in the reveal.
const CHALLENGE_BASE := 0.74

var _speed := 1.0

# ── state (Godot owns all of it) ────────────────────────────────────────────
var _phase: int = Phase.OPENING
var _phase_t := 0.0
var _t := 0.0
var _seed := 0
var _template := "ceasefire"
var _rng := RandomNumberGenerator.new()

var _alive := [true, true, true, true, true]
var _hands := []            # Array[Array[bool]] — true = SIGNAL
var _turn := 0              # whose claim
var _responder := -1
var _played_is_signal := false
var _claim_is_lie := false
var _holder := -1           # who is holding the revolver
var _chamber_live := 0      # which of six chambers holds the round
var _chamber_at := 0
var _round := 1
var _shots := 0
var _grudges := {}          # "i>j" -> float

# ── view ────────────────────────────────────────────────────────────────────
var _stage: Node2D = null
var _bleed: ColorRect = null
var _actors := []
var _name_labels := []
var _subtitle: Label = null
var _banner: Label = null
var _sub_name: Label = null
var _hud_round: Label = null
var _hud_status: Label = null
var _lamp: Node2D = null
var _stage_home := Vector2.ZERO
var _speaking := 2
var _flash_rect: ColorRect = null
var _closeup: Node2D = null
var _closeup_on := false
var _portraits := []
var _table_node: Node2D = null
var _shake := 0.0
## The revolver in a held-up pose at the holder's temple during CHAMBER.
var _held_gun: Node2D = null
## Blood on the back wall. Persists for the rest of the match.
var _splatters := []
var _splat_layer: Node2D = null

## Sound. Every cue is optional: a missing file is skipped, never fatal, so a
## partial drop of audio still plays the match.
const AUDIO_DIR := "res://assets/audio"
const AUDIO_EXT := [".ogg", ".wav", ".mp3"]
var _sfx := {}
var _bus_loops := {}

# ── model ───────────────────────────────────────────────────────────────────
var _client = null
var _policy = null
var _model_key := ""
var _live := false
var _waiting := false
var _wait_started := -999.0
var _personas := {}
var _history := []
var _pending_kind := ""

# ── replay ──────────────────────────────────────────────────────────────────
var _replay_path := ""
var _replay: FileAccess = null
var _no_model := false
var _shot_dir := ""
var _shot_n := 0
var _shot_queue := []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var want_seed := -1
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): want_seed = int(args[i + 1])
		if args[i] == "--template" and i + 1 < args.size(): _template = args[i + 1]
		if args[i] == "--replay" and i + 1 < args.size(): _replay_path = args[i + 1]
		if args[i] == "--no-model": _no_model = true
		if args[i] == "--speed" and i + 1 < args.size():
			_speed = maxf(0.1, float(args[i + 1]))
		if args[i] == "--shots" and i + 1 < args.size(): _shot_dir = args[i + 1]
	if not TEMPLATES.has(_template):
		_template = "ceasefire"

	_seed = want_seed if want_seed >= 0 else int(Time.get_unix_time_from_system())
	_rng.seed = _seed
	# The bullet is placed before a word is spoken, and written to the replay.
	_chamber_live = _rng.randi_range(0, 5)

	_stage = Node2D.new()
	add_child(_stage)
	_bleed = ColorRect.new()
	_bleed.color = PAL["black"]
	_bleed.z_index = -200
	add_child(_bleed)
	move_child(_bleed, 0)
	_fit()
	get_viewport().size_changed.connect(_fit)

	_build_room()
	_build_chairs()
	_build_actors()
	_build_table()
	_build_props()
	_build_light()
	_build_atmosphere()
	_build_hud()
	_load_cards()
	_load_gun()
	_load_audio()
	_build_gun_and_blood()

	_deal_all()
	_open_replay()
	_start_model()
	_flash(str(TEMPLATES[_template]["title"]), PAL["bone"], 2.6, 62)
	_say_line("", str(TEMPLATES[_template]["premise"]))
	_phase = Phase.OPENING
	_phase_t = 0.0


func _fit() -> void:
	var vp := Vector2(get_viewport_rect().size)
	if _bleed != null:
		_bleed.size = vp
	if _stage == null:
		return
	var safe_h: float = SAFE_BOTTOM - SAFE_TOP
	var k: float = minf(vp.x / W, vp.y / safe_h)
	_stage.scale = Vector2(k, k)
	_stage.position = Vector2((vp.x - W * k) * 0.5,
		(vp.y - safe_h * k) * 0.5 - SAFE_TOP * k)
	_stage_home = _stage.position


# ════════════════════════════════════════════════════════════════════════════
# GAME
# ════════════════════════════════════════════════════════════════════════════

func _deal_all() -> void:
	_hands.clear()
	for i in SEATS.size():
		_hands.append(_deal_hand())


## Three cards. Two are usually SIGNAL, so a claim is plausible but a lie is
## always available. That tension is the whole game.
func _deal_hand() -> Array:
	var hand := []
	for c in 3:
		hand.append(_rng.randf() < 0.62)
	return hand


func _living() -> Array:
	var out := []
	for i in _alive.size():
		if _alive[i]:
			out.append(i)
	return out


func _next_living(from: int) -> int:
	for k in range(1, SEATS.size() + 1):
		var j: int = (from + k) % SEATS.size()
		if _alive[j]:
			return j
	return from


## The claim. The engine picks the card; the model only talks about it.
func _begin_claim() -> void:
	_phase = Phase.CLAIM
	_phase_t = 0.0
	if _hands[_turn].is_empty():
		_hands[_turn] = _deal_hand()
	# Bluff pressure: the fewer SIGNAL cards held, the more often a lie is the
	# only move. Grudge toward the responder nudges it further.
	var signals := 0
	for c in _hands[_turn]:
		if c:
			signals += 1
	var idx := 0
	var truth_available := signals > 0
	if truth_available:
		for i in _hands[_turn].size():
			if _hands[_turn][i]:
				idx = i
				break
	_played_is_signal = bool(_hands[_turn][idx])
	# Sometimes lie on purpose even when able to tell the truth.
	if truth_available and _rng.randf() < 0.34:
		for i in _hands[_turn].size():
			if not _hands[_turn][i]:
				idx = i
				_played_is_signal = false
				break
	_hands[_turn].remove_at(idx)
	_claim_is_lie = not _played_is_signal

	_speaking = _turn
	for i in SEATS.size():
		if _alive[i]:
			_set_anim(i, "idle")
	_light()
	_responder = _next_living(_turn)
	_sfx_play("card")
	_reveal_card = ""
	_shot("claim_%s" % _name(_turn).to_lower())
	_record({"kind": "claim", "agent": _name(_turn), "is_lie": _claim_is_lie,
		"responder": _name(_responder)})
	_ask("claim")
	_say_line(_name(_turn), _fallback_claim())
	_set_status("%s plays a card face down" % _name(_turn))


func _begin_response() -> void:
	_phase = Phase.RESPONSE
	_phase_t = 0.0
	_speaking = _responder
	_light()
	_ask("response")
	_say_line(_name(_responder), _fallback_response())


## The model's own call, with a bounded engine fallback. Grudges make a
## challenge more likely; they never force one.
func _resolve_response(challenged: bool) -> void:
	_record({"kind": "response", "agent": _name(_responder),
		"challenged": challenged})
	print("SA_RESPONSE %s challenged=%s (claim_was_lie=%s)" % [_name(_responder),
		str(challenged), str(_claim_is_lie)])
	if not challenged:
		_flash("STANDS", PAL["hemp_hi"], 1.0, 40)
		_say_line(_name(_responder), "Then it stands.")
		_phase = Phase.AFTERMATH
		_phase_t = 0.0
		_holder = -1
		return

	_phase = Phase.REVEAL
	_phase_t = 0.0
	_flash("LIAR!", PAL["maroon_hi"], 1.4, 66)
	# The card turns over. This is the only moment the table sees the truth.
	_reveal_card = "signal" if _played_is_signal else "noise"
	_reveal_at = Vector2(lerpf(SEAT_POS[_turn].x, TABLE_C.x, 0.34), TABLE_C.y - 40)
	_sfx_play("challenge")
	_shot("challenge")
	_set_anim(_responder, "strike")
	_set_anim(_turn, "hurt")
	# Truth decided here, by the engine, from the card that was actually played.
	if _claim_is_lie:
		_holder = _turn
		_say_line(_name(_responder), "%s was lying." % _name(_turn))
		_bump_grudge(_responder, _turn, 0.35)
	else:
		_holder = _responder
		_say_line(_name(_turn), "It was clean. That one is on you.")
		_bump_grudge(_turn, _responder, 0.35)
	_record({"kind": "reveal", "was_lie": _claim_is_lie, "holder": _name(_holder)})


func _begin_chamber() -> void:
	_phase = Phase.CHAMBER
	_phase_t = 0.0
	_speaking = _holder
	_light()
	_set_status("%s puts it to their own head" % _name(_holder))
	# The gun comes up to the temple and stays there for the beat.
	if _held_gun != null:
		_held_gun.visible = true
		_held_gun.position = _head_of(_holder) + Vector2(14, -340)
		_held_gun.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.tween_property(_held_gun, "modulate", Color(1, 1, 1, 1), 0.35)
		tw.parallel().tween_property(_held_gun, "position",
			_head_of(_holder) + Vector2(6, -132), 0.55)
	_set_anim(_holder, "hurt")
	if _banner != null:
		_banner.modulate = Color(1, 1, 1, 0)
	_sfx_play("spin")
	# The gun fades and travels in over ~0.6s; capturing immediately caught it
	# at almost zero alpha.
	var t3 := create_tween()
	t3.tween_interval(0.9 / _speed)
	t3.tween_callback(func() -> void: _shot("revolver_to_head"))
	_say_line(_name(_holder), _fallback_chamber())


## The shot. Deterministic: the live chamber was fixed by the seed.
func _pull_trigger() -> void:
	var live: bool = (_chamber_at == _chamber_live)
	_shots += 1
	print("SA_TRIGGER %s chamber=%d live=%d fired=%s" % [_name(_holder),
		_chamber_at, _chamber_live, str(live)])
	_record({"kind": "trigger", "agent": _name(_holder), "chamber": _chamber_at,
		"live_chamber": _chamber_live, "fired": live, "shot_no": _shots})
	_chamber_at = (_chamber_at + 1) % 6

	if _held_gun != null:
		_held_gun.visible = false
	if live:
		_sfx_play("gunshot", 0.02)
		_alive[_holder] = false
		_muzzle_at_head(_holder)
		_blood_burst(_holder)
		_add_splatter(_holder)
		_set_anim(_holder, "dying")
		_shake = 1.0
		_shot("muzzle_flash")
		_flash("%s IS OUT" % _name(_holder), PAL["crit"], 2.4, 68)
		_set_status("the chamber was loaded")
		# Deferred: the flash is still on screen at the instant of the shot, and
		# the dying animation has not played yet.
		_sfx_play("death")
		var dead_name := _name(_holder).to_lower()
		var t2 := create_tween()
		t2.tween_interval(1.5 / _speed)
		t2.tween_callback(func() -> void: _shot("elimination_%s" % dead_name))
		var a = _actor(_holder)
		if a != null:
			# Slump, then go dark. The dying animation plays through first.
			create_tween().tween_property(a["holder"], "position",
				SEAT_POS[_holder] + Vector2(0, 46), 1.4)
			var dim := create_tween()
			dim.tween_interval(0.9)
			dim.tween_property(a["sprite"], "modulate",
				Color(0.11, 0.08, 0.08, 0.55), 1.1)
			create_tween().tween_property(a["rim"], "modulate",
				Color(0.35, 0.06, 0.06, 0.10), 0.9)
		if _portraits.size() > _holder:
			_portraits[_holder]["dead"] = true
		# fresh cylinder for the next holder
		_chamber_live = _rng.randi_range(0, 5)
		_chamber_at = 0
	else:
		_sfx_play("click")
		_set_anim(_holder, "idle")
		_flash("EMPTY", PAL["hemp_hi"], 1.4, 58)
		_set_status("empty chamber")
		_say_line(_name(_holder), "Still here.")
	_phase = Phase.AFTERMATH
	_phase_t = 0.0
	_closeup_show(false)


func _aftermath() -> void:
	var living := _living()
	if living.size() <= 1:
		_phase = Phase.OVER
		_phase_t = 0.0
		var last: int = living[0] if living.size() == 1 else -1
		_record({"kind": "match_end", "survivor": _name(last), "rounds": _round,
			"shots": _shots})
		_survivor_card(last)
		if _replay != null:
			_replay.flush()
		return
	_round += 1
	_turn = _next_living(_turn)
	_update_hud()
	_phase = Phase.CLAIM
	_phase_t = 0.0
	_begin_claim()


func _bump_grudge(from: int, to: int, amount: float) -> void:
	var key := "%d>%d" % [from, to]
	_grudges[key] = clampf(float(_grudges.get(key, 0.0)) + amount, -1.0, 1.0)


func _grudge(from: int, to: int) -> float:
	return float(_grudges.get("%d>%d" % [from, to], 0.0))


func _name(i: int) -> String:
	return str(SEATS[i]["name"]) if i >= 0 and i < SEATS.size() else "NOBODY"


# ════════════════════════════════════════════════════════════════════════════
# MODEL
# ════════════════════════════════════════════════════════════════════════════

func _start_model() -> void:
	if _no_model:
		_set_status("scripted dialogue (--no-model)")
		return
	var f := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if f == null:
		_set_status("no roster - scripted dialogue")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_set_status("roster unreadable - scripted dialogue")
		return
	for a in parsed.get("agents", []):
		_personas[str(a.get("display_name", ""))] = str(a.get("persona", ""))
	var runtimes: Array = parsed.get("runtimes", [])
	if runtimes.is_empty():
		_set_status("no runtime - scripted dialogue")
		return
	_model_key = str(runtimes[0].get("model_key", ""))

	_policy = PolicyScript.new()
	add_child(_policy)
	if not _policy.load_catalog():
		_set_status("catalog unavailable - scripted dialogue")
		return
	var reason: String = _policy.check(_model_key)
	if reason != "":
		_set_status("model refused - scripted dialogue")
		return
	_client = ClientScript.new()
	_client.model_policy = _policy
	add_child(_client)
	_live = true
	_set_status("LIVE  %s" % _model_key)


func _ask(kind: String) -> void:
	if not _live or _waiting:
		return
	var who: int = _turn if kind == "claim" else _responder
	if kind == "chamber":
		who = _holder
	var nm := _name(who)
	var persona: String = str(_personas.get(nm, "an operator at this table"))
	var others := []
	for i in SEATS.size():
		if i != who and _alive[i]:
			others.append(_name(i))

	var p := "You are %s at a table with %s.\n" % [nm, ", ".join(others)]
	p += "Character: %s\n" % persona.substr(0, 300)
	p += "SITUATION: %s\n" % str(TEMPLATES[_template]["premise"])
	# Give them the actual words, and make answering those words the task. A
	# transcript alone gets parroted; naming the speaker and demanding a reply
	# to their specific point is what makes it read as listening.
	if not _history.is_empty():
		var recent: Array = _history.slice(maxi(0, _history.size() - 3), _history.size())
		p += "WHAT WAS JUST SAID, most recent last:\n"
		for h in recent:
			p += "  %s\n" % h
		var last: String = str(recent[recent.size() - 1])
		var who_last := last.substr(0, maxi(0, last.find(":")))
		if who_last != "" and who_last != nm:
			p += "\nYou are answering %s. Pick ONE specific thing they said and " % who_last
			p += "react to THAT: agree, twist it, throw it back, or call it a lie. "
			p += "Do not change the subject and do not repeat their words.\n"
	match kind:
		"claim":
			p += "\nYou just played a card face down and claimed it is SIGNAL.\n"
			p += "Say ONE short line selling that claim to %s. Under 16 words.\n" % _name(_responder)
		"response":
			p += "\n%s claims their face-down card is SIGNAL.\n" % _name(_turn)
			p += "Decide. Start your reply with exactly CHALLENGE or PASS, then a "
			p += "comma, then ONE short line under 14 words.\n"
		"chamber":
			p += "\nYou lost the call. The revolver is in your hand.\n"
			p += "Say ONE short line, under 12 words, before you pull.\n"
	p += "Output only the words. No name prefix, no quotes, no stage directions."

	_waiting = true
	_wait_started = _t
	_pending_kind = kind
	_client.chat_completion(nm, _model_key, [{"role": "user", "content": p}],
		func(ok: bool, reply: String, code: int):
			_waiting = false
			if not ok:
				_set_status("model error %d - scripted" % code)
				return
			_on_reply(kind, who, reply),
		{"temperature": 0.85, "max_tokens": 56, "top_p": 0.92})


func _on_reply(kind: String, who: int, raw: String) -> void:
	var text := _clean(raw)
	if kind == "response":
		var upper := text.to_upper()
		var challenged := upper.begins_with("CHALLENGE")
		# strip the verb off the spoken line
		for verb in ["CHALLENGE,", "CHALLENGE", "PASS,", "PASS"]:
			if upper.begins_with(verb):
				text = text.substr(verb.length()).strip_edges()
				break
		text = text.lstrip(",").strip_edges()
		if text != "":
			_say_line(_name(who), text)
		_record({"kind": "model_call", "agent": _name(who), "challenged": challenged})
		if _phase == Phase.RESPONSE:
			_resolve_response(challenged)
		return
	if text != "":
		_say_line(_name(who), text)


func _clean(t0: String) -> String:
	var t := t0.strip_edges().replace("\n", " ").replace("\r", " ")
	for junk in ["\"", "“", "”", "*"]:
		t = t.replace(junk, "")
	var colon := t.find(":")
	if colon > 0 and colon <= 22:
		t = t.substr(colon + 1).strip_edges()
	for i in SEATS.size():
		var at := t.to_upper().find(_name(i).to_upper() + ":")
		if at > 0:
			t = t.substr(0, at).strip_edges()
	var dash := t.rfind(" - ")
	if dash > 0 and t.length() - dash < 26:
		t = t.substr(0, dash).strip_edges()
	if t.length() > 108:
		var cut := -1
		for mark in [". ", "? ", "! "]:
			var m := t.find(mark)
			if m > 20 and (cut < 0 or m < cut):
				cut = m + 1
		t = t.substr(0, cut).strip_edges() if cut > 0 else t.substr(0, 104).strip_edges()
	return t


# ── scripted fallbacks, so a dead LM Studio never stops the match ───────────

const CLAIM_LINES := [
	"Clean card. Look at me while I say it.",
	"Signal. Take it or call it.",
	"I have no reason to burn a card on you.",
	"You want to do this now? Fine. Signal.",
	"Read the room before you read me.",
]
const RESPONSE_LINES := [
	"I do not believe a word of that.",
	"Let it stand. For now.",
	"You blinked when you said signal.",
	"Not worth the chamber. Pass.",
	"Turn it over.",
]
const CHAMBER_LINES := [
	"One of six. I have had worse odds.",
	"Tell them I did not flinch.",
	"This is a stupid way to be right.",
	"Somebody count for me.",
]

func _fallback_claim() -> String:
	return str(CLAIM_LINES[_rng.randi_range(0, CLAIM_LINES.size() - 1)])

func _fallback_response() -> String:
	return str(RESPONSE_LINES[_rng.randi_range(0, RESPONSE_LINES.size() - 1)])

func _fallback_chamber() -> String:
	return str(CHAMBER_LINES[_rng.randi_range(0, CHAMBER_LINES.size() - 1)])


## Engine decision, used when no model answered in time. Grudge raises the
## chance of a challenge; it never guarantees one.
func _engine_challenge() -> bool:
	var g := _grudge(_responder, _turn)
	return _rng.randf() < clampf(CHALLENGE_BASE + g * 0.20, 0.35, 0.95)


# ════════════════════════════════════════════════════════════════════════════
# LOOP
# ════════════════════════════════════════════════════════════════════════════

## Save a frame at a named beat. Deferred by one frame so what lands in the PNG
## is what the beat actually looks like, not the frame before it.
func _shot(tag: String) -> void:
	if _shot_dir == "":
		return
	# A queue, not a slot: muzzle flash and elimination fire in the same frame
	# and the second was overwriting the first.
	_shot_queue.append(tag)


## One capture at a time. Without the guard, several coroutines await the same
## frame, pop from the same queue and collide on the counter, which silently
## dropped most of the beats in the first pass.
var _shooting := false

func _do_shot() -> void:
	if _shooting:
		return
	_shooting = true
	var tag: String = str(_shot_queue.pop_front())
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shooting = false
	if img == null:
		print("SA_SHOT_FAILED %s" % tag)
		return
	_shot_n += 1
	var path := "%s/%02d_%s.png" % [_shot_dir, _shot_n, tag]
	var err := img.save_png(path)
	if err != OK:
		print("SA_SHOT_ERR %s %d" % [tag, err])
		return
	print("SA_SHOT %s" % path)


func _process(delta: float) -> void:
	_t += delta
	if not _shot_queue.is_empty():
		_do_shot()
	_phase_t += delta

	if _waiting and _t - _wait_started > 22.0:
		_waiting = false
		_set_status("model timeout - scripted")

	_tick_view(delta)

	match _phase:
		Phase.OPENING:
			if _phase_t >= T_OPENING / _speed:
				_begin_claim()
		Phase.CLAIM:
			if _phase_t >= T_CLAIM / _speed and not _waiting:
				_begin_response()
		Phase.RESPONSE:
			# The model gets a window to make its own call; after that the
			# engine decides so the match never stalls.
			if _phase_t >= T_RESPONSE / _speed:
				_resolve_response(_engine_challenge())
		Phase.REVEAL:
			if _phase_t >= T_REVEAL / _speed:
				_begin_chamber()
		Phase.CHAMBER:
			if _phase_t >= T_CHAMBER / _speed:
				_pull_trigger()
		Phase.AFTERMATH:
			if _phase_t >= T_AFTERMATH / _speed:
				_aftermath()
		Phase.OVER:
			if _phase_t >= 6.0 / _speed and _shot_dir != "":
				_shot("07_survivor")
				get_tree().quit()


# ════════════════════════════════════════════════════════════════════════════
# REPLAY
# ════════════════════════════════════════════════════════════════════════════

func _open_replay() -> void:
	if _replay_path == "":
		return
	_replay = FileAccess.open(_replay_path, FileAccess.WRITE)
	if _replay == null:
		return
	_record({"kind": "match_start", "seed": _seed, "template": _template,
		"live_chamber": _chamber_live, "model": _model_key,
		"agents": [_name(0), _name(1), _name(2), _name(3), _name(4)],
		"schema": "silicon_arena_replay/1.0"})


func _record(row: Dictionary) -> void:
	if _replay == null:
		return
	row["t_ms"] = int(_t * 1000.0)
	row["round"] = _round
	_replay.store_line(JSON.stringify(row))


func _exit_tree() -> void:
	if _replay != null:
		_replay.close()


# ════════════════════════════════════════════════════════════════════════════
# VIEW
# ════════════════════════════════════════════════════════════════════════════

var _props: Node2D = null
var _crt_mat: ShaderMaterial = null


const ROOM_TEX := "res://assets/generated/room_back.png"
const CARD_TEX := {
	"back": "res://assets/generated/card_back.png",
	"signal": "res://assets/generated/card_signal.png",
	"noise": "res://assets/generated/card_noise.png",
}
var _cards := {}
## The card just played, shown face up only after a challenge.
var _reveal_card := ""
var _reveal_at := Vector2.ZERO

func _build_room() -> void:
	var bg := ColorRect.new()
	bg.color = PAL["black"]
	bg.size = Vector2(W, H)
	bg.z_index = -100
	_stage.add_child(bg)

	# A real wall behind the table: the dungeon pack's stone brick tile, retiled
	# and pushed into this project's palette by tools/gen_room.py. Replaces the
	# black gradient that made the room read as a void.
	if ResourceLoader.exists(ROOM_TEX):
		var wall := TextureRect.new()
		wall.texture = load(ROOM_TEX)
		wall.size = Vector2(W, H)
		wall.z_index = -99
		wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wall.stretch_mode = TextureRect.STRETCH_SCALE
		wall.modulate = Color(1, 1, 1, 1)
		_stage.add_child(wall)
	var wall := _radial(Vector2(960, 540), 1000.0, Color(0.13, 0.06, 0.05, 0.36))
	wall.z_index = -95
	_stage.add_child(wall)
	var fl := _radial(Vector2(960, 950), 840.0, Color(0.10, 0.06, 0.045, 0.5))
	fl.z_index = -94
	_stage.add_child(fl)


func _build_chairs() -> void:
	var n := Node2D.new()
	n.z_index = -60
	n.draw.connect(func() -> void:
		for i in SEAT_POS.size():
			var p: Vector2 = SEAT_POS[i]
			var s: float = SEAT_SCALE[i]
			var w := 150.0 * s
			var h := 250.0 * s
			n.draw_rect(Rect2(p.x - w * 0.5, p.y - h, w, h), Color(0.042, 0.030, 0.028), true)
			n.draw_rect(Rect2(p.x - w * 0.5, p.y - h, w, h), Color(0.10, 0.07, 0.06), false, 2.0)
			for dx in [-1.0, 1.0]:
				n.draw_rect(Rect2(p.x + dx * w * 0.5 - 4, p.y - h, 8, h + 40),
					Color(0.055, 0.040, 0.036), true)
	)
	_stage.add_child(n)
	n.queue_redraw()


func _build_actors() -> void:
	for i in SEATS.size():
		var frames := _load_frames(i)
		if frames == null:
			continue
		var holder := Node2D.new()
		holder.position = SEAT_POS[i]
		holder.z_index = -50 + i
		_stage.add_child(holder)

		var tint: Color = SEATS[i]["tint"]
		var rim := AnimatedSprite2D.new()
		rim.sprite_frames = frames
		rim.centered = false
		rim.scale = Vector2.ONE * SEAT_SCALE[i] * 1.05
		rim.offset = Vector2(-_frame_w * 0.5, -_frame_h)
		rim.modulate = Color(tint.r, tint.g, tint.b, 0.30)
		rim.z_index = -1
		holder.add_child(rim)
		rim.play("idle")

		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.centered = false
		spr.scale = Vector2.ONE * SEAT_SCALE[i]
		spr.offset = Vector2(-_frame_w * 0.5, -_frame_h)
		spr.modulate = Color(0.26, 0.245, 0.23)
		holder.add_child(spr)
		spr.play("idle")
		# Everyone breathes on their own clock.
		spr.frame = _rng.randi_range(0, 11)
		rim.frame = spr.frame

		_actors.append({"holder": holder, "sprite": spr, "rim": rim, "index": i,
			"phase": _rng.randf() * TAU, "anim": "idle"})


var _frame_w := 380.0
var _frame_h := 560.0


## Build SpriteFrames from the PNG sequences already on disk. Subsampled so the
## whole roster fits comfortably in 8GB: the packs ship 24-36 frames per state
## and every second or third one reads identically in motion.
func _load_frames(i: int) -> SpriteFrames:
	var dir: String = str(SEATS[i]["dir"])
	var pre: String = str(SEATS[i]["prefix"])
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var built := 0
	# Frame counts differ per state AND per pack, so the directory is the source
	# of truth rather than a hardcoded count.
	for spec in [["idle", "Idle Blinking", true, 10.0],
			["hurt", "Hurt", false, 16.0],
			["dying", "Dying", false, 14.0],
			["strike", "Slashing", false, 18.0]]:
		var anim: String = str(spec[0])
		sf.add_animation(anim)
		sf.set_animation_loop(anim, bool(spec[2]))
		sf.set_animation_speed(anim, float(spec[3]))
		var folder := "%s/%s" % [dir, str(spec[1])]
		var names := _pngs_in(folder)
		# Subsample to keep the whole roster comfortable in 8GB.
		var step: int = 2 if names.size() > 16 else 1
		var n := 0
		for k in range(0, names.size(), step):
			var tex: Texture2D = load("%s/%s" % [folder, names[k]])
			if tex == null:
				continue
			sf.add_frame(anim, tex)
			n += 1
			if built == 0 and n == 1:
				_frame_w = float(tex.get_width())
				_frame_h = float(tex.get_height())
		if n > 0:
			built += 1
	if built == 0:
		push_warning("[arena] no frames for %s" % _name(i))
		return null
	return sf


## Sorted PNG names in a sequence folder. Godot exports strip .import files, so
## only real textures are returned.
func _pngs_in(folder: String) -> Array:
	var out := []
	var d := DirAccess.open(folder)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png"):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## Switch an actor's animation. Non-looping states fall back to idle.
func _set_anim(i: int, anim: String) -> void:
	var a = _actor(i)
	if a == null or str(a["anim"]) == anim:
		return
	a["anim"] = anim
	var spr: AnimatedSprite2D = a["sprite"]
	var rim: AnimatedSprite2D = a["rim"]
	if spr.sprite_frames == null or not spr.sprite_frames.has_animation(anim):
		return
	spr.play(anim)
	rim.play(anim)


func _build_table() -> void:
	var t := Node2D.new()
	t.z_index = 10
	t.draw.connect(func() -> void:
		_ellipse(t, TABLE_C + Vector2(0, 26), TABLE_R * 1.04, Color(0, 0, 0, 0.75))
		_ellipse(t, TABLE_C + Vector2(0, 20), TABLE_R, Color(0.033, 0.023, 0.019))
		_ellipse(t, TABLE_C, TABLE_R, Color(0.052, 0.034, 0.027))
		_ellipse(t, TABLE_C + Vector2(0, -10), TABLE_R * 0.80, Color(0.125, 0.078, 0.050, 0.85))
		_ellipse(t, TABLE_C + Vector2(0, -16), TABLE_R * 0.56, Color(0.23, 0.14, 0.080, 0.80))
		_ellipse(t, TABLE_C + Vector2(0, -22), TABLE_R * 0.32, Color(0.36, 0.22, 0.115, 0.70))
		for k in 44:
			var a: float = PI + PI * (float(k) / 43.0)
			t.draw_circle(TABLE_C + Vector2(cos(a) * TABLE_R.x, sin(a) * TABLE_R.y),
				2.2, Color(0.58, 0.38, 0.21, 0.45))
	)
	_stage.add_child(t)
	t.queue_redraw()
	_table_node = t


func _build_props() -> void:
	var p := Node2D.new()
	p.z_index = 12
	p.draw.connect(func() -> void:
		for i in SEAT_POS.size():
			if not _alive[i]:
				continue
			var cx: float = lerpf(SEAT_POS[i].x, TABLE_C.x, 0.10)
			var cy: float = TABLE_C.y - 62 + absf(float(i) - 2.0) * 26.0
			var n: int = _hands[i].size() if i < _hands.size() else 0
			for c in n:
				var r := Rect2(cx - 30 + c * 15, cy - 22 + c * 3, 32, 48)
				if _cards.has("back"):
					p.draw_texture_rect(_cards["back"], r, false)
				else:
					p.draw_rect(r, Color(0.62, 0.57, 0.48, 0.92), true)
					p.draw_rect(r, Color(0.12, 0.09, 0.07), false, 1.5)
		# The played card, face up only once somebody has called it.
		if _reveal_card != "" and _cards.has(_reveal_card):
			var rr := Rect2(_reveal_at.x - 46, _reveal_at.y - 68, 92, 138)
			p.draw_texture_rect(_cards[_reveal_card], rr, false)
		# Only draw it on the table when nobody has picked it up.
		if _held_gun == null or not _held_gun.visible:
			_draw_revolver(p, TABLE_C + Vector2(0, -6), -0.20, 1.0)
	)
	_stage.add_child(p)
	p.queue_redraw()
	_props = p


## The revolver is real art now, not primitives. Base width is normalised so
## k=1.0 keeps the same on-table size the code-drawn version had.
const GUN_TEX_PATH := "res://assets/props/revolver_side.png"
const GUN_BASE_W := 380.0
var _gun_tex: Texture2D = null


func _load_cards() -> void:
	for k in CARD_TEX:
		if ResourceLoader.exists(str(CARD_TEX[k])):
			_cards[k] = load(str(CARD_TEX[k]))


func _load_gun() -> void:
	if ResourceLoader.exists(GUN_TEX_PATH):
		_gun_tex = load(GUN_TEX_PATH)


func _draw_revolver(c: CanvasItem, at: Vector2, rot: float, k: float, reveal := false) -> void:
	if _gun_tex == null:
		return
	var tw := float(_gun_tex.get_width())
	var th := float(_gun_tex.get_height())
	var base := GUN_BASE_W / tw
	var w := tw * base
	var h := th * base
	# Shadow first, so it reads as sitting on a surface.
	c.draw_set_transform(at + Vector2(7, 13) * k, rot, Vector2(k, k))
	c.draw_texture_rect(_gun_tex, Rect2(-w * 0.5, -h * 0.5, w, h), false,
		Color(0, 0, 0, 0.55))
	c.draw_set_transform(at, rot, Vector2(k, k))
	c.draw_texture_rect(_gun_tex, Rect2(-w * 0.5, -h * 0.5, w, h), false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _build_light() -> void:
	var lamp := Node2D.new()
	lamp.z_index = 40
	lamp.draw.connect(func() -> void:
		lamp.draw_line(Vector2(LAMP.x, -10), LAMP + Vector2(0, -18), Color(0.15, 0.12, 0.10), 3.0)
		lamp.draw_circle(LAMP, 15, Color(1.0, 0.88, 0.66))
		lamp.draw_circle(LAMP, 27, Color(1.0, 0.74, 0.38, 0.30))
		lamp.draw_circle(LAMP, 58, Color(1.0, 0.64, 0.30, 0.13))
		lamp.draw_circle(LAMP, 120, Color(1.0, 0.60, 0.26, 0.045))
	)
	_stage.add_child(lamp)
	lamp.queue_redraw()
	_lamp = lamp

	var cone := Node2D.new()
	cone.z_index = 39
	cone.draw.connect(func() -> void:
		cone.draw_colored_polygon(PackedVector2Array([LAMP + Vector2(-22, 14),
			LAMP + Vector2(22, 14), Vector2(1680, 1020), Vector2(240, 1020)]),
			Color(1.0, 0.66, 0.30, 0.034))
		cone.draw_colored_polygon(PackedVector2Array([LAMP + Vector2(-14, 14),
			LAMP + Vector2(14, 14), Vector2(1380, 990), Vector2(540, 990)]),
			Color(1.0, 0.72, 0.36, 0.030))
	)
	_stage.add_child(cone)
	cone.queue_redraw()


func _build_atmosphere() -> void:
	var dust := CPUParticles2D.new()
	dust.position = Vector2(960, 540)
	dust.amount = 110
	dust.lifetime = 9.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(440, 320)
	dust.direction = Vector2(0, 1)
	dust.spread = 24.0
	dust.gravity = Vector2(2, 5)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 9.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 2.0
	dust.color = Color(1.0, 0.82, 0.55, 0.14)
	dust.z_index = 45
	_stage.add_child(dust)

	var vig := ColorRect.new()
	vig.size = Vector2(W, H)
	vig.z_index = 88
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nvoid fragment(){vec2 p=UV-vec2(0.5);float d=length(p*vec2(1.25,1.0));COLOR=vec4(0.0,0.0,0.0,smoothstep(0.33,0.92,d)*0.92);}"
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vig.material = vm
	_stage.add_child(vig)

	# CRT scanlines plus grain: the command-room texture.
	var crt := ColorRect.new()
	crt.size = Vector2(W, H)
	crt.z_index = 89
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := Shader.new()
	cs.code = "shader_type canvas_item;\nuniform float t=0.0;\nfloat n(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}\nvoid fragment(){float sl=step(0.5,fract(UV.y*540.0));float g=n(UV*vec2(1920.0,1080.0)+vec2(t*37.0,t*91.0));COLOR=vec4(vec3(g),0.045+sl*0.030);}"
	var cm := ShaderMaterial.new()
	cm.shader = cs
	crt.material = cm
	_stage.add_child(crt)
	_crt_mat = cm

	_flash_rect = ColorRect.new()
	_flash_rect.size = Vector2(W, H)
	_flash_rect.color = Color(1, 0.93, 0.80, 0)
	_flash_rect.z_index = 95
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_flash_rect)


func _build_hud() -> void:
	# CRT portrait strip. Each agent gets a panel that dies with them.
	for i in SEATS.size():
		var x: float = 96.0 + float(i) * 350.0
		var panel := Node2D.new()
		panel.z_index = 72
		panel.position = Vector2(x, 62)
		var rec := {"node": panel, "index": i, "dead": false}
		panel.draw.connect(func() -> void:
			var tint: Color = SEATS[i]["tint"]
			var dead: bool = bool(rec["dead"])
			var a: float = 0.22 if dead else (1.0 if i == _speaking else 0.55)
			panel.draw_rect(Rect2(0, 0, 310, 74), Color(0.035, 0.028, 0.026, 0.92), true)
			panel.draw_rect(Rect2(0, 0, 310, 74), Color(tint.r, tint.g, tint.b, a), false, 2.0)
			# scan bar
			for s in 9:
				panel.draw_rect(Rect2(4, 6.0 + float(s) * 8.0, 302, 3),
					Color(tint.r, tint.g, tint.b, 0.05 * a), true)
			if dead:
				panel.draw_line(Vector2(8, 8), Vector2(302, 66), Color(1.0, 0.2, 0.1, 0.65), 3.0)
				panel.draw_line(Vector2(302, 8), Vector2(8, 66), Color(1.0, 0.2, 0.1, 0.65), 3.0)
		)
		_stage.add_child(panel)
		_portraits.append(rec)
		panel.queue_redraw()

		var lbl := Label.new()
		lbl.text = str(SEATS[i]["name"])
		lbl.z_index = 73
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.position = Vector2(x + 12, 78)
		lbl.size = Vector2(290, 26)
		_stage.add_child(lbl)
		_name_labels.append(lbl)

	_hud_round = Label.new()
	_hud_round.z_index = 73
	_hud_round.add_theme_font_size_override("font_size", 20)
	_hud_round.add_theme_color_override("font_color", PAL["bone"])
	_hud_round.add_theme_constant_override("outline_size", 5)
	_hud_round.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_round.position = Vector2(96, 122)
	_hud_round.size = Vector2(900, 26)
	_stage.add_child(_hud_round)

	_hud_status = Label.new()
	_hud_status.z_index = 73
	_hud_status.add_theme_font_size_override("font_size", 15)
	_hud_status.add_theme_color_override("font_color", Color(0.42, 0.46, 0.44, 0.8))
	_hud_status.add_theme_constant_override("outline_size", 4)
	_hud_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_status.position = Vector2(96, 152)
	_hud_status.size = Vector2(1100, 22)
	_stage.add_child(_hud_status)

	_banner = Label.new()
	_banner.z_index = 90
	_banner.add_theme_font_size_override("font_size", 62)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_banner.position = Vector2(160, 380)
	_banner.size = Vector2(1600, 90)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate = Color(1, 1, 1, 0)
	_stage.add_child(_banner)

	_sub_name = Label.new()
	_sub_name.z_index = 74
	_sub_name.add_theme_font_size_override("font_size", 19)
	_sub_name.add_theme_constant_override("outline_size", 5)
	_sub_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_sub_name.position = Vector2(260, 946)
	_sub_name.size = Vector2(1400, 26)
	_sub_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(_sub_name)

	_subtitle = Label.new()
	_subtitle.z_index = 74
	_subtitle.add_theme_font_size_override("font_size", 30)
	_subtitle.add_theme_color_override("font_color", PAL["bone"])
	_subtitle.add_theme_constant_override("outline_size", 8)
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_subtitle.position = Vector2(200, 976)
	_subtitle.size = Vector2(1520, 44)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(_subtitle)

	_update_hud()


func _build_gun_and_blood() -> void:
	# Blood sits behind the actors so it reads as being ON the wall, not on them.
	var sp := Node2D.new()
	sp.z_index = -70
	sp.draw.connect(func() -> void:
		for b in _splatters:
			var at: Vector2 = b["at"]
			var col: Color = b["col"]
			for blob in b["blobs"]:
				sp.draw_circle(at + Vector2(blob[0], blob[1]), float(blob[2]), col)
			# runs
			for run in b["runs"]:
				sp.draw_rect(Rect2(at.x + float(run[0]), at.y + float(run[1]),
					float(run[2]), float(run[3])), col, true)
	)
	_stage.add_child(sp)
	sp.queue_redraw()
	_splat_layer = sp

	var g := Node2D.new()
	g.z_index = 30
	g.visible = false
	g.draw.connect(func() -> void:
		if _holder < 0:
			return
		# Held up beside the head, barrel toward the temple.
		# Barrel DOWN at the crown of the head. The muzzle sits 150*scale below
		# the pivot, which is what the rest position below is derived from.
		_draw_revolver(g, Vector2.ZERO, -1.5708, 0.46, false)
	)
	_stage.add_child(g)
	_held_gun = g


## A permanent mark on the wall behind the seat.
func _add_splatter(i: int) -> void:
	var at: Vector2 = _head_of(i) + Vector2(_rng.randf_range(-30, 30), -34)
	var blobs := []
	for k in 26:
		var ang := _rng.randf_range(0.0, TAU)
		var rad := _rng.randf_range(6.0, 150.0)
		blobs.append([cos(ang) * rad, sin(ang) * rad * 0.72,
			_rng.randf_range(3.0, 20.0) * (1.0 - rad / 210.0)])
	var runs := []
	for k in 7:
		var x := _rng.randf_range(-90.0, 90.0)
		runs.append([x, _rng.randf_range(-10.0, 40.0), _rng.randf_range(2.0, 6.0),
			_rng.randf_range(30.0, 170.0)])
	_splatters.append({"at": at, "col": Color(0.34, 0.03, 0.05, 0.92),
		"blobs": blobs, "runs": runs})
	if _splat_layer != null:
		_splat_layer.queue_redraw()


## Spray, at the head, away from the wall.
func _blood_burst(i: int) -> void:
	var pa := CPUParticles2D.new()
	pa.position = _head_of(i)
	pa.z_index = 44
	pa.amount = 120
	pa.lifetime = 1.5
	pa.one_shot = true
	pa.explosiveness = 0.96
	pa.direction = Vector2(0, -1)
	pa.spread = 78.0
	pa.gravity = Vector2(0, 900)
	pa.initial_velocity_min = 160.0
	pa.initial_velocity_max = 620.0
	pa.scale_amount_min = 1.5
	pa.scale_amount_max = 6.0
	pa.color = Color(0.46, 0.03, 0.05, 0.95)
	_stage.add_child(pa)
	pa.emitting = true
	# A short-lived mist that fades before the splatter is read.
	var mist := CPUParticles2D.new()
	mist.position = _head_of(i)
	mist.z_index = 43
	mist.amount = 40
	mist.lifetime = 2.2
	mist.one_shot = true
	mist.explosiveness = 0.9
	mist.direction = Vector2(0, -1)
	mist.spread = 180.0
	mist.gravity = Vector2(0, 90)
	mist.initial_velocity_min = 20.0
	mist.initial_velocity_max = 140.0
	mist.scale_amount_min = 6.0
	mist.scale_amount_max = 18.0
	mist.color = Color(0.30, 0.02, 0.04, 0.30)
	_stage.add_child(mist)
	mist.emitting = true


func _build_closeup() -> void:
	var c := Node2D.new()
	c.z_index = 84
	c.modulate = Color(1, 1, 1, 0)
	c.draw.connect(func() -> void:
		c.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.008, 0.008, 0.90), true)
		_draw_revolver(c, Vector2(960, 560), -0.06, 2.6, true)
	)
	_stage.add_child(c)
	c.queue_redraw()
	_closeup = c


func _closeup_show(on: bool) -> void:
	_closeup_on = on
	if _closeup == null:
		return
	_closeup.queue_redraw()
	create_tween().tween_property(_closeup, "modulate",
		Color(1, 1, 1, 1.0 if on else 0.0), 0.45)


## A hard local flash at the temple, then the screen hit. Reads as a gunshot
## rather than a lighting change.
func _muzzle_at_head(i: int) -> void:
	var f := Node2D.new()
	f.z_index = 46
	f.position = _head_of(i) + Vector2(2, -40)
	var life := {"t": 0.0}
	f.draw.connect(func() -> void:
		f.draw_circle(Vector2.ZERO, 78, Color(1.0, 0.92, 0.66, 0.95))
		f.draw_circle(Vector2.ZERO, 150, Color(1.0, 0.62, 0.20, 0.55))
		for k in 8:
			var a2: float = TAU * float(k) / 8.0 + 0.3
			f.draw_line(Vector2.ZERO, Vector2(cos(a2), sin(a2)) * 240.0,
				Color(1.0, 0.80, 0.40, 0.7), 9.0)
	)
	_stage.add_child(f)
	f.queue_redraw()
	var tw := create_tween()
	tw.tween_property(f, "modulate", Color(1, 1, 1, 0), 0.28)
	tw.tween_callback(f.queue_free)
	_muzzle_flash()


func _muzzle_flash() -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = Color(1, 0.90, 0.72, 0.55)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color", Color(1, 0.45, 0.16, 0.20), 0.05)
	tw.tween_property(_flash_rect, "color", Color(1, 0.90, 0.72, 0.0), 0.30)


func _survivor_card(idx: int) -> void:
	var card := ColorRect.new()
	card.size = Vector2(W, H)
	card.color = Color(0.012, 0.009, 0.009, 0.0)
	card.z_index = 96
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(card)
	create_tween().tween_property(card, "color", Color(0.012, 0.009, 0.009, 0.96), 1.2)

	var t1 := Label.new()
	t1.text = "LAST ONE SITTING"
	t1.z_index = 97
	t1.add_theme_font_size_override("font_size", 30)
	t1.add_theme_color_override("font_color", PAL["steel"])
	t1.position = Vector2(160, 400)
	t1.size = Vector2(1600, 40)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.modulate = Color(1, 1, 1, 0)
	_stage.add_child(t1)

	var t2 := Label.new()
	t2.text = _name(idx)
	t2.z_index = 97
	t2.add_theme_font_size_override("font_size", 96)
	var tint: Color = SEATS[idx]["tint"] if idx >= 0 else PAL["bone"]
	t2.add_theme_color_override("font_color", tint)
	t2.add_theme_constant_override("outline_size", 14)
	t2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	t2.position = Vector2(160, 450)
	t2.size = Vector2(1600, 120)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.modulate = Color(1, 1, 1, 0)
	_stage.add_child(t2)

	var t3 := Label.new()
	t3.text = "seed %d   ·   %d shots fired   ·   %s" % [_seed, _shots,
		("model " + _model_key) if _live else "scripted dialogue"]
	t3.z_index = 97
	t3.add_theme_font_size_override("font_size", 20)
	t3.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	t3.position = Vector2(160, 596)
	t3.size = Vector2(1600, 30)
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t3.modulate = Color(1, 1, 1, 0)
	_stage.add_child(t3)

	for n in [t1, t2, t3]:
		var tw := create_tween()
		tw.tween_interval(0.8)
		tw.tween_property(n, "modulate", Color(1, 1, 1, 1), 0.9)
	_sfx_play("survivor", 0.0)
	for cue in _bus_loops:
		create_tween().tween_property(_bus_loops[cue], "volume_db", -60.0, 2.5)
	print("SILICON_ARENA_SURVIVOR %s seed=%d shots=%d" % [_name(idx), _seed, _shots])


# ── per-frame view ─────────────────────────────────────────────────────────

func _light() -> void:
	for a in _actors:
		var i: int = a["index"]
		if not _alive[i]:
			continue
		var lit: float = 1.0 if i == _speaking else 0.26
		var tint: Color = SEATS[i]["tint"]
		create_tween().tween_property(a["sprite"], "modulate",
			Color(lit, lit * 0.94, lit * 0.88), 0.4)
		create_tween().tween_property(a["rim"], "modulate",
			Color(tint.r, tint.g, tint.b, 0.75 if i == _speaking else 0.28), 0.4)
		create_tween().tween_property(a["holder"], "position",
			SEAT_POS[i] + (Vector2(0, 9) if i == _speaking else Vector2.ZERO), 0.45)
	for rec in _portraits:
		rec["node"].queue_redraw()
	for i in _name_labels.size():
		var tint2: Color = SEATS[i]["tint"]
		var a2: float = 0.28 if not _alive[i] else (1.0 if i == _speaking else 0.55)
		_name_labels[i].add_theme_color_override("font_color",
			Color(tint2.r, tint2.g, tint2.b, a2))


func _say_line(who: String, text: String) -> void:
	if _subtitle == null:
		return
	_subtitle.text = "“%s”" % text if who != "" else text
	if _sub_name != null:
		_sub_name.text = who
		var idx := -1
		for i in SEATS.size():
			if _name(i) == who:
				idx = i
		var c: Color = SEATS[idx]["tint"] if idx >= 0 else PAL["steel"]
		_sub_name.add_theme_color_override("font_color", c)
	if who != "":
		_history.append("%s: %s" % [who, text])
		if _history.size() > 6:
			_history.remove_at(0)
		_record({"kind": "line", "agent": who, "text": text})


func _flash(text: String, col: Color, hold := 2.0, size := 62) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", size)
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate", Color(1, 1, 1, 1), 0.24)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate", Color(1, 1, 1, 0), 0.45)


func _update_hud() -> void:
	if _hud_round == null:
		return
	_hud_round.text = "ROUND %d      %d AT THE TABLE      SEED %d" % [
		_round, _living().size(), _seed]


func _set_status(text: String) -> void:
	if _hud_status != null:
		_hud_status.text = text


func _tick_view(delta: float) -> void:
	if _crt_mat != null:
		_crt_mat.set_shader_parameter("t", _t)
	if _lamp != null:
		var f: float = (sin(_t * 3.1) + sin(_t * 7.7)) * 0.25 + 0.5
		_lamp.modulate = Color(1, 1, 1, 1).lerp(Color(0.92, 0.89, 0.85, 1), f)
	# The sprites animate themselves now; no fake breathing needed.
	if _props != null:
		_props.queue_redraw()
	if _stage != null:
		var jitter := Vector2.ZERO
		if _shake > 0.001:
			_shake = maxf(0.0, _shake - delta * 2.2)
			jitter = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 26.0 * _shake
		_stage.position = _stage_home + Vector2(sin(_t * 0.21) * 8.0,
			cos(_t * 0.17) * 5.0) + jitter


# ── helpers ────────────────────────────────────────────────────────────────

## Load whatever cues are present. Names are fixed; see assets/audio/README.txt.
func _load_audio() -> void:
	for cue in ["gunshot", "click", "spin", "cock", "card", "challenge",
			"death", "survivor", "roomtone", "tension"]:
		var stream: AudioStream = null
		for ext in AUDIO_EXT:
			var path := "%s/%s%s" % [AUDIO_DIR, cue, ext]
			if ResourceLoader.exists(path):
				stream = load(path)
				if stream != null:
					break
		if stream == null:
			continue
		var looping: bool = cue in ["roomtone", "tension"]
		if stream is AudioStreamOggVorbis:
			stream.loop = looping
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		elif stream is AudioStreamMP3:
			stream.loop = looping
		var pl := AudioStreamPlayer.new()
		pl.stream = stream
		pl.bus = "Master"
		if looping:
			pl.volume_db = -16.0
		add_child(pl)
		_sfx[cue] = pl
		if looping:
			pl.play()
			_bus_loops[cue] = pl
	if not _sfx.is_empty():
		print("SA_AUDIO loaded: %s" % ", ".join(_sfx.keys()))


## Fire a cue if it exists. Slight random pitch so repeats do not machine-gun.
func _sfx_play(cue: String, pitch_jitter := 0.06) -> void:
	if not _sfx.has(cue):
		return
	var pl: AudioStreamPlayer = _sfx[cue]
	pl.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	pl.play()


## Roughly where the character's head is, in stage coordinates.
## Measured from a real render: the head sits ~465 sprite-units above the seat
## anchor, before per-seat scaling. The raw frame height is useless here because
## the packs pad each frame with transparency.
const HEAD_UNITS := 465.0

func _head_of(i: int) -> Vector2:
	return SEAT_POS[i] + Vector2(0, -HEAD_UNITS * SEAT_SCALE[i])


func _actor(i: int) -> Variant:
	for a in _actors:
		if int(a["index"]) == i:
			return a
	return null


func _radial(centre: Vector2, radius: float, col: Color) -> Node2D:
	var n := Node2D.new()
	n.draw.connect(func() -> void:
		for i in range(26, 0, -1):
			var f := float(i) / 26.0
			n.draw_circle(centre, radius * f,
				Color(col.r, col.g, col.b, col.a * (1.0 - f) * 0.16))
	)
	n.queue_redraw()
	return n


func _ellipse(target: CanvasItem, centre: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 72:
		var a := TAU * float(i) / 72.0
		pts.append(centre + Vector2(cos(a) * r.x, sin(a) * r.y))
	target.draw_colored_polygon(pts, col)
