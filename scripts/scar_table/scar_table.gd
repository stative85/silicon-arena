extends Node2D

## SCAR TABLE — the visual frame.
##
## Five characters around one lit table in a dark room. Built entirely in code,
## matching this project's convention of programmatic scene construction.
##
## Phase 1 is composition and light ONLY. No LM Studio, no sockets, no memory,
## no turns. If it does not look good as a still, nothing wired into it will
## save it.
##
##   run:      Godot --path . scenes/scar_table/scar_table.tscn
##   capture:  ... -- --capture <path.png>

const ClientScript := preload("res://scripts/api/lm_studio_client.gd")
const PolicyScript := preload("res://scripts/arena/model_policy.gd")

const ROSTER_PATH := "../extinct_os/config/arena-roster.v1.json"
const TOPIC := "One of you is lying about what happened in this room. Find out who."

const W := 1920.0
const H := 1080.0

## Table centre and radii. Everything else is placed relative to these.
const TABLE_C := Vector2(960, 858)
const TABLE_R := Vector2(700, 182)

## The lamp hangs above the heads, not through them.
const LAMP := Vector2(960, 176)

## The five, in seating order left to right.
const SEATS := [
	{"name": "OZONIOUS", "tint": Color(1.0, 0.55, 0.45),
	 "sprite": "res://assets/craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Orc/PNG/PNG Sequences/Idle/0_Orc_Idle_000.png"},
	{"name": "GEMMATRON", "tint": Color(0.45, 0.85, 1.0),
	 "sprite": "res://assets/craftpix-891123-free-golems-chibi-2d-game-sprites2/Golem_1/PNG/PNG Sequences/Idle/0_Golem_Idle_000.png"},
	{"name": "SMOLLIOUS", "tint": Color(1.0, 0.78, 0.45),
	 "sprite": "res://assets/craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Goblin/PNG/PNG Sequences/Idle/0_Goblin_Idle_000.png"},
	{"name": "GROKISH", "tint": Color(0.65, 0.55, 1.0),
	 "sprite": "res://assets/craftpix-net-935193-free-chibi-necromancer-of-the-shadow-character-sprites/Necromancer_of_the_Shadow_1/PNG/PNG Sequences/Idle/0_Necromancer_of_the_Shadow_Idle_000.png"},
	{"name": "DANOHSHIT", "tint": Color(0.95, 0.42, 0.38),
	 "sprite": "res://assets/craftpix-net-140672-free-chibi-skeleton-warrior-character-sprites/Skeleton_Warrior_1/PNG/PNG Sequences/Idle/0_Skeleton_Warrior_Idle_000.png"},
]

## Seat positions on the far arc. Characters sit BEHIND the table, and the table
## is drawn over them, which is what sells "seated" from standing sprites.
const SEAT_POS := [
	Vector2(430, 846), Vector2(695, 800), Vector2(960, 780),
	Vector2(1225, 800), Vector2(1490, 846),
]
const SEAT_SCALE := [0.50, 0.465, 0.45, 0.465, 0.50]

var _capture_path := ""
var _frames := 0
var _t := 0.0
var _actors := []
var _speaking := 2   # who has focus in the still
var _stage: Node2D = null
var _bleed: ColorRect = null
var _name_labels := []
var _subtitle: Label = null
var _lamp: Node2D = null
var _stage_home := Vector2.ZERO
## Frame-sequence capture, for turning a live run into a clip.
## Live dialogue. Godot picks who speaks and when; the model only supplies the
## words. If the model is unavailable the table keeps talking from its own
## lines, clearly marked, rather than freezing.
var _client = null
var _policy = null
var _model_key := ""
var _live := false
var _waiting := false
var _wait_started := 0.0
var _personas := {}
var _history := []
var _status: Label = null

## THE GAME. Godot owns every rule and every outcome. The model only supplies
## words and a name to vote for; it never decides who dies.
enum Phase { TALK, VOTE, CHAMBER, RESULT, OVER }
var _phase: int = Phase.TALK
var _round := 1
var _talk_turns := 0
const TALK_TURNS_PER_ROUND := 6
var _alive := [true, true, true, true, true]
var _votes := {}
var _accused := -1
var _rng := RandomNumberGenerator.new()
var _chamber := 0          # which chamber holds the live round, 0..5
var _chamber_at := 0       # how many times it has been pulled
var _banner: Label = null
var _round_lbl: Label = null
var _phase_t := 0.0

var _seq_dir := ""
var _seq_i := 0
var _seq_t := 0.0
const SEQ_FPS := 12.0
const SEQ_FRAMES := 96
## Which treatment to render. Same geometry, different light and colour.
var _look := "film"


func _fit_stage() -> void:
	if _stage == null:
		return
	var vp := Vector2(get_viewport_rect().size)
	if _bleed != null:
		_bleed.size = vp
	# Frame against a SAFE RECT rather than a guessed zoom. Everything that
	# matters lives between y=60 (lamp) and y=1010 (subtitle); the camera fills
	# the window with that band and never crops it, whatever shape the window is.
	var safe_top := 60.0
	var safe_bottom := 1010.0
	var safe_h: float = safe_bottom - safe_top
	var k: float = minf(vp.x / W, vp.y / safe_h)
	if _look == "wide":
		k = minf(vp.x / W, vp.y / H)
	_stage.scale = Vector2(k, k)
	_stage.position = Vector2(
		(vp.x - W * k) * 0.5,
		(vp.y - safe_h * k) * 0.5 - safe_top * k)
	_stage_home = _stage.position


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--capture" and i + 1 < args.size():
			_capture_path = args[i + 1]
		if args[i] == "--look" and i + 1 < args.size():
			_look = args[i + 1]
		if args[i] == "--seq" and i + 1 < args.size():
			_seq_dir = args[i + 1]

	# Everything is composed at 1920x1080 and then scaled to fit the real
	# window. The first render was cropped because the project viewport is
	# 1540x720 and the layout assumed otherwise.
	# Full-bleed black behind everything, OUTSIDE the fitted stage, so an odd
	# window shape shows more darkness rather than grey bars.
	var bleed := ColorRect.new()
	bleed.color = Color(0.012, 0.009, 0.009)
	bleed.z_index = -200
	bleed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bleed)
	_bleed = bleed

	_stage = Node2D.new()
	add_child(_stage)
	_fit_stage()
	get_viewport().size_changed.connect(_fit_stage)

	print("SCAR_TABLE_ARGS %s | capture='%s' seq='%s'" % [str(args), _capture_path, _seq_dir])
	get_tree().auto_accept_quit = false

	_build_room()
	_build_chairs()
	_build_actors()
	_build_table()
	_build_props()
	_build_light()
	_build_atmosphere()
	_build_nameplates()
	_build_status()
	_build_banner()
	_rng.randomize()
	_chamber = _rng.randi_range(0, 5)
	_start_live()


## Load the roster, check the model against the 7B ceiling, and open a client.
## Every failure here is survivable: the scene still runs, it just says so.
func _start_live() -> void:
	if _capture_path != "" or _seq_dir != "":
		return   # captures stay deterministic

	var f := FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if f == null:
		_set_status("roster not found - running scripted lines")
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_set_status("roster unreadable - running scripted lines")
		return

	for a in parsed.get("agents", []):
		_personas[str(a.get("display_name", ""))] = str(a.get("persona", ""))
	var runtimes: Array = parsed.get("runtimes", [])
	if runtimes.is_empty():
		_set_status("no runtime in roster - running scripted lines")
		return
	_model_key = str(runtimes[0].get("model_key", ""))

	_policy = PolicyScript.new()
	add_child(_policy)
	if not _policy.load_catalog():
		_set_status("model catalog unavailable - running scripted lines")
		return
	# THE GUARD, on the request path. Nothing above 7B is ever requested.
	var reason: String = _policy.check(_model_key)
	if reason != "":
		_set_status("model refused: %s" % reason)
		return

	_client = ClientScript.new()
	_client.model_policy = _policy
	add_child(_client)
	_live = true
	_set_status("LIVE  %s" % _model_key)
	# First line after a beat, so the room is on screen before anyone talks.
	_turn_t = TURN_SECS - 0.8


func _build_status() -> void:
	var l := Label.new()
	l.z_index = 70
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.42, 0.46, 0.44, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.position = Vector2(30, 78)
	l.size = Vector2(700, 22)
	_stage.add_child(l)
	_status = l
	_set_status("starting...")


func _build_banner() -> void:
	var b := Label.new()
	b.z_index = 80
	b.add_theme_font_size_override("font_size", 54)
	b.add_theme_color_override("font_color", Color(0.95, 0.90, 0.82))
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	b.position = Vector2(160, 300)
	b.size = Vector2(1600, 70)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.modulate = Color(1, 1, 1, 0)
	_stage.add_child(b)
	_banner = b

	var r := Label.new()
	r.z_index = 70
	r.add_theme_font_size_override("font_size", 19)
	r.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55, 0.9))
	r.add_theme_constant_override("outline_size", 5)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	r.position = Vector2(30, 104)
	r.size = Vector2(500, 24)
	_stage.add_child(r)
	_round_lbl = r
	_update_round_label()


func _update_round_label() -> void:
	var n := 0
	for a in _alive:
		if a:
			n += 1
	_round_lbl.text = "ROUND %d      %d STILL AT THE TABLE" % [_round, n]


func _flash(text: String, col: Color, hold := 2.2) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate", Color(1, 1, 1, 1), 0.28)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate", Color(1, 1, 1, 0), 0.5)


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# ── the room ────────────────────────────────────────────────────────────────

func _build_room() -> void:
	# Darkness everything else is carved out of.
	var bg := ColorRect.new()
	bg.color = Color(0.016, 0.012, 0.012)
	bg.size = Vector2(W, H)
	bg.z_index = -100
	_stage.add_child(bg)

	# Back wall: a faint warm bloom behind the table so the silhouettes have
	# something to separate against instead of dying into pure black.
	var wall_col := Color(0.20, 0.10, 0.07, 0.55)
	if _look == "cold":
		wall_col = Color(0.07, 0.12, 0.15, 0.55)
	elif _look == "dark" or _look == "film":
		wall_col = Color(0.12, 0.06, 0.045, 0.34)
	var wall := _radial(Vector2(960, 520), 980.0, wall_col)
	wall.z_index = -95
	_stage.add_child(wall)

	# Floor: slightly warmer than the wall, and only near the table.
	var floor_glow := _radial(Vector2(960, 940), 820.0, Color(0.12, 0.07, 0.05, 0.6))
	floor_glow.z_index = -94
	_stage.add_child(floor_glow)


func _build_chairs() -> void:
	var chairs := Node2D.new()
	chairs.z_index = -60
	chairs.draw.connect(func() -> void:
		for i in SEAT_POS.size():
			var p: Vector2 = SEAT_POS[i]
			var s: float = SEAT_SCALE[i]
			var w := 150.0 * s
			var h := 250.0 * s
			# Chair back, just a shape darker than the wall.
			chairs.draw_rect(Rect2(p.x - w * 0.5, p.y - h, w, h),
				Color(0.045, 0.032, 0.030), true)
			chairs.draw_rect(Rect2(p.x - w * 0.5, p.y - h, w, h),
				Color(0.10, 0.07, 0.06), false, 2.0)
			# Two uprights, so it reads as a chair and not a slab.
			for dx in [-1.0, 1.0]:
				chairs.draw_rect(Rect2(p.x + dx * w * 0.5 - 4, p.y - h, 8, h + 40),
					Color(0.06, 0.042, 0.038), true)
	)
	_stage.add_child(chairs)
	chairs.queue_redraw()


func _build_actors() -> void:
	for i in SEATS.size():
		var seat: Dictionary = SEATS[i]
		var tex: Texture2D = load(seat["sprite"])
		if tex == null:
			push_warning("[scar_table] missing sprite: %s" % seat["sprite"])
			continue

		var holder := Node2D.new()
		holder.position = SEAT_POS[i]
		holder.z_index = -50 + i
		_stage.add_child(holder)

		# Rim light: a tinted copy behind the sprite, offset and blurred by
		# scale. Cheap, and it does the separating work that real rim lighting
		# would do. Each identity gets its own colour.
		var rim := Sprite2D.new()
		rim.texture = tex
		rim.centered = false
		rim.scale = Vector2.ONE * SEAT_SCALE[i] * 1.045
		rim.position = Vector2(-tex.get_width() * rim.scale.x * 0.5,
			-tex.get_height() * rim.scale.y)
		var rim_a: float = 0.75 if i == _speaking else 0.34
		rim.modulate = Color(seat["tint"].r, seat["tint"].g, seat["tint"].b, rim_a)
		rim.z_index = -1
		holder.add_child(rim)

		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2.ONE * SEAT_SCALE[i]
		spr.position = Vector2(-tex.get_width() * spr.scale.x * 0.5,
			-tex.get_height() * spr.scale.y)
		# Everyone sits in shadow except whoever is speaking.
		var lit: float = 1.0 if i == _speaking else 0.40
		if _look == "dark" or _look == "film":
			lit = 1.0 if i == _speaking else 0.26
		elif _look == "cold":
			lit = 1.0 if i == _speaking else 0.46
		spr.modulate = Color(lit, lit * 0.94, lit * 0.88)
		holder.add_child(spr)

		_actors.append({"holder": holder, "sprite": spr, "rim": rim,
			"seat": seat, "index": i, "phase": randf() * TAU})


func _build_table() -> void:
	# Drawn AFTER the actors so it occludes their legs. That single ordering
	# decision is what turns standing sprites into seated characters.
	var table := Node2D.new()
	table.z_index = 10
	table.draw.connect(func() -> void:
		# Drop shadow under the table.
		table.draw_set_transform(TABLE_C + Vector2(0, 26), 0.0, Vector2(1, 1))
		_ellipse(table, Vector2.ZERO, TABLE_R * 1.04, Color(0, 0, 0, 0.75))
		table.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Table edge / thickness.
		_ellipse(table, TABLE_C + Vector2(0, 20), TABLE_R, Color(0.035, 0.024, 0.020))
		# Top surface: nearly black at the edges.
		_ellipse(table, TABLE_C, TABLE_R, Color(0.055, 0.036, 0.028))
		# The pool of light, tight and warm, falling off fast.
		_ellipse(table, TABLE_C + Vector2(0, -10), TABLE_R * 0.80,
			Color(0.13, 0.082, 0.052, 0.85))
		_ellipse(table, TABLE_C + Vector2(0, -16), TABLE_R * 0.56,
			Color(0.24, 0.145, 0.082, 0.80))
		var pool := Color(0.38, 0.23, 0.12, 0.70)
		if _look == "cold":
			pool = Color(0.20, 0.30, 0.38, 0.70)
		elif _look == "dark" or _look == "film":
			pool = Color(0.32, 0.19, 0.095, 0.62)
		_ellipse(table, TABLE_C + Vector2(0, -22), TABLE_R * 0.32, pool)
		# Rim highlight along the far edge, where the lamp catches it.
		for k in 40:
			var a: float = PI + PI * (float(k) / 39.0)
			var p := TABLE_C + Vector2(cos(a) * TABLE_R.x, sin(a) * TABLE_R.y)
			table.draw_circle(p, 2.2, Color(0.62, 0.40, 0.22, 0.5))
	)
	_stage.add_child(table)
	table.queue_redraw()


func _build_props() -> void:
	var props := Node2D.new()
	props.z_index = 12
	props.draw.connect(func() -> void:
		# Cards in front of each seat: a token per player, worn and off-white.
		for i in SEAT_POS.size():
			var p: Vector2 = SEAT_POS[i]
			var cx: float = lerpf(p.x, TABLE_C.x, 0.10)
			var cy: float = TABLE_C.y - 68 + absf(float(i) - 2.0) * 26.0
			for c in 2:
				var r := Rect2(cx - 26 + c * 16, cy - 20 + c * 4, 30, 42)
				props.draw_rect(r, Color(0.72, 0.66, 0.55, 0.92), true)
				props.draw_rect(r, Color(0.15, 0.11, 0.09), false, 1.5)

		# The centre prop: one revolver, laid across the middle of the table.
		# The centre prop, big enough to read at a glance and angled across the
		# table so it points at nobody in particular.
		var g := TABLE_C + Vector2(0, -6)
		var steel := Color(0.20, 0.20, 0.23)
		var steel_hi := Color(0.58, 0.57, 0.62)

		# soft shadow so it sits ON the table instead of floating
		props.draw_set_transform(g + Vector2(6, 12), -0.20, Vector2.ONE)
		props.draw_rect(Rect2(-150, -14, 250, 30), Color(0, 0, 0, 0.5), true)

		props.draw_set_transform(g, -0.20, Vector2.ONE)
		# barrel
		props.draw_rect(Rect2(-150, -13, 230, 26), steel, true)
		props.draw_rect(Rect2(-150, -13, 230, 8), Color(0.34, 0.34, 0.38), true)
		props.draw_rect(Rect2(-150, -13, 230, 26), steel_hi, false, 2.0)
		# muzzle
		props.draw_circle(Vector2(-150, 0), 12, Color(0.06, 0.06, 0.07))
		# cylinder
		props.draw_circle(Vector2(6, 0), 36, Color(0.26, 0.26, 0.29))
		props.draw_circle(Vector2(6, 0), 36, steel_hi)
		props.draw_circle(Vector2(6, 0), 28, Color(0.13, 0.13, 0.15))
		# chambers: five empty, one live
		for c in 6:
			var a: float = TAU * float(c) / 6.0 - PI * 0.5
			var cp := Vector2(6, 0) + Vector2(cos(a), sin(a)) * 17.0
			if c == 0:
				props.draw_circle(cp, 7.0, Color(0.95, 0.72, 0.28))
				props.draw_circle(cp, 7.0, Color(1.0, 0.88, 0.55))
			else:
				props.draw_circle(cp, 6.0, Color(0.05, 0.05, 0.06))
		# hammer
		props.draw_rect(Rect2(38, -30, 20, 22), steel, true)
		props.draw_rect(Rect2(38, -30, 20, 22), steel_hi, false, 1.5)
		# grip, drawn inside the barrel's transform so it stays welded to the
		# frame instead of floating off as a separate plank
		var grip := PackedVector2Array([
			Vector2(30, 6), Vector2(64, 2), Vector2(96, 86),
			Vector2(58, 96), Vector2(34, 40),
		])
		props.draw_colored_polygon(grip, Color(0.23, 0.13, 0.09))
		props.draw_polyline(grip + PackedVector2Array([grip[0]]),
			Color(0.48, 0.30, 0.19), 2.0)
		props.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	)
	_stage.add_child(props)
	props.queue_redraw()


func _build_light() -> void:
	# The one practical: a bare bulb over the table on a wire.
	var lamp := Node2D.new()
	lamp.z_index = 40
	lamp.draw.connect(func() -> void:
		lamp.draw_line(Vector2(LAMP.x, -10), LAMP + Vector2(0, -18),
			Color(0.16, 0.13, 0.11), 3.0)
		var bulb := Color(1.0, 0.88, 0.66)
		if _look == "cold":
			bulb = Color(0.80, 0.93, 1.0)
		lamp.draw_circle(LAMP, 15, bulb)
		var halo := Color(1.0, 0.74, 0.38, 1.0)
		if _look == "cold":
			halo = Color(0.62, 0.84, 1.0, 1.0)
		lamp.draw_circle(LAMP, 27, Color(halo.r, halo.g, halo.b, 0.32))
		lamp.draw_circle(LAMP, 58, Color(halo.r, halo.g, halo.b, 0.14))
		lamp.draw_circle(LAMP, 120, Color(halo.r, halo.g, halo.b, 0.05))
	)
	_stage.add_child(lamp)
	lamp.queue_redraw()
	_lamp = lamp

	# The cone it throws.
	var cone := Node2D.new()
	cone.z_index = 39
	cone.draw.connect(func() -> void:
		var pts := PackedVector2Array([
			LAMP + Vector2(-22, 14), LAMP + Vector2(22, 14),
			Vector2(1680, 1010), Vector2(240, 1010),
		])
		var cone_col := Color(1.0, 0.66, 0.30, 0.05)
		if _look == "cold":
			cone_col = Color(0.58, 0.82, 1.0, 0.05)
		elif _look == "dark" or _look == "film":
			cone_col = Color(1.0, 0.66, 0.30, 0.034)
		cone.draw_colored_polygon(pts, cone_col)
		var pts2 := PackedVector2Array([
			LAMP + Vector2(-14, 14), LAMP + Vector2(14, 14),
			Vector2(1380, 980), Vector2(540, 980),
		])
		cone.draw_colored_polygon(pts2, Color(cone_col.r, cone_col.g, cone_col.b,
			cone_col.a * 0.9))
	)
	_stage.add_child(cone)
	cone.queue_redraw()


func _build_atmosphere() -> void:
	# Dust in the light cone. Slow, sparse, barely there.
	var dust := CPUParticles2D.new()
	dust.position = Vector2(960, 520)
	dust.amount = 90
	dust.lifetime = 9.0
	dust.preprocess = 6.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(430, 300)
	dust.direction = Vector2(0, 1)
	dust.spread = 24.0
	dust.gravity = Vector2(2, 5)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 9.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 2.0
	dust.color = Color(1.0, 0.82, 0.55, 0.16)
	dust.z_index = 45
	_stage.add_child(dust)

	# Vignette.
	var vig := ColorRect.new()
	vig.size = Vector2(W, H)
	vig.z_index = 90
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p * vec2(1.25, 1.0));
	float v = smoothstep(0.34, 0.92, d);
	COLOR = vec4(0.0, 0.0, 0.0, v * 0.92);
}
"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vig.material = vm
	_stage.add_child(vig)

	# Grain. Subtle enough that you notice it only when it is gone.
	var grain := ColorRect.new()
	grain.size = Vector2(W, H)
	grain.z_index = 92
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := Shader.new()
	gs.code = """
shader_type canvas_item;
uniform float t = 0.0;
float n(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float g = n(UV * vec2(1920.0, 1080.0) + vec2(t * 37.0, t * 91.0));
	COLOR = vec4(vec3(g), 0.055);
}
"""
	var gm := ShaderMaterial.new()
	gm.shader = gs
	grain.material = gm
	_stage.add_child(grain)
	_grain_mat = gm


var _grain_mat: ShaderMaterial = null


func _build_nameplates() -> void:
	# Small, diegetic-ish. A name under each seat, brighter for the speaker.
	for i in SEATS.size():
		var seat: Dictionary = SEATS[i]
		var lbl := Label.new()
		lbl.text = str(seat["name"])
		lbl.z_index = 60
		lbl.add_theme_font_size_override("font_size", 21 if i == _speaking else 18)
		var c: Color = seat["tint"]
		var a: float = 1.0 if i == _speaking else 0.62
		lbl.add_theme_color_override("font_color", Color(c.r, c.g, c.b, a))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		var nx: float = lerpf(SEAT_POS[i].x, TABLE_C.x, 0.10)
		var ny: float = TABLE_C.y - 108 + absf(float(i) - 2.0) * 26.0
		lbl.position = Vector2(nx - 70, ny)
		lbl.size = Vector2(140, 24)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stage.add_child(lbl)
		_name_labels.append(lbl)

	# One subtitle line for the speaker. Not a chat panel — one line, centred.
	var sub := Label.new()
	sub.text = "“Somebody at this table is lying, and it isn’t me.”"
	sub.z_index = 61
	sub.add_theme_font_size_override("font_size", 27)
	sub.add_theme_color_override("font_color", Color(0.93, 0.88, 0.78))
	sub.add_theme_constant_override("outline_size", 7)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	sub.position = Vector2(260, 966)
	sub.size = Vector2(1400, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(sub)
	_subtitle = sub


# ── helpers ─────────────────────────────────────────────────────────────────

func _radial(centre: Vector2, radius: float, col: Color) -> Node2D:
	var n := Node2D.new()
	n.draw.connect(func() -> void:
		var steps := 26
		for i in range(steps, 0, -1):
			var f := float(i) / float(steps)
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


## Cycle the speaker so the room reads as a conversation, not a photograph.
## Deterministic rehearsal only — no model is talking yet.
const LINES := [
	"Somebody at this table is lying, and it isn’t me.",
	"You have been quiet a long time, GROKISH.",
	"I watched you take it. I did not say anything then.",
	"Say that again and look at me while you do it.",
	"Three of us know. Two of us are pretending not to.",
]
var _turn_t := 0.0
const TURN_SECS := 3.2


func _advance_speaker() -> void:
	for _k in SEATS.size():
		_speaking = (_speaking + 1) % SEATS.size()
		if _alive[_speaking]:
			break
	_light_speaker()
	if _live and not _waiting:
		_request_line()


## Move the light. Used by talking, voting and the chamber alike.
func _light_speaker() -> void:
	for a in _actors:
		var i: int = a["index"]
		if not _alive[i]:
			continue
		var lit: float = 1.0 if i == _speaking else 0.26
		var spr: Sprite2D = a["sprite"]
		var rim: Sprite2D = a["rim"]
		var seat: Dictionary = a["seat"]
		create_tween().tween_property(spr, "modulate",
			Color(lit, lit * 0.94, lit * 0.88), 0.45)
		var ra: float = 0.75 if i == _speaking else 0.30
		create_tween().tween_property(rim, "modulate",
			Color(seat["tint"].r, seat["tint"].g, seat["tint"].b, ra), 0.45)
		if i == _speaking:
			# a small lean-in on the speaker
			create_tween().tween_property(a["holder"], "position",
				SEAT_POS[i] + Vector2(0, 8), 0.5)
		else:
			create_tween().tween_property(a["holder"], "position", SEAT_POS[i], 0.5)
	if _name_labels.size() == SEATS.size():
		for i in SEATS.size():
			var c: Color = SEATS[i]["tint"]
			var a2: float = 1.0 if i == _speaking else 0.55
			_name_labels[i].add_theme_color_override("font_color",
				Color(c.r, c.g, c.b, a2))
			_name_labels[i].add_theme_font_size_override("font_size",
				21 if i == _speaking else 18)
	if _subtitle != null:
		_subtitle.text = "“%s”" % LINES[_speaking]


# ── vote ───────────────────────────────────────────────────────────────────

func _begin_vote() -> void:
	_phase = Phase.VOTE
	_phase_t = 0.0
	_turn_t = 0.0
	_votes.clear()
	_flash("WHO IS LYING?", Color(0.95, 0.82, 0.45), 1.4)
	if _subtitle != null:
		_subtitle.text = "The table votes."


## Each living agent votes. Godot tallies; nobody is told the result early.
func _cast_next_vote() -> void:
	for i in SEATS.size():
		if _alive[i] and not _votes.has(i):
			var target := _pick_vote_target(i)
			_votes[i] = target
			_speaking = i
			_light_speaker()
			if _subtitle != null:
				_subtitle.text = "%s votes for %s." % [
					str(SEATS[i]["name"]), str(SEATS[target]["name"])]
			return
	_tally()


## Who i votes for. Weighted by who has been talking at them, with bounded
## noise so it is never a fixed answer. The MODEL does not decide this — the
## engine does, from the room's state, exactly like the systemic ruleset.
func _pick_vote_target(i: int) -> int:
	var best := -1
	var best_score := -INF
	for j in SEATS.size():
		if j == i or not _alive[j]:
			continue
		var score := _rng.randf() * 0.6
		# Anyone who named you recently earns suspicion.
		for h in _history:
			if h.begins_with(str(SEATS[j]["name"]) + ":") 					and h.to_upper().contains(str(SEATS[i]["name"]).to_upper()):
				score += 0.5
		if score > best_score:
			best_score = score
			best = j
	return best if best >= 0 else i


func _tally() -> void:
	var counts := {}
	for v in _votes.values():
		counts[v] = int(counts.get(v, 0)) + 1
	var top := -1
	var top_n := -1
	for k in counts:
		if int(counts[k]) > top_n:
			top_n = int(counts[k])
			top = int(k)
	_accused = top
	_phase = Phase.CHAMBER
	_phase_t = 0.0
	_speaking = _accused
	_light_speaker()
	_flash("%s IS CHOSEN" % str(SEATS[_accused]["name"]),
		Color(0.95, 0.45, 0.35), 1.6)
	if _subtitle != null:
		_subtitle.text = "%d of %d point at %s." % [
			top_n, _votes.size(), str(SEATS[_accused]["name"])]


# ── the chamber ────────────────────────────────────────────────────────────

## One cylinder, one live round, six chambers. Godot resolves it. The result is
## decided by the seeded rng and nothing else.
func _pull_trigger() -> void:
	_phase = Phase.RESULT
	_phase_t = 0.0
	var live: bool = (_chamber_at == _chamber)
	_chamber_at = (_chamber_at + 1) % 6
	if live:
		_alive[_accused] = false
		_flash("%s IS OUT" % str(SEATS[_accused]["name"]),
			Color(1.0, 0.30, 0.22), 2.4)
		if _subtitle != null:
			_subtitle.text = "The chamber was loaded."
		var a: Variant = _actor_for(_accused)
		if a != null:
			create_tween().tween_property(a["sprite"], "modulate",
				Color(0.10, 0.09, 0.09, 0.55), 0.8)
			create_tween().tween_property(a["rim"], "modulate",
				Color(0.4, 0.1, 0.1, 0.12), 0.8)
		# reload for the next round
		_chamber = _rng.randi_range(0, 5)
		_chamber_at = 0
	else:
		_flash("EMPTY", Color(0.60, 0.72, 0.52), 1.8)
		if _subtitle != null:
			_subtitle.text = "%s breathes out." % str(SEATS[_accused]["name"])
	_update_round_label()


func _actor_for(i: int) -> Variant:
	for a in _actors:
		if int(a["index"]) == i:
			return a
	return null


func _next_round() -> void:
	var n := 0
	var last := -1
	for i in _alive.size():
		if _alive[i]:
			n += 1
			last = i
	if n <= 1:
		_phase = Phase.OVER
		_flash("%s IS THE LAST ONE SITTING" % str(SEATS[last]["name"]),
			Color(0.95, 0.88, 0.62), 9.0)
		if _subtitle != null:
			_subtitle.text = "Restart to run it again."
		return
	_round += 1
	_talk_turns = 0
	_phase = Phase.TALK
	_phase_t = 0.0
	_turn_t = 0.0
	_history.clear()
	_update_round_label()
	_flash("ROUND %d" % _round, Color(0.85, 0.80, 0.70), 1.2)


## One short line, in character, aware of what was just said. Godot decides who
## speaks; the model only fills in the words.
func _request_line() -> void:
	var name := str(SEATS[_speaking]["name"])
	var persona: String = str(_personas.get(name, "an AI at this table"))
	var others := []
	for i in SEATS.size():
		if i != _speaking:
			others.append(str(SEATS[i]["name"]))

	var prompt := "You are %s, sitting at a table with %s.\n" % [name, ", ".join(others)]
	prompt += "Your character: %s\n" % persona.substr(0, 420)
	prompt += "SITUATION: %s\n" % TOPIC
	if not _history.is_empty():
		prompt += "Just said:\n"
		for h in _history.slice(maxi(0, _history.size() - 3), _history.size()):
			prompt += "  %s\n" % h
	prompt += "
Say ONE short line out loud, in character. Under 18 words.
"
	# Anti-parrot. Small models fed a transcript continue the last speaker almost
	# verbatim; the first live run repeated one sentence five times running.
	prompt += "RULES:
"
	prompt += "- Do NOT repeat, quote or paraphrase any line above. Say something NEW.
"
	prompt += "- Name one other agent and say something TO them.
"
	prompt += "- Accuse, deny, bargain or threaten. Take a position.
"
	prompt += "- Output ONLY the spoken words. No name prefix, no name suffix, "
	prompt += "no quotes, no dashes, no stage directions."

	_waiting = true
	_wait_started = _t
	# danube3 rejects a system role, so the whole briefing rides the user turn.
	_client.chat_completion(name, _model_key,
		[{"role": "user", "content": prompt}],
		func(ok: bool, reply: String, code: int):
			_waiting = false
			if not ok:
				_set_status("model error %d - scripted line used" % code)
				return
			var line := _clean(reply)
			if line == "":
				return
			# Drop verbatim echoes rather than showing one sentence twice.
			var echoed := false
			for h in _history:
				var prev: String = h.substr(h.find(":") + 1).strip_edges()
				if prev.length() > 18 and line.contains(prev.substr(0, 18)):
					echoed = true
			if echoed:
				_set_status("echo dropped  %s" % _model_key)
				return
			print("SCAR_TABLE %s: %s" % [name, line])
			_history.append("%s: %s" % [name, line])
			if _history.size() > 8:
				_history.remove_at(0)
			if _subtitle != null:
				_subtitle.text = "\u201c%s\u201d" % line
			_set_status("LIVE  %s" % _model_key),
		{"temperature": 0.85, "max_tokens": 60, "top_p": 0.92})


## Small models leak. Strip the usual wrappers rather than showing them.
func _clean(text: String) -> String:
	var t := text.strip_edges()
	t = t.replace("\n", " ").replace("\r", " ")
	for junk in ["\"", "\u201c", "\u201d", "*"]:
		t = t.replace(junk, "")
	# Strip ANY "Something:" speaker prefix, not just the five real names — the
	# model invents labels like "Tribunal Engine:" and "Grokiwraith:".
	var colon := t.find(":")
	if colon > 0 and colon <= 24:
		t = t.substr(colon + 1).strip_edges()
	# Strip trailing " - NAME" attributions.
	var at := t.rfind(" - ")
	if at > 0 and t.length() - at < 26:
		t = t.substr(0, at).strip_edges()
	# The model keeps writing everyone else's turn too. Cut at the first point
	# where it hands off to another speaker.
	for i in SEATS.size():
		var n := str(SEATS[i]["name"])
		var at2 := t.to_upper().find(n.to_upper() + ":")
		if at2 > 0:
			t = t.substr(0, at2).strip_edges()
	# One sentence is a line of dialogue. Two is a monologue.
	if t.length() > 110:
		var cut := -1
		for mark in [". ", "? ", "! "]:
			var m := t.find(mark)
			if m > 24 and (cut < 0 or m < cut):
				cut = m + 1
		t = t.substr(0, cut).strip_edges() if cut > 0 else t.substr(0, 104).strip_edges()
	return t.strip_edges()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("SCAR_TABLE_QUIT window close requested")
		get_tree().quit()
	elif what == NOTIFICATION_CRASH:
		print("SCAR_TABLE_QUIT crash notification")


func _process(delta: float) -> void:
	_t += delta

	# Never let a stalled request freeze the room.
	if _waiting and _t - _wait_started > 25.0:
		_waiting = false
		_set_status("model timed out - scripted line used")

	if _capture_path == "" or _seq_dir != "":
		_turn_t += delta
		_phase_t += delta
		match _phase:
			Phase.TALK:
				if _turn_t >= TURN_SECS:
					_turn_t = 0.0
					_advance_speaker()
					_talk_turns += 1
					if _talk_turns >= TALK_TURNS_PER_ROUND:
						_begin_vote()
			Phase.VOTE:
				if _turn_t >= 1.4:
					_turn_t = 0.0
					_cast_next_vote()
			Phase.CHAMBER:
				if _phase_t >= 3.0:
					_pull_trigger()
			Phase.RESULT:
				if _phase_t >= 4.0:
					_next_round()
			Phase.OVER:
				pass

	# The bulb is a real bulb: it is never perfectly steady.
	if _lamp != null:
		_lamp.modulate = Color(1, 1, 1, 1).lerp(
			Color(0.93, 0.90, 0.86, 1), (sin(_t * 3.1) + sin(_t * 7.7)) * 0.25 + 0.5)

	# Slow camera drift so a still frame never feels locked off.
	if _stage != null and (_capture_path == "" or _seq_dir != ""):
		_stage.position = _stage_home + Vector2(sin(_t * 0.21) * 9.0,
			cos(_t * 0.17) * 6.0)
	if _grain_mat != null:
		_grain_mat.set_shader_parameter("t", _t)

	# Breathing. Tiny, offset per actor, so the room is never dead still.
	for a in _actors:
		var s: Sprite2D = a["sprite"]
		var base: float = SEAT_SCALE[a["index"]]
		var b: float = 1.0 + sin(_t * 1.5 + a["phase"]) * 0.006
		s.scale = Vector2(base, base * b)

	if _seq_dir != "":
		_seq_t += delta
		if _seq_t >= 1.0 / SEQ_FPS:
			_seq_t = 0.0
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			im.save_png("%s/f%03d.png" % [_seq_dir, _seq_i])
			_seq_i += 1
			if _seq_i >= SEQ_FRAMES:
				print("SCAR_TABLE_SEQ %d frames" % _seq_i)
				get_tree().quit()
		return

	if _capture_path != "":
		_frames += 1
		if _frames == 14:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(_capture_path)
			print("SCAR_TABLE_CAPTURE %s" % _capture_path)
			get_tree().quit()
