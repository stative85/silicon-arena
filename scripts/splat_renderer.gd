extends Node2D

## ═══════════════════════════════════════════════════════════════════
## SPLAT ENGINE v1.0 — Godot Renderer
## Loads packed JSON or binary splat data from Gemini Studio exports.
## Also generates splats from raw PNG if no export file available.
## Motion fields, layer system, audio reactivity, arena hooks.
## ═══════════════════════════════════════════════════════════════════

const ARENA_SIZE := Vector2(1540, 720)
const ARENA_CENTER := Vector2(770, 360)
const MAX_SPLATS := 50000
const DEFAULT_SPLATS := 3000

# ── Packed float arrays (no per-point dictionaries) ───────────────
# Stride: [x, y, z, size, r, g, b, a, orig_x, orig_y, phase, layer]
const STRIDE := 12
const X := 0; const Y := 1; const Z := 2; const SZ := 3
const R := 4; const G := 5; const B := 6; const A := 7
const OX := 8; const OY := 9; const PH := 10; const LY := 11

var _data := PackedFloat32Array()
var _count := 0
var _loaded := false
var _time := 0.0

# ── Motion System ─────────────────────────────────────────────────
enum MotionMode { DRIFT, VORTEX, COLLAPSE, EXPLOSION, BASS_PULSE, NOISE, NONE }
var motion_mode: int = MotionMode.DRIFT
var motion_intensity := 1.0
var motion_turbulence := 0.3
var motion_spring := 0.02  # pull-to-origin strength

# ── Render System ─────────────────────────────────────────────────
enum RenderMode { SOFT_GLOW, HARD_DOT, STREAK, TOXIC, ADDITIVE }
var render_mode: int = RenderMode.SOFT_GLOW
var glow_radius := 1.4
var streak_angle := 0.0  # radians, for STREAK mode

# ── Layer System (0=BG, 1=MID, 2=FG) ─────────────────────────────
var layer_visible := [true, true, true]
var layer_motion_scale := [0.5, 1.0, 1.5]  # parallax multiplier
var layer_z_ranges := [Vector2(0.6, 1.0), Vector2(0.3, 0.6), Vector2(0.0, 0.3)]

# ── External Reactivity (wired from main.gd) ─────────────────────
var beat_intensity := 0.0   # 0-1, audio bass hit
var mid_intensity := 0.0    # 0-1, audio mids
var high_intensity := 0.0   # 0-1, audio highs
var doom_factor := 0.0      # 0-1, arena doom meter
var heat_level := 0.0       # 0-1, debate heat
var scatter_force := 0.0    # 0-1, shockwave scatter
var arena_focus := "normal" # "normal", "beef", "agape"

# ── Camera ────────────────────────────────────────────────────────
var camera_offset := Vector2.ZERO
var camera_zoom := 1.0
var camera_shake := 0.0
var _shake_offset := Vector2.ZERO

# ── Presets ───────────────────────────────────────────────────────
const PRESETS := {
	"subtle_drift": {
		"motion": MotionMode.DRIFT, "intensity": 0.4, "turbulence": 0.1,
		"render": RenderMode.SOFT_GLOW, "glow": 1.4,
	},
	"doom_approach": {
		"motion": MotionMode.COLLAPSE, "intensity": 1.2, "turbulence": 0.5,
		"render": RenderMode.TOXIC, "glow": 1.8,
	},
	"bass_pulse": {
		"motion": MotionMode.BASS_PULSE, "intensity": 1.0, "turbulence": 0.3,
		"render": RenderMode.ADDITIVE, "glow": 2.0,
	},
	"vortex": {
		"motion": MotionMode.VORTEX, "intensity": 0.8, "turbulence": 0.4,
		"render": RenderMode.SOFT_GLOW, "glow": 1.6,
	},
	"explosion": {
		"motion": MotionMode.EXPLOSION, "intensity": 1.5, "turbulence": 0.6,
		"render": RenderMode.STREAK, "glow": 1.2,
	},
	"nebula": {
		"motion": MotionMode.NOISE, "intensity": 0.6, "turbulence": 0.8,
		"render": RenderMode.SOFT_GLOW, "glow": 2.2,
	},
}

# ═══════════════════════════════════════════════════════════════════
# LOADING — supports 3 formats
# ═══════════════════════════════════════════════════════════════════

func load_packed_json(path: String) -> bool:
	## Load packed array format: {"meta":{...}, "splats":[[x,y,z,sx,sy,r,g,b,a],...]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[SPLAT] Cannot open: %s" % path)
		return false
	var text := file.get_as_text()
	file.close()
	var json = JSON.parse_string(text)
	if json == null or not json is Dictionary:
		print("[SPLAT] Invalid JSON: %s" % path)
		return false
	var meta: Dictionary = json.get("meta", {})
	var raw_splats: Array = json.get("splats", [])
	if raw_splats.is_empty():
		print("[SPLAT] No splats in file")
		return false

	var src_w: float = float(meta.get("width", 1280))
	var src_h: float = float(meta.get("height", 720))
	var scale_x := ARENA_SIZE.x / src_w
	var scale_y := ARENA_SIZE.y / src_h

	var count := mini(raw_splats.size(), MAX_SPLATS)
	_data.resize(count * STRIDE)
	_count = count

	for i in range(count):
		var s = raw_splats[i]
		if not s is Array or s.size() < 9:
			continue
		var idx := i * STRIDE
		# Packed format: [x, y, z, sx, sy, r, g, b, a]
		# Values may be quantized ints (0-255 for color) or floats
		var px: float = float(s[0]) * scale_x
		var py: float = float(s[1]) * scale_y
		var pz: float = float(s[2]) / 255.0 if float(s[2]) > 1.0 else float(s[2])
		var sz: float = float(s[3])
		if sz > 10.0:
			sz = sz / 10.0  # quantized size
		var cr: float = float(s[5]); var cg: float = float(s[6])
		var cb: float = float(s[7]); var ca: float = float(s[8])
		# Detect quantized 0-255 color values
		if cr > 1.0 or cg > 1.0 or cb > 1.0 or ca > 1.0:
			cr /= 255.0; cg /= 255.0; cb /= 255.0; ca /= 255.0

		var layer := 0  # BG
		if pz < 0.3: layer = 2  # FG
		elif pz < 0.6: layer = 1  # MID

		_data[idx + X] = px
		_data[idx + Y] = py
		_data[idx + Z] = pz
		_data[idx + SZ] = clampf(sz, 1.0, 20.0)
		_data[idx + R] = clampf(cr, 0.0, 1.0)
		_data[idx + G] = clampf(cg, 0.0, 1.0)
		_data[idx + B] = clampf(cb, 0.0, 1.0)
		_data[idx + A] = clampf(ca, 0.0, 1.0)
		_data[idx + OX] = px
		_data[idx + OY] = py
		_data[idx + PH] = randf() * TAU
		_data[idx + LY] = float(layer)

	_loaded = true
	print("[SPLAT] Loaded %d splats from packed JSON (%s)" % [_count, path])
	queue_redraw()
	return true

func load_binary(path: String, src_w: float = 1280.0, src_h: float = 720.0) -> bool:
	## Load binary format: [x:f32, y:f32, z:f32, r:u8, g:u8, b:u8, a:u8, size:f32] = 20 bytes per point
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[SPLAT] Cannot open binary: %s" % path)
		return false
	var bytes := file.get_buffer(file.get_length())
	file.close()

	var bytes_per_point := 20
	var point_count := bytes.size() / bytes_per_point
	if point_count == 0:
		return false
	point_count = mini(point_count, MAX_SPLATS)

	var scale_x := ARENA_SIZE.x / src_w
	var scale_y := ARENA_SIZE.y / src_h

	_data.resize(point_count * STRIDE)
	_count = point_count

	for i in range(point_count):
		var offset := i * bytes_per_point
		var idx := i * STRIDE
		var px := bytes.decode_float(offset) * scale_x
		var py := bytes.decode_float(offset + 4) * scale_y
		var pz := bytes.decode_float(offset + 8)
		var cr := float(bytes[offset + 12]) / 255.0
		var cg := float(bytes[offset + 13]) / 255.0
		var cb := float(bytes[offset + 14]) / 255.0
		var ca := float(bytes[offset + 15]) / 255.0
		var sz := bytes.decode_float(offset + 16)

		# Remap normalized coords (-1..1) to arena space if needed
		if px < 0.0 or py < 0.0:
			px = (px + 1.0) * 0.5 * ARENA_SIZE.x
			py = (py + 1.0) * 0.5 * ARENA_SIZE.y

		var layer := 0
		if pz < 0.3: layer = 2
		elif pz < 0.6: layer = 1

		_data[idx + X] = px; _data[idx + Y] = py; _data[idx + Z] = pz
		_data[idx + SZ] = clampf(sz, 1.0, 20.0)
		_data[idx + R] = cr; _data[idx + G] = cg; _data[idx + B] = cb; _data[idx + A] = ca
		_data[idx + OX] = px; _data[idx + OY] = py
		_data[idx + PH] = randf() * TAU; _data[idx + LY] = float(layer)

	_loaded = true
	print("[SPLAT] Loaded %d splats from binary (%s)" % [_count, path])
	queue_redraw()
	return true

func load_from_path(path: String, splat_count: int = DEFAULT_SPLATS) -> bool:
	## Auto-detect format by extension, fallback to PNG decomposition
	if path.ends_with(".json") or path.ends_with(".json.gz"):
		return load_packed_json(path)
	if path.ends_with(".bin") or path.ends_with(".splat"):
		return load_binary(path)
	# Treat as image — decompose to splats
	return _load_image_and_generate(path, splat_count)

func _load_image_and_generate(path: String, count: int) -> bool:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex = load(path) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.new()
		if img.load(path) != OK:
			img = null
	if img == null:
		print("[SPLAT] Failed to load image: %s" % path)
		return false

	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var iw := img.get_width()
	var ih := img.get_height()
	if iw == 0 or ih == 0:
		return false

	var scale_x := ARENA_SIZE.x / float(iw)
	var scale_y := ARENA_SIZE.y / float(ih)
	count = clampi(count, 500, MAX_SPLATS)

	# Importance sampling — edge + saturation bias
	var candidates := PackedFloat32Array()
	var step := maxi(1, int(sqrt(float(iw * ih) / float(count * 4))))

	for y in range(0, ih, step):
		for x in range(0, iw, step):
			var c := img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			var brightness := (c.r + c.g + c.b) / 3.0
			var max_ch := maxf(c.r, maxf(c.g, c.b))
			var min_ch := minf(c.r, minf(c.g, c.b))
			var sat := max_ch - min_ch
			var weight := brightness * 0.5 + sat * 0.3 + 0.2
			# Pack: x, y, r, g, b, a, weight, brightness
			candidates.append_array([float(x), float(y), c.r, c.g, c.b, c.a, weight, brightness])

	# Sort by weight — take top candidates
	var entries: Array = []
	var entry_stride := 8
	for i in range(0, candidates.size(), entry_stride):
		entries.append(i)
	entries.sort_custom(func(a, b): return candidates[a + 6] > candidates[b + 6])

	var to_use := mini(entries.size(), count)
	_data.resize(to_use * STRIDE)
	_count = to_use

	for i in range(to_use):
		var ci: int = entries[i]
		var idx := i * STRIDE
		var px: float = candidates[ci] * scale_x + randf_range(-scale_x * 0.4, scale_x * 0.4)
		var py: float = candidates[ci + 1] * scale_y + randf_range(-scale_y * 0.4, scale_y * 0.4)
		var cr: float = candidates[ci + 2]
		var cg: float = candidates[ci + 3]
		var cb: float = candidates[ci + 4]
		var ca: float = candidates[ci + 5]
		var bright: float = candidates[ci + 7]

		# Derive Z from brightness (dark = far)
		var pz := 1.0 - bright
		var sz: float = lerp(3.0, 8.0, 1.0 - bright) * maxf(scale_x, scale_y) * 0.3
		var layer := 0
		if pz < 0.3: layer = 2
		elif pz < 0.6: layer = 1

		_data[idx + X] = px; _data[idx + Y] = py; _data[idx + Z] = pz
		_data[idx + SZ] = sz
		_data[idx + R] = cr; _data[idx + G] = cg; _data[idx + B] = cb; _data[idx + A] = ca
		_data[idx + OX] = px; _data[idx + OY] = py
		_data[idx + PH] = randf() * TAU; _data[idx + LY] = float(layer)

	_loaded = true
	print("[SPLAT] Generated %d splats from image (%dx%d)" % [_count, iw, ih])
	queue_redraw()
	return true

func clear_splats() -> void:
	_data.resize(0)
	_count = 0
	_loaded = false
	queue_redraw()

func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		print("[SPLAT] Unknown preset: %s" % preset_name)
		return
	var p: Dictionary = PRESETS[preset_name]
	motion_mode = p.get("motion", MotionMode.DRIFT)
	motion_intensity = p.get("intensity", 1.0)
	motion_turbulence = p.get("turbulence", 0.3)
	render_mode = p.get("render", RenderMode.SOFT_GLOW)
	glow_radius = p.get("glow", 1.4)
	print("[SPLAT] Preset applied: %s" % preset_name)

func trigger_scatter(strength: float = 1.0) -> void:
	scatter_force = clampf(strength, 0.0, 2.0)

func trigger_beat(bass: float, mids: float = 0.0, highs: float = 0.0) -> void:
	beat_intensity = clampf(bass, 0.0, 1.0)
	mid_intensity = clampf(mids, 0.0, 1.0)
	high_intensity = clampf(highs, 0.0, 1.0)

# ═══════════════════════════════════════════════════════════════════
# MOTION FIELDS
# ═══════════════════════════════════════════════════════════════════

func _apply_motion(idx: int, delta: float) -> Vector2:
	var px: float = _data[idx + X]
	var py: float = _data[idx + Y]
	var ox: float = _data[idx + OX]
	var oy: float = _data[idx + OY]
	var phase: float = _data[idx + PH]
	var layer_scale: float = layer_motion_scale[int(_data[idx + LY])]
	var intensity: float = motion_intensity * layer_scale

	var dx := 0.0
	var dy := 0.0

	match motion_mode:
		MotionMode.DRIFT:
			dx = sin(_time * 0.7 + phase) * 3.0 * intensity
			dy = cos(_time * 0.5 + phase * 1.3) * 2.0 * intensity
			dx += sin(_time * 1.8 + phase * 2.7) * motion_turbulence * 2.0
			dy += cos(_time * 2.1 + phase * 3.1) * motion_turbulence * 1.5

		MotionMode.VORTEX:
			var to_center := ARENA_CENTER - Vector2(ox, oy)
			var angle := to_center.angle() + _time * 0.5 * intensity
			var dist := to_center.length()
			dx = cos(angle) * dist * 0.03 * intensity
			dy = sin(angle) * dist * 0.03 * intensity
			dx += sin(_time * 3.0 + phase) * motion_turbulence * 3.0
			dy += cos(_time * 2.5 + phase) * motion_turbulence * 3.0

		MotionMode.COLLAPSE:
			var to_center := ARENA_CENTER - Vector2(px, py)
			var pull := to_center.normalized() * intensity * 0.5
			dx = pull.x + sin(_time * 2.0 + phase) * motion_turbulence * 2.0
			dy = pull.y + cos(_time * 1.7 + phase) * motion_turbulence * 2.0

		MotionMode.EXPLOSION:
			var from_center := Vector2(ox, oy) - ARENA_CENTER
			var push := from_center.normalized() * intensity * 2.0
			dx = push.x * (1.0 + sin(_time * 3.0 + phase) * motion_turbulence)
			dy = push.y * (1.0 + cos(_time * 2.5 + phase) * motion_turbulence)

		MotionMode.BASS_PULSE:
			var from_center := Vector2(ox, oy) - ARENA_CENTER
			var pulse_str := beat_intensity * intensity * 3.0
			dx = from_center.normalized().x * pulse_str
			dy = from_center.normalized().y * pulse_str
			dx += sin(_time * 1.5 + phase) * 1.5
			dy += cos(_time * 1.2 + phase) * 1.0

		MotionMode.NOISE:
			var nx := sin(px * 0.01 + _time * 0.8) * cos(py * 0.013 + _time * 0.6)
			var ny := cos(px * 0.012 + _time * 0.7) * sin(py * 0.009 + _time * 0.9)
			dx = nx * 8.0 * intensity * motion_turbulence
			dy = ny * 6.0 * intensity * motion_turbulence

		MotionMode.NONE:
			pass

	# Spring pull back to origin
	dx += (ox - px) * motion_spring
	dy += (oy - py) * motion_spring

	# Scatter override
	if scatter_force > 0.01:
		var away := (Vector2(px, py) - ARENA_CENTER).normalized()
		dx += away.x * scatter_force * 120.0
		dy += away.y * scatter_force * 80.0

	return Vector2(px + dx * delta * 60.0, py + dy * delta * 60.0)

# ═══════════════════════════════════════════════════════════════════
# UPDATE
# ═══════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not _loaded:
		return
	_time += delta

	# Decay reactive values
	scatter_force = maxf(scatter_force - delta * 2.0, 0.0)
	beat_intensity = maxf(beat_intensity - delta * 4.0, 0.0)
	mid_intensity = maxf(mid_intensity - delta * 3.0, 0.0)
	high_intensity = maxf(high_intensity - delta * 5.0, 0.0)
	camera_shake = maxf(camera_shake - delta * 3.0, 0.0)

	# Camera shake
	if camera_shake > 0.01:
		_shake_offset = Vector2(
			randf_range(-1, 1) * camera_shake * 8.0,
			randf_range(-1, 1) * camera_shake * 6.0
		)
	else:
		_shake_offset = Vector2.ZERO

	# Apply motion to all points
	for i in range(_count):
		var idx := i * STRIDE
		var new_pos := _apply_motion(idx, delta)
		_data[idx + X] = clampf(new_pos.x, -50, ARENA_SIZE.x + 50)
		_data[idx + Y] = clampf(new_pos.y, -50, ARENA_SIZE.y + 50)

	queue_redraw()

# ═══════════════════════════════════════════════════════════════════
# RENDER
# ═══════════════════════════════════════════════════════════════════

func _draw() -> void:
	if not _loaded or _count == 0:
		return

	# Dark base
	draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color(0.015, 0.015, 0.03, 0.92))

	# Arena focus color shifts
	var focus_tint := Color.WHITE
	match arena_focus:
		"beef": focus_tint = Color(1.0, 0.85, 0.8)
		"agape": focus_tint = Color(0.85, 0.9, 1.0)

	# Draw back-to-front: layer 0 (BG) → 1 (MID) → 2 (FG)
	for draw_layer in range(3):
		if not layer_visible[draw_layer]:
			continue
		for i in range(_count):
			var idx := i * STRIDE
			if int(_data[idx + LY]) != draw_layer:
				continue

			var pos := Vector2(_data[idx + X], _data[idx + Y]) + _shake_offset + camera_offset
			var sz: float = _data[idx + SZ] * camera_zoom
			var cr: float = _data[idx + R]
			var cg: float = _data[idx + G]
			var cb: float = _data[idx + B]
			var ca: float = _data[idx + A]
			var phase: float = _data[idx + PH]

			# Beat size modulation
			sz *= 1.0 + beat_intensity * 0.5

			# High-frequency flicker
			if high_intensity > 0.1:
				ca *= 1.0 - high_intensity * 0.3 * (0.5 + 0.5 * sin(_time * 20.0 + phase))

			# Doom color shift
			if doom_factor > 0.05:
				cr = lerpf(cr, 0.9, doom_factor * 0.4)
				cg = lerpf(cg, 0.08, doom_factor * 0.3)
				cb = lerpf(cb, 0.05, doom_factor * 0.3)

			# Heat intensity boost
			if heat_level > 0.1:
				cr = minf(cr + heat_level * 0.15, 1.0)
				ca = minf(ca + heat_level * 0.1, 1.0)

			# Apply focus tint
			cr *= focus_tint.r; cg *= focus_tint.g; cb *= focus_tint.b

			# Mid jitter
			if mid_intensity > 0.05:
				pos += Vector2(
					sin(_time * 12.0 + phase) * mid_intensity * 4.0,
					cos(_time * 10.0 + phase) * mid_intensity * 3.0
				)

			match render_mode:
				RenderMode.SOFT_GLOW:
					draw_circle(pos, sz * glow_radius, Color(cr, cg, cb, ca * 0.12))
					draw_circle(pos, sz, Color(cr, cg, cb, ca * 0.4))
					draw_circle(pos, sz * 0.35, Color(
						minf(cr + 0.15, 1.0), minf(cg + 0.15, 1.0),
						minf(cb + 0.15, 1.0), ca * 0.65))

				RenderMode.HARD_DOT:
					draw_circle(pos, sz * 0.6, Color(cr, cg, cb, ca * 0.85))

				RenderMode.STREAK:
					var dir := Vector2(cos(streak_angle + phase * 0.3), sin(streak_angle + phase * 0.3))
					var streak_len := sz * 2.5 * (1.0 + beat_intensity)
					draw_line(pos - dir * streak_len, pos + dir * streak_len,
						Color(cr, cg, cb, ca * 0.35), sz * 0.4)
					draw_circle(pos, sz * 0.4, Color(cr, cg, cb, ca * 0.7))

				RenderMode.TOXIC:
					var toxic_pulse := sin(_time * 3.0 + phase) * 0.5 + 0.5
					var toxic_g := minf(cg + 0.3 * toxic_pulse, 1.0)
					draw_circle(pos, sz * glow_radius * 1.2, Color(cr * 0.5, toxic_g, cb * 0.3, ca * 0.1))
					draw_circle(pos, sz, Color(cr * 0.7, toxic_g, cb * 0.5, ca * 0.45))
					draw_circle(pos, sz * 0.3, Color(0.2, toxic_g, 0.1, ca * 0.7))

				RenderMode.ADDITIVE:
					var boost := 1.0 + beat_intensity * 0.5
					draw_circle(pos, sz * glow_radius, Color(
						minf(cr * boost, 1.0), minf(cg * boost, 1.0),
						minf(cb * boost, 1.0), ca * 0.2))
					draw_circle(pos, sz * 0.5, Color(
						minf(cr * boost + 0.2, 1.0), minf(cg * boost + 0.2, 1.0),
						minf(cb * boost + 0.2, 1.0), ca * 0.6))
