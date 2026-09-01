extends Node3D

## SCAR SIX ARENA — the 3D room.
##
## Build order A: ONE complete elimination sequence, shot properly. No match
## loop here yet, no models. This exists to make a single gunshot feel like
## something before any of it is repeated five times.
##
## PS1/PS2 lane on purpose: chunky geometry, low internal resolution, unfiltered
## textures, hard shadow from one practical light, restrained particles. The
## characters are camera-facing billboards, which is what that era actually did
## and what keeps five silhouettes readable at a glance.
##
## GPU law: the room must stay cheap enough that a 7B model owns the VRAM.
##
##   --seq DIR      write beat frames
##   --hold         loop the sequence instead of quitting
##   --perf         performance mode: no post, minimal particles

const SEATS := [
	{"name": "OZONIOUS", "tint": Color(1.00, 0.45, 0.32),
	 "dir": "res://assets/craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Orc/PNG/PNG Sequences",
	 "prefix": "0_Orc"},
	{"name": "GEMMATRON", "tint": Color(0.35, 0.82, 1.00),
	 "dir": "res://assets/craftpix-891123-free-golems-chibi-2d-game-sprites2/Golem_1/PNG/PNG Sequences",
	 "prefix": "0_Golem"},
	{"name": "SMOLLIOUS", "tint": Color(1.00, 0.74, 0.30),
	 "dir": "res://assets/craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Goblin/PNG/PNG Sequences",
	 "prefix": "0_Goblin"},
	{"name": "GROKISH", "tint": Color(0.62, 0.48, 1.00),
	 "dir": "res://assets/craftpix-net-935193-free-chibi-necromancer-of-the-shadow-character-sprites/Necromancer_of_the_Shadow_1/PNG/PNG Sequences",
	 "prefix": "0_Necromancer_of_the_Shadow"},
	{"name": "DANOHSHIT", "tint": Color(0.95, 0.30, 0.26),
	 "dir": "res://assets/craftpix-net-140672-free-chibi-skeleton-warrior-character-sprites/Skeleton_Warrior_1/PNG/PNG Sequences",
	 "prefix": "0_Skeleton_Warrior"},
]

const GUN_TEX := "res://assets/props/revolver_side.png"

const TABLE_R := 1.55
const SEAT_R := 2.05
const SEAT_Y := 0.0

## The victim for this sequence. Seat 3 sits camera-right of centre, which reads
## best in the profile shot.
const VICTIM := 3

enum Beat { SETTLE, ANTICIPATION, PICKUP, SPIN, RAISE, HOLD, TRIGGER, IMPACT,
	COLLAPSE, REACTION, DONE }

const BEAT_TIME := {
	Beat.SETTLE: 2.2,
	Beat.ANTICIPATION: 2.6,
	Beat.PICKUP: 1.8,
	Beat.SPIN: 2.0,
	Beat.RAISE: 1.6,
	Beat.HOLD: 2.4,
	Beat.TRIGGER: 0.9,
	Beat.IMPACT: 1.1,
	Beat.COLLAPSE: 2.2,
	Beat.REACTION: 3.4,
}

var _beat: int = Beat.SETTLE
var _bt := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()

var _cam: Camera3D = null
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_k := 0.0
var _cam_dur := 1.0
var _shake := 0.0

var _agents := []
var _gun: Node3D = null
var _gun_sprite: Sprite3D = null
var _muzzle: OmniLight3D = null
var _flash_quad: Sprite3D = null
var _bulb: OmniLight3D = null
var _blood_decal: Decal = null
var _blood_parts: GPUParticles3D = null
var _smoke: GPUParticles3D = null

var _seq_dir := ""
var _seq_i := 0
var _shot_queue := []
var _shooting := false
var _hold := false
var _perf := false

var _sub: Label = null
var _sub_name: Label = null
var _banner: Label = null
var _hud: Control = null
var _plates := []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seq" and i + 1 < args.size(): _seq_dir = args[i + 1]
		if args[i] == "--hold": _hold = true
		if args[i] == "--perf": _perf = true
	_rng.seed = 606

	_build_env()
	_build_room()
	_build_table()
	_build_agents()
	_build_gun()
	_build_fx()
	_build_hud()
	_cut_to(_shot_master(), 0.0)
	_say(SEATS[VICTIM]["name"], "One of six. Somebody count for me.")


# ── environment ─────────────────────────────────────────────────────────────

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.010, 0.010)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.10, 0.09)
	env.ambient_light_energy = 0.22
	if not _perf:
		env.fog_enabled = true
		env.fog_light_color = Color(0.20, 0.11, 0.08)
		env.fog_density = 0.030
		env.glow_enabled = true
		env.glow_intensity = 0.55
		env.glow_bloom = 0.10
		env.glow_hdr_threshold = 0.95
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.adjustment_enabled = true
		env.adjustment_saturation = 0.86
		env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


const TEX_DIR := "res://assets/generated"

## Materials built from the procedurally generated maps. No asset pack, no
## downloads: layered noise written to PNG by tools/gen_textures.py. Untextured
## boxes are what made the first pass look like a tech demo.
func _tex_mat(name: String, col: Color, uv := 2.0, rough_map := true,
		rough := 0.92) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var alb := "%s/%s_albedo.png" % [TEX_DIR, name]
	if ResourceLoader.exists(alb):
		m.albedo_texture = load(alb)
	m.albedo_color = col
	var rp := "%s/%s_rough.png" % [TEX_DIR, name]
	if rough_map and ResourceLoader.exists(rp):
		m.roughness_texture = load(rp)
	m.roughness = rough
	m.metallic = 0.0
	m.uv1_scale = Vector3(uv, uv, uv)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _mat(col: Color, rough := 0.94, metal := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Chunky, not glossy. No filtering anywhere in this project.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _box(size: Vector3, pos: Vector3, col: Color, rough := 0.95) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(col, rough)
	add_child(mi)
	return mi


func _build_room() -> void:
	var wall := Color(0.085, 0.070, 0.066)
	var floor_col := Color(0.055, 0.045, 0.042)
	# A small hard room, now with real surfaces on it.
	_box(Vector3(9.0, 0.3, 9.0), Vector3(0, -0.15, 0), floor_col, 0.98) 		.material_override = _tex_mat("floor", Color(1, 1, 1), 3.0)
	_box(Vector3(9.0, 0.3, 9.0), Vector3(0, 3.6, 0), Color(1, 1, 1)) 		.material_override = _tex_mat("ceiling", Color(1, 1, 1), 2.5, false)
	for spec in [[Vector3(9.0, 4.0, 0.3), Vector3(0, 1.8, -4.4)],
			[Vector3(0.3, 4.0, 9.0), Vector3(-4.4, 1.8, 0)],
			[Vector3(0.3, 4.0, 9.0), Vector3(4.4, 1.8, 0)],
			[Vector3(9.0, 4.0, 0.3), Vector3(0, 1.8, 4.4)]]:
		_box(spec[0], spec[1], wall).material_override = 			_tex_mat("wall", Color(1, 1, 1), 1.6)

	# Panel seams on the back wall: cheap, and they give the shadows something
	# to break across so the room does not read as a flat void.
	for i in 7:
		var x := -3.6 + float(i) * 1.2
		_box(Vector3(0.10, 3.4, 0.10), Vector3(x, 1.7, -4.22), Color(0.055, 0.045, 0.042))
	for j in 3:
		_box(Vector3(8.4, 0.09, 0.09), Vector3(0, 0.55 + float(j) * 1.15, -4.22),
			Color(0.050, 0.041, 0.039))

	# A vent and a hanging cable, so the silhouette of the room is not symmetric.
	_box(Vector3(1.1, 0.7, 0.12), Vector3(-2.9, 2.75, -4.22), Color(0.04, 0.034, 0.032))
	_box(Vector3(0.06, 1.5, 0.06), Vector3(3.3, 2.85, -4.1), Color(0.035, 0.030, 0.028))


func _build_table() -> void:
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = TABLE_R
	cm.bottom_radius = TABLE_R
	cm.height = 0.14
	cm.radial_segments = 14          # deliberately faceted
	top.mesh = cm
	top.position = Vector3(0, 0.92, 0)
	top.material_override = _tex_mat("table", Color(1, 1, 1), 2.2, true, 0.62)
	add_child(top)

	var col := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = 0.26
	cm2.bottom_radius = 0.42
	cm2.height = 0.92
	cm2.radial_segments = 10
	col.mesh = cm2
	col.position = Vector3(0, 0.46, 0)
	col.material_override = _mat(Color(0.06, 0.048, 0.044))
	add_child(col)

	for i in SEATS.size():
		var a := _seat_angle(i)
		var p := Vector3(sin(a) * SEAT_R, 0, cos(a) * SEAT_R)
		var seat := _box(Vector3(0.62, 0.10, 0.60), p + Vector3(0, 0.46, 0),
			Color(0.055, 0.042, 0.040))
		seat.rotation.y = a
		var back := _box(Vector3(0.62, 0.86, 0.10),
			p + Vector3(sin(a) * 0.28, 0.90, cos(a) * 0.28), Color(0.048, 0.037, 0.035))
		back.rotation.y = a


## Seats sit on the far arc so the camera sees five faces, not five backs.
func _seat_angle(i: int) -> float:
	return PI + (float(i) - 2.0) * 0.52


# ── agents ──────────────────────────────────────────────────────────────────

func _build_agents() -> void:
	for i in SEATS.size():
		var frames := _load_frames(i)
		var a := _seat_angle(i)
		var p := Vector3(sin(a) * SEAT_R, 0, cos(a) * SEAT_R)

		var root := Node3D.new()
		root.position = p + Vector3(0, 1.28, 0)
		add_child(root)

		var spr := AnimatedSprite3D.new()
		spr.sprite_frames = frames
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.pixel_size = 0.0017
		spr.shaded = true
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.double_sided = false
		root.add_child(spr)
		if frames != null and frames.has_animation("idle"):
			spr.play("idle")
			spr.frame = _rng.randi_range(0, 5)

		# Accent light per identity. Tiny range, so it rims the character
		# without lighting the room.
		var rim := OmniLight3D.new()
		rim.light_color = SEATS[i]["tint"]
		rim.light_energy = 1.5
		rim.omni_range = 1.25
		rim.shadow_enabled = false
		rim.position = Vector3(sin(a) * 0.55, 0.30, cos(a) * 0.55)
		root.add_child(rim)

		_agents.append({"root": root, "sprite": spr, "rim": rim, "index": i,
			"seat_pos": p, "angle": a, "alive": true})


func _load_frames(i: int) -> SpriteFrames:
	var dir: String = str(SEATS[i]["dir"])
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for spec in [["idle", "Idle Blinking", true, 9.0],
			["hurt", "Hurt", false, 15.0],
			["dying", "Dying", false, 12.0]]:
		var anim: String = str(spec[0])
		sf.add_animation(anim)
		sf.set_animation_loop(anim, bool(spec[2]))
		sf.set_animation_speed(anim, float(spec[3]))
		var folder := "%s/%s" % [dir, str(spec[1])]
		var names := _pngs_in(folder)
		var step: int = 2 if names.size() > 16 else 1
		for k in range(0, names.size(), step):
			var tex: Texture2D = load("%s/%s" % [folder, names[k]])
			if tex != null:
				sf.add_frame(anim, tex)
	return sf


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


func _agent(i: int) -> Dictionary:
	for a in _agents:
		if int(a["index"]) == i:
			return a
	return {}


# ── the revolver ────────────────────────────────────────────────────────────

func _build_gun() -> void:
	_gun = Node3D.new()
	add_child(_gun)
	var s := Sprite3D.new()
	if ResourceLoader.exists(GUN_TEX):
		s.texture = load(GUN_TEX)
	s.pixel_size = 0.0016
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.double_sided = true
	_gun.add_child(s)
	_gun_sprite = s
	# Lying on the table, muzzle toward camera-left.
	_gun.position = Vector3(0.05, 1.00, 0.10)
	_gun.rotation = Vector3(-PI * 0.5, 0.18, 0)


func _build_fx() -> void:
	_bulb = OmniLight3D.new()
	_bulb.position = Vector3(0, 3.05, 0)
	_bulb.light_color = Color(1.0, 0.80, 0.55)
	_bulb.light_energy = 3.4
	_bulb.omni_range = 9.5
	_bulb.shadow_enabled = true
	_bulb.light_specular = 0.2
	add_child(_bulb)

	var shade := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.075
	sm.height = 0.15
	sm.radial_segments = 8
	sm.rings = 5
	shade.mesh = sm
	shade.position = Vector3(0, 3.05, 0)
	shade.material_override = _mat(Color(1.0, 0.92, 0.72), 0.6, 0.0, true)
	add_child(shade)
	_box(Vector3(0.03, 0.55, 0.03), Vector3(0, 3.42, 0), Color(0.05, 0.04, 0.038))

	_muzzle = OmniLight3D.new()
	_muzzle.light_color = Color(1.0, 0.86, 0.55)
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 5.0
	_muzzle.shadow_enabled = false
	add_child(_muzzle)

	_flash_quad = Sprite3D.new()
	_flash_quad.texture = _flash_texture()
	_flash_quad.pixel_size = 0.006
	_flash_quad.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_quad.shaded = false
	_flash_quad.modulate = Color(1, 1, 1, 0)
	_flash_quad.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(_flash_quad)

	if not _perf:
		_blood_parts = _make_blood()
		add_child(_blood_parts)
		_smoke = _make_smoke()
		add_child(_smoke)

	_blood_decal = Decal.new()
	_blood_decal.texture_albedo = _splatter_texture()
	_blood_decal.size = Vector3(2.2, 2.2, 1.2)
	_blood_decal.modulate = Color(1, 1, 1, 0)
	_blood_decal.albedo_mix = 1.0
	add_child(_blood_decal)


## A cheap star-burst, generated rather than shipped.
func _flash_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n * 0.5, n * 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y) - c
			var r := d.length() / (n * 0.5)
			var ang := atan2(d.y, d.x)
			var spikes: float = 0.55 + 0.45 * pow(absf(cos(ang * 4.0)), 6.0)
			var v: float = clampf(1.0 - r / spikes, 0.0, 1.0)
			v = pow(v, 2.2)
			img.set_pixel(x, y, Color(1.0, 0.86 + 0.14 * v, 0.45 + 0.4 * v, v))
	return ImageTexture.create_from_image(img)


func _splatter_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for blob in 90:
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(0.0, 108.0)
		var cx := int(128 + cos(ang) * rad)
		var cy := int(128 + sin(ang) * rad * 0.85)
		var br := int(rng.randf_range(3.0, 20.0) * (1.0 - rad / 150.0) + 2.0)
		for dy in range(-br, br + 1):
			for dx in range(-br, br + 1):
				if dx * dx + dy * dy > br * br:
					continue
				var px := cx + dx
				var py := cy + dy
				if px < 0 or py < 0 or px >= n or py >= n:
					continue
				img.set_pixel(px, py, Color(0.34, 0.025, 0.04, 0.95))
	# runs
	for run in 10:
		var rx := int(rng.randf_range(40, 216))
		var ry := int(rng.randf_range(110, 150))
		var len_r := int(rng.randf_range(20, 90))
		var wdt := int(rng.randf_range(1, 4))
		for yy in range(ry, mini(n, ry + len_r)):
			for xx in range(rx, mini(n, rx + wdt)):
				img.set_pixel(xx, yy, Color(0.30, 0.02, 0.035, 0.9))
	return ImageTexture.create_from_image(img)


func _make_blood() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 96
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0.4, -1)
	m.spread = 42.0
	m.initial_velocity_min = 3.5
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, -12.0, 0)
	m.scale_min = 0.5
	m.scale_max = 1.6
	m.color = Color(0.45, 0.03, 0.05)
	p.process_material = m
	var qm := QuadMesh.new()
	qm.size = Vector2(0.045, 0.045)
	p.draw_pass_1 = qm
	var dm := _mat(Color(0.45, 0.03, 0.05), 1.0, 0.0, true)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.material_override = dm
	return p


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.7
	p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 30.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.3
	m.gravity = Vector3(0, 0.35, 0)
	m.scale_min = 0.8
	m.scale_max = 2.4
	m.color = Color(0.5, 0.45, 0.40, 0.16)
	p.process_material = m
	var qm := QuadMesh.new()
	qm.size = Vector2(0.30, 0.30)
	p.draw_pass_1 = qm
	var dm := _mat(Color(0.5, 0.45, 0.40, 0.16), 1.0, 0.0, true)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	p.material_override = dm
	return p


# ── HUD ─────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_hud = root

	for i in SEATS.size():
		var plate := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.025, 0.024, 0.86)
		sb.border_color = Color(SEATS[i]["tint"].r, SEATS[i]["tint"].g,
			SEATS[i]["tint"].b, 0.55)
		sb.set_border_width_all(2)
		plate.add_theme_stylebox_override("panel", sb)
		plate.position = Vector2(66 + i * 316, 40)
		plate.size = Vector2(286, 56)
		root.add_child(plate)

		var nm := Label.new()
		nm.text = str(SEATS[i]["name"])
		nm.add_theme_font_size_override("font_size", 21)
		nm.add_theme_color_override("font_color", SEATS[i]["tint"])
		nm.add_theme_constant_override("outline_size", 5)
		nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		nm.position = Vector2(78 + i * 316, 52)
		nm.size = Vector2(266, 28)
		root.add_child(nm)
		_plates.append({"panel": plate, "label": nm, "style": sb, "index": i})

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 64)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_banner.position = Vector2(0, 380)
	_banner.size = Vector2(1920, 90)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate = Color(1, 1, 1, 0)
	root.add_child(_banner)

	_sub_name = Label.new()
	_sub_name.add_theme_font_size_override("font_size", 19)
	_sub_name.add_theme_constant_override("outline_size", 5)
	_sub_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_sub_name.position = Vector2(0, 946)
	_sub_name.size = Vector2(1920, 26)
	_sub_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_sub_name)

	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 30)
	_sub.add_theme_color_override("font_color", Color(0.92, 0.87, 0.79))
	_sub.add_theme_constant_override("outline_size", 8)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_sub.position = Vector2(0, 976)
	_sub.size = Vector2(1920, 44)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_sub)


func _say(who: String, text: String) -> void:
	_sub.text = "“%s”" % text if text != "" else ""
	_sub_name.text = who
	var tint := Color(0.6, 0.6, 0.6)
	for i in SEATS.size():
		if str(SEATS[i]["name"]) == who:
			tint = SEATS[i]["tint"]
	_sub_name.add_theme_color_override("font_color", tint)


func _flash_banner(text: String, col: Color, hold := 1.6) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate", Color(1, 1, 1, 1), 0.20)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate", Color(1, 1, 1, 0), 0.4)


func _focus_plate(i: int) -> void:
	for rec in _plates:
		var on: bool = int(rec["index"]) == i
		var t: Color = SEATS[int(rec["index"])]["tint"]
		rec["style"].border_color = Color(t.r, t.g, t.b, 0.95 if on else 0.40)
		rec["style"].bg_color = Color(0.05, 0.035, 0.033, 0.92) if on \
			else Color(0.03, 0.025, 0.024, 0.80)
		rec["panel"].queue_redraw()


# ── camera language ─────────────────────────────────────────────────────────

## looking_at() takes a world POSITION, not a direction. Passing a direction
## aimed every camera in the scene at a point near the origin.
func _look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis(), from).looking_at(at, Vector3.UP)


func _cut_to(t: Transform3D, dur := 0.0) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 44.0
		_cam.near = 0.05
		add_child(_cam)
		_cam.current = true
	_cam_from = _cam.global_transform
	_cam_to = t
	_cam_dur = dur
	_cam_k = 0.0 if dur > 0.0 else 1.0
	if dur <= 0.0:
		_cam.global_transform = t


func _victim_pos() -> Vector3:
	var a = _agent(VICTIM)
	return (a["seat_pos"] as Vector3) + Vector3(0, 1.62, 0)


## Readable master: the whole table, five faces, slightly above eye line.
func _shot_master() -> Transform3D:
	return _look(Vector3(0.0, 3.05, 7.30), Vector3(0, 1.35, -0.55))


## Speaker close-up, angled so the room falls away behind them.
func _shot_closeup(i: int) -> Transform3D:
	var a = _agent(i)
	var p := (a["seat_pos"] as Vector3) + Vector3(0, 1.05, 0)
	var dir := (Vector3(0, 1.4, 4.6) - p).normalized()
	return _look(p + dir * 2.35 + Vector3(0.26, 0.16, 0), p + Vector3(0, 0.04, 0))


## Cylinder insert: tight on the gun, low, so the table edge crops the frame.
func _shot_insert() -> Transform3D:
	var g := _gun.global_position
	return _look(g + Vector3(0.42, 0.34, 1.15), g)


## Victim profile, from their left, gun and face in the same frame.
func _shot_profile() -> Transform3D:
	var p := _victim_pos()
	return _look(p + Vector3(1.85, 0.42, 1.65), p + Vector3(-0.05, 0.02, 0))


## Hard cut to the muzzle at the moment of the shot.
func _shot_muzzle() -> Transform3D:
	var p := _victim_pos() + Vector3(0, 0.34, 0)
	return _look(p + Vector3(1.15, 0.24, 1.00), p)


## Wide again for the consequence: body, blood, four survivors watching.
func _shot_aftermath() -> Transform3D:
	return _look(Vector3(2.35, 2.75, 6.10), Vector3(0.45, 1.30, -0.55))


# ── the sequence ────────────────────────────────────────────────────────────

func _enter_beat(b: int) -> void:
	_beat = b
	_bt = 0.0
	match b:
		Beat.ANTICIPATION:
			_focus_plate(VICTIM)
			_cut_to(_shot_closeup(VICTIM), 1.1)
			_say(SEATS[VICTIM]["name"], "You are all going to watch this.")
			_shot("01_anticipation")
		Beat.PICKUP:
			_cut_to(_shot_insert(), 0.0)
			_say("", "")
			var tw := create_tween()
			tw.tween_property(_gun, "position",
				_victim_pos() + Vector3(0.22, -0.30, 0.30), 1.2)
			tw.parallel().tween_property(_gun, "rotation",
				Vector3(-0.32, 0.18, 0.0), 1.2)
			_shot("02_pickup")
		Beat.SPIN:
			_cut_to(_shot_insert(), 0.5)
			_sfx("spin")
			# The cylinder spin, read as the whole gun rolling on its axis.
			var tw2 := create_tween()
			tw2.tween_property(_gun, "rotation:z", TAU * 2.0, 1.5)
			_shot("03_cylinder")
		Beat.RAISE:
			_cut_to(_shot_profile(), 0.9)
			var a = _agent(VICTIM)
			a["sprite"].play("hurt")
			var tw3 := create_tween()
			tw3.tween_property(_gun, "position", _victim_pos() + Vector3(0.16, 0.30, 0.02), 1.0)
			tw3.parallel().tween_property(_gun, "rotation", Vector3(0, 0.18, PI * 0.5), 1.0)
			_say(SEATS[VICTIM]["name"], "One of six.")
			_shot("04_raise")
		Beat.HOLD:
			_cut_to(_shot_profile(), 1.6)
			_say(SEATS[VICTIM]["name"], "Somebody count for me.")
			_shot("05_hold")
		Beat.TRIGGER:
			_cut_to(_shot_muzzle(), 0.0)
			_shot("06_trigger")
		Beat.IMPACT:
			_fire()
			_shot("07_muzzle_flash")
		Beat.COLLAPSE:
			_cut_to(_shot_aftermath(), 0.8)
			var a2 = _agent(VICTIM)
			a2["sprite"].play("dying")
			a2["alive"] = false
			var tw4 := create_tween()
			tw4.tween_property(a2["root"], "position",
				(a2["seat_pos"] as Vector3) + Vector3(0.10, 0.16, 0.22), 1.6)
			tw4.parallel().tween_property(a2["rim"], "light_energy", 0.10, 1.2)
			for rec in _plates:
				if int(rec["index"]) == VICTIM:
					rec["style"].border_color = Color(0.55, 0.06, 0.06, 0.9)
					rec["label"].add_theme_color_override("font_color",
						Color(0.42, 0.20, 0.20, 0.75))
			_flash_banner("%s IS OUT" % SEATS[VICTIM]["name"], Color(1.0, 0.18, 0.05), 1.8)
			_shot("08_collapse")
		Beat.REACTION:
			_cut_to(_shot_closeup(1), 1.0)
			_say(SEATS[1]["name"], "Reload it.")
			_shot("09_reaction")
		Beat.DONE:
			_cut_to(_shot_master(), 1.4)
			_say("", "")
			_shot("10_after")


## The shot itself: light, flash quad, blood, decal on the wall, shake.
func _fire() -> void:
	_sfx("gunshot")
	var head := _victim_pos() + Vector3(0, 0.30, 0)
	_muzzle.position = head + Vector3(0.10, 0.10, 0.06)
	_muzzle.light_energy = 26.0
	_flash_quad.position = _muzzle.position
	_flash_quad.modulate = Color(1, 1, 1, 1)
	_shake = 1.0

	var tw := create_tween()
	tw.tween_property(_muzzle, "light_energy", 0.0, 0.16)
	var tw2 := create_tween()
	tw2.tween_property(_flash_quad, "modulate", Color(1, 1, 1, 0), 0.18)

	if _blood_parts != null:
		_blood_parts.position = head
		_blood_parts.restart()
		_blood_parts.emitting = true
	if _smoke != null:
		_smoke.position = _muzzle.position
		_smoke.restart()
		_smoke.emitting = true

	# Permanent mark on the wall behind the victim.
	var a = _agent(VICTIM)
	var ang: float = a["angle"]
	_blood_decal.position = Vector3(sin(ang) * 4.15, 1.62, cos(ang) * 4.15)
	_blood_decal.rotation = Vector3(0, ang, 0)
	var tw3 := create_tween()
	tw3.tween_property(_blood_decal, "modulate", Color(1, 1, 1, 1), 0.12)

	_gun.visible = false


func _sfx(cue: String) -> void:
	var path := ""
	for ext in [".wav", ".ogg", ".mp3"]:
		var p := "res://assets/audio/%s%s" % [cue, ext]
		if ResourceLoader.exists(p):
			path = p
			break
	if path == "":
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = load(path)
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)


func _process(delta: float) -> void:
	_t += delta
	_bt += delta

	if not _shot_queue.is_empty():
		_do_shot()

	# Camera interpolation plus a little handheld drift, and a hard shake on
	# the gunshot.
	if _cam != null:
		if _cam_k < 1.0 and _cam_dur > 0.0:
			_cam_k = minf(1.0, _cam_k + delta / _cam_dur)
		var e := _cam_k * _cam_k * (3.0 - 2.0 * _cam_k)
		var base := _cam_from.interpolate_with(_cam_to, e) if _cam_dur > 0.0 else _cam_to
		# Handheld drift and shake are an OFFSET from the shot, never
		# accumulated onto it. Adding them each frame walked the camera metres
		# into the table over twenty seconds.
		var off := Vector3(sin(_t * 0.31) * 0.020, cos(_t * 0.27) * 0.015, 0)
		if _shake > 0.001:
			_shake = maxf(0.0, _shake - delta * 3.2)
			off += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1),
				_rng.randf_range(-1, 1)) * 0.12 * _shake
		base.origin += base.basis * off
		_cam.global_transform = base

	if _bulb != null:
		_bulb.light_energy = 3.4 + sin(_t * 5.3) * 0.10 + sin(_t * 11.7) * 0.06

	if _beat == Beat.DONE:
		if _bt > 3.0:
			if _hold:
				get_tree().reload_current_scene()
			elif _seq_dir != "":
				get_tree().quit()
		return
	if _bt >= float(BEAT_TIME.get(_beat, 2.0)):
		_enter_beat(_beat + 1)


# ── beat capture ────────────────────────────────────────────────────────────

func _shot(tag: String) -> void:
	if _seq_dir == "":
		return
	_shot_queue.append(tag)


func _do_shot() -> void:
	if _shooting:
		return
	_shooting = true
	var tag: String = str(_shot_queue.pop_front())
	# Let the cut and the tween settle before grabbing the frame.
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shooting = false
	if img == null:
		return
	_seq_i += 1
	var path := "%s/%s.png" % [_seq_dir, tag]
	if img.save_png(path) == OK:
		print("SA3D_SHOT %s" % path)
