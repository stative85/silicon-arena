extends Node2D
## SPLAT TRAILER LAB — Godot native
## Type words → cinematic particles → size / shape / explode / sweep → PNG
## No HTML. No karaoke. Trailer only.

const ARENA := Vector2(1540, 720)
const CENTER := Vector2(770, 360)
const MAX_PTS := 16000
const STRIDE := 14
# layout: x y z sz r g b a ox oy phase edge vx vy

var pts := PackedFloat32Array()
var count := 0
var _time := 0.0
var _loaded := false
var _forming := false
var _form_t := 0.0
var _busy := false

var size_mul := 1.0
var shape_mode := 0  # 0 circle 1 diamond 2 square 3 streak 4 cross 5 ring
var entrance := 0    # 0 sweep 1 explode 2 rain 3 scan 4 spiral 5 implode
var look_i := 0
var cam_off := Vector2.ZERO
var cam_zoom := 1.0
var cam_mode := 0  # 0 static 1 dolly 2 orbit 3 push
var letterbox := true
var _shake := 0.0
var _shake_off := Vector2.ZERO
var _dragging := false

var _ui: CanvasLayer
var _text_edit: LineEdit
var _status: Label
var _size_slider: HSlider
var _count_slider: HSlider
var _vp: SubViewport
var _vp_label: Label

const LOOKS := [
	{"name": "SIDE SWEEP", "cam": 1, "hue": 0.72},
	{"name": "STAR COLLAPSE", "cam": 3, "hue": 0.55},
	{"name": "ASH FALL", "cam": 0, "hue": 0.08},
	{"name": "ORBIT DUST", "cam": 2, "hue": 0.12},
	{"name": "EMBER RIVER", "cam": 1, "hue": 0.02},
	{"name": "CYAN SCAN", "cam": 0, "hue": 0.52},
	{"name": "GOLD NEEDLES", "cam": 1, "hue": 0.1},
	{"name": "ICE DUST", "cam": 2, "hue": 0.55},
	{"name": "SPIRAL LOCK", "cam": 2, "hue": 0.78},
	{"name": "VOID EATER", "cam": 2, "hue": 0.7},
]

const SHAPE_NAMES := ["DOT", "DIAMOND", "SQUARE", "STREAK", "CROSS", "RING"]
const ENT_NAMES := ["SWEEP", "EXPLODE", "RAIN", "SCAN", "SPIRAL", "IMPLODE"]

# Compact 5x7 uppercase bitmap font (bits = columns top→bottom, left→right)
const FONT5X7 := {
	"A": [0x1E, 0x05, 0x05, 0x05, 0x1E],
	"B": [0x1F, 0x15, 0x15, 0x15, 0x0A],
	"C": [0x0E, 0x11, 0x11, 0x11, 0x0A],
	"D": [0x1F, 0x11, 0x11, 0x11, 0x0E],
	"E": [0x1F, 0x15, 0x15, 0x15, 0x11],
	"F": [0x1F, 0x05, 0x05, 0x05, 0x01],
	"G": [0x0E, 0x11, 0x15, 0x15, 0x1C],
	"H": [0x1F, 0x04, 0x04, 0x04, 0x1F],
	"I": [0x11, 0x1F, 0x11],
	"J": [0x08, 0x10, 0x11, 0x0F],
	"K": [0x1F, 0x04, 0x0A, 0x11],
	"L": [0x1F, 0x10, 0x10, 0x10],
	"M": [0x1F, 0x02, 0x04, 0x02, 0x1F],
	"N": [0x1F, 0x02, 0x04, 0x08, 0x1F],
	"O": [0x0E, 0x11, 0x11, 0x11, 0x0E],
	"P": [0x1F, 0x05, 0x05, 0x05, 0x02],
	"Q": [0x0E, 0x11, 0x15, 0x09, 0x16],
	"R": [0x1F, 0x05, 0x0D, 0x15, 0x12],
	"S": [0x12, 0x15, 0x15, 0x15, 0x09],
	"T": [0x01, 0x01, 0x1F, 0x01, 0x01],
	"U": [0x0F, 0x10, 0x10, 0x10, 0x0F],
	"V": [0x07, 0x08, 0x10, 0x08, 0x07],
	"W": [0x1F, 0x08, 0x04, 0x08, 0x1F],
	"X": [0x11, 0x0A, 0x04, 0x0A, 0x11],
	"Y": [0x03, 0x04, 0x18, 0x04, 0x03],
	"Z": [0x11, 0x19, 0x15, 0x13, 0x11],
	"0": [0x0E, 0x19, 0x15, 0x13, 0x0E],
	"1": [0x12, 0x1F, 0x10],
	"2": [0x12, 0x19, 0x15, 0x15, 0x12],
	"3": [0x11, 0x15, 0x15, 0x15, 0x0A],
	"4": [0x07, 0x04, 0x04, 0x1F, 0x04],
	"5": [0x17, 0x15, 0x15, 0x15, 0x09],
	"6": [0x0E, 0x15, 0x15, 0x15, 0x08],
	"7": [0x01, 0x01, 0x19, 0x05, 0x03],
	"8": [0x0A, 0x15, 0x15, 0x15, 0x0A],
	"9": [0x02, 0x15, 0x15, 0x15, 0x0E],
	"!": [0x17],
	"?": [0x02, 0x01, 0x15, 0x05, 0x02],
	".": [0x10],
	",": [0x10, 0x08],
	"-": [0x04, 0x04, 0x04],
	"'": [0x03],
	":": [0x0A],
	"/": [0x10, 0x08, 0x04, 0x02, 0x01],
	"&": [0x0A, 0x15, 0x15, 0x0A, 0x14],
}


func _ready() -> void:
	get_window().title = "SPLAT TRAILER LAB — Godot"
	get_window().size = Vector2i(1540, 720)
	RenderingServer.set_default_clear_color(Color(0, 0, 0))
	_build_ui()
	_setup_text_vp()
	_kick_generate("SIGNAL", true)


func _process(delta: float) -> void:
	if not _loaded:
		return
	_time += delta
	_form_t += delta
	_shake = maxf(_shake - delta * 3.0, 0.0)
	if _shake > 0.01:
		_shake_off = Vector2(randf_range(-1, 1) * _shake * 10.0, randf_range(-1, 1) * _shake * 7.0)
	else:
		_shake_off = Vector2.ZERO
	_camera(delta)
	_motion(delta)
	queue_redraw()


func _setup_text_vp() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 360)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_vp)
	_vp_label = Label.new()
	_vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp_label.add_theme_font_size_override("font_size", 150)
	_vp_label.add_theme_color_override("font_color", Color.WHITE)
	_vp_label.add_theme_color_override("font_outline_color", Color.WHITE)
	_vp_label.add_theme_constant_override("outline_size", 4)
	_vp.add_child(_vp_label)


# ── TEXT → PARTICLES ──────────────────────────────────────────────
func _kick_generate(text: String, scatter: bool = true) -> void:
	if _busy:
		return
	_busy = true
	_generate_text(text, scatter)


func _generate_text(text: String, scatter: bool = true) -> void:
	text = text.strip_edges().to_upper()
	if text.is_empty():
		text = "SIGNAL"
	if _status:
		_status.text = "STAMPING…"

	var glyph: Array = await _sample_glyphs(text)
	if glyph.is_empty():
		# hard fallback — always has points
		glyph = _sample_bitmap_glyphs(text)
	if glyph.is_empty():
		if _status:
			_status.text = "TEXT FAIL"
		_busy = false
		return

	var target := 10000
	if _count_slider:
		target = int(_count_slider.value)
	var n := mini(maxi(target, 2000), MAX_PTS)
	pts.resize(n * STRIDE)
	count = n
	var gsz := glyph.size()
	for i in range(n):
		var g: Dictionary = glyph[i % gsz]
		var hx: float = float(g.x)
		var hy: float = float(g.y)
		var edge: float = float(g.edge)
		var idx := i * STRIDE
		var sz := (1.35 if edge > 0.5 else 0.75) * size_mul * randf_range(0.65, 1.35)
		var hue: float = float(LOOKS[look_i].hue) + randf_range(-0.04, 0.04)
		var c := Color.from_hsv(fmod(hue + 1.0, 1.0), 0.5 + randf() * 0.4, 0.7 + randf() * 0.3)
		if edge > 0.5:
			c = c.lightened(0.3)
		pts[idx + 0] = hx
		pts[idx + 1] = hy
		pts[idx + 2] = randf()
		pts[idx + 3] = sz
		pts[idx + 4] = c.r
		pts[idx + 5] = c.g
		pts[idx + 6] = c.b
		pts[idx + 7] = 0.78 + edge * 0.18
		pts[idx + 8] = hx
		pts[idx + 9] = hy
		pts[idx + 10] = randf() * TAU
		pts[idx + 11] = edge
		pts[idx + 12] = 0.0
		pts[idx + 13] = 0.0
		if scatter:
			_spawn_entrance(idx, hx, hy)

	_loaded = true
	_forming = true
	_form_t = 0.0
	_busy = false
	_status_text()
	print("[TRAILER] %d pts · %s · %s · size=%.2f · glyphs=%d" % [
		count, ENT_NAMES[entrance], SHAPE_NAMES[shape_mode], size_mul, gsz
	])


func _spawn_entrance(idx: int, hx: float, hy: float) -> void:
	match entrance:
		0: # SWEEP
			var side := -1.0 if randf() < 0.5 else 1.0
			pts[idx] = hx + side * (520.0 + randf() * 600.0)
			pts[idx + 1] = hy + randf_range(-180, 180)
			pts[idx + 12] = -side * (280.0 + randf() * 420.0)
			pts[idx + 13] = randf_range(-80, 80)
		1: # EXPLODE
			var a := randf() * TAU
			var r := 40.0 + randf() * 120.0
			pts[idx] = CENTER.x + cos(a) * r
			pts[idx + 1] = CENTER.y + sin(a) * r
			var blast := 500.0 + randf() * 900.0
			pts[idx + 12] = cos(a) * blast
			pts[idx + 13] = sin(a) * blast
		2: # RAIN
			var up := randf() < 0.2
			pts[idx] = hx + randf_range(-40, 40)
			pts[idx + 1] = (-200.0 - randf() * 500.0) if not up else (ARENA.y + 200.0 + randf() * 400.0)
			pts[idx + 12] = randf_range(-40, 40)
			pts[idx + 13] = (600.0 + randf() * 500.0) if not up else (-600.0 - randf() * 500.0)
		3: # SCAN
			pts[idx] = -300.0 - randf() * 400.0
			pts[idx + 1] = hy + randf_range(-3, 3)
			pts[idx + 12] = 700.0 + randf() * 600.0
			pts[idx + 13] = 0.0
		4: # SPIRAL
			var a2 := randf() * TAU
			var r2 := 280.0 + randf() * 420.0
			pts[idx] = CENTER.x + cos(a2) * r2
			pts[idx + 1] = CENTER.y + sin(a2) * r2 * 0.75
			pts[idx + 12] = -sin(a2) * (200.0 + randf() * 300.0)
			pts[idx + 13] = cos(a2) * (200.0 + randf() * 300.0)
		5: # IMPLODE
			var a3 := randf() * TAU
			var r3 := 600.0 + randf() * 700.0
			pts[idx] = CENTER.x + cos(a3) * r3
			pts[idx + 1] = CENTER.y + sin(a3) * r3
			var suck := 180.0 + randf() * 280.0
			pts[idx + 12] = -cos(a3) * suck
			pts[idx + 13] = -sin(a3) * suck


func _sample_glyphs(text: String) -> Array:
	## Prefer crisp system font via SubViewport; fall back to dense bitmap.
	var img: Image = await _render_text_image(text)
	var arr: Array = []
	if img != null:
		arr = _pixels_to_glyphs(img)
	# Thin clouds look like sparse noise — bitmap is solid block letters
	if arr.size() < 1200:
		var bm := _sample_bitmap_glyphs(text)
		if bm.size() > arr.size():
			return bm
	return arr


func _render_text_image(text: String) -> Image:
	if _vp == null or _vp_label == null:
		return null
	_vp_label.text = text
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Wait for actual GPU frames so the label is painted
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := _vp.get_texture()
	if tex == null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return null
	var src := tex.get_image()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	return src


func _pixels_to_glyphs(img: Image) -> Array:
	var pts_arr: Array = []
	var w := img.get_width()
	var h := img.get_height()
	var step := 1
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) * 0.333
			if c.a < 0.08 and lum < 0.15:
				continue
			var edge := 0.0
			if x <= 1 or y <= 1 or x >= w - 2 or y >= h - 2:
				edge = 1.0
			else:
				var nL := img.get_pixel(x - 1, y)
				var nR := img.get_pixel(x + 1, y)
				var nU := img.get_pixel(x, y - 1)
				var nD := img.get_pixel(x, y + 1)
				var lL := (nL.r + nL.g + nL.b) * 0.333 + nL.a
				var lR := (nR.r + nR.g + nR.b) * 0.333 + nR.a
				var lU := (nU.r + nU.g + nU.b) * 0.333 + nU.a
				var lD := (nD.r + nD.g + nD.b) * 0.333 + nD.a
				if lL < 0.18 or lR < 0.18 or lU < 0.18 or lD < 0.18:
					edge = 1.0
			var px := (float(x) / float(w)) * ARENA.x
			var py := (float(y) / float(h)) * ARENA.y * 0.52 + ARENA.y * 0.24
			px += randf_range(-0.5, 0.5)
			py += randf_range(-0.5, 0.5)
			pts_arr.append({"x": px, "y": py, "edge": edge})
			if edge > 0.5:
				pts_arr.append({"x": px + randf_range(-1.0, 1.0), "y": py + randf_range(-1.0, 1.0), "edge": 1.0})
	return pts_arr


func _sample_bitmap_glyphs(text: String) -> Array:
	## Always-works procedural font — dense block letters as point clouds
	var pts_arr: Array = []
	var scale := 16.0
	var gap := 2
	var lines := text.replace("\\n", "\n").split("\n")
	# measure total width for centering
	var max_w := 0
	var line_ws: Array = []
	for line in lines:
		var lw := 0
		for i in range(line.length()):
			var ch := line[i]
			if ch == " ":
				lw += 3 + gap
				continue
			var cols: Array = FONT5X7.get(ch, FONT5X7["?"])
			lw += cols.size() + gap
		line_ws.append(lw)
		if lw > max_w:
			max_w = lw
	var total_h := lines.size() * 8 + (lines.size() - 1) * 3
	var base_x := CENTER.x - float(max_w) * scale * 0.5
	var base_y := CENTER.y - float(total_h) * scale * 0.5

	for li in range(lines.size()):
		var line: String = lines[li]
		var lw: int = line_ws[li]
		var x := CENTER.x - float(lw) * scale * 0.5
		var y := base_y + float(li) * (8 + 3) * scale
		for i in range(line.length()):
			var ch := line[i]
			if ch == " ":
				x += (3 + gap) * scale
				continue
			var cols2: Array = FONT5X7.get(ch, FONT5X7["?"])
			for cx in range(cols2.size()):
				var col: int = int(cols2[cx])
				for cy in range(7):
					if (col >> cy) & 1:
						var px := x + float(cx) * scale
						var py := y + float(cy) * scale
						# fill cell with dense samples
						for s in range(8):
							var jx := randf_range(0.0, scale * 0.9)
							var jy := randf_range(0.0, scale * 0.9)
							var edge := 0.0
							if cy == 0 or cy == 6 or cx == 0 or cx == cols2.size() - 1:
								edge = 1.0
							pts_arr.append({"x": px + jx, "y": py + jy, "edge": edge})
			x += (cols2.size() + gap) * scale
	# if still empty, single block
	if pts_arr.is_empty():
		for i in range(2000):
			pts_arr.append({
				"x": CENTER.x + randf_range(-200, 200),
				"y": CENTER.y + randf_range(-80, 80),
				"edge": 0.0
			})
	return pts_arr


# ── MOTION ────────────────────────────────────────────────────────
func _motion(delta: float) -> void:
	var spring := 9.0
	var damp := 0.90
	for i in range(count):
		var idx := i * STRIDE
		var px: float = pts[idx]
		var py: float = pts[idx + 1]
		var ox: float = pts[idx + 8]
		var oy: float = pts[idx + 9]
		var vx: float = pts[idx + 12]
		var vy: float = pts[idx + 13]
		if _forming:
			var delay := float(i % 48) * 0.0035
			var age := _form_t - delay
			if age > 0.0:
				var pull := clampf(age * 3.5, 0.0, 1.0)
				pull = pull * pull * (3.0 - 2.0 * pull)
				vx += (ox - px) * spring * pull * delta * 60.0
				vy += (oy - py) * spring * pull * delta * 60.0
				var df := 1.0 - clampf(pull * delta * 12.0, 0.0, 0.92)
				vx *= df
				vy *= df
		var ph: float = pts[idx + 10]
		vx += sin(_time * 1.2 + ph) * 6.0 * delta
		vy += cos(_time * 0.9 + ph * 1.3) * 5.0 * delta
		vx *= damp
		vy *= damp
		px += vx * delta
		py += vy * delta
		pts[idx] = px
		pts[idx + 1] = py
		pts[idx + 12] = vx
		pts[idx + 13] = vy


func _camera(_delta: float) -> void:
	match cam_mode:
		1:
			cam_off.x = sin(_time * 0.25) * 40.0
			cam_off.y = sin(_time * 0.18) * 12.0
		2:
			cam_off.x = cos(_time * 0.2) * 50.0
			cam_off.y = sin(_time * 0.2) * 20.0
		3:
			cam_zoom = lerpf(cam_zoom, 1.15 + sin(_form_t * 0.5) * 0.08, 0.02)
		_:
			cam_off = cam_off.lerp(Vector2.ZERO, 0.05)


# ── DRAW ──────────────────────────────────────────────────────────
func _draw() -> void:
	var vw := get_viewport_rect().size.x
	var vh := get_viewport_rect().size.y
	draw_rect(Rect2(Vector2.ZERO, Vector2(vw, vh)), Color(0, 0, 0, 1))
	if not _loaded or count == 0:
		return
	var sx := vw / ARENA.x
	var sy := vh / ARENA.y
	var ox := cam_off.x + _shake_off.x
	var oy := cam_off.y + _shake_off.y
	# draw in chunks — soft core + bright edge
	for i in range(count):
		var idx := i * STRIDE
		var p := Vector2((pts[idx] + ox) * sx, (pts[idx + 1] + oy) * sy)
		var sz: float = pts[idx + 3] * cam_zoom * size_mul * ((sx + sy) * 0.5)
		var c := Color(pts[idx + 4], pts[idx + 5], pts[idx + 6], pts[idx + 7])
		_draw_shape(p, sz, c)
	if letterbox:
		var bar := maxf(0.0, (vh - vw / 2.39) * 0.5)
		draw_rect(Rect2(0, 0, vw, bar), Color.BLACK)
		draw_rect(Rect2(0, vh - bar, vw, bar), Color.BLACK)


func _draw_shape(p: Vector2, sz: float, c: Color) -> void:
	match shape_mode:
		0:
			draw_circle(p, sz, c)
		1:
			var diamond := PackedVector2Array([
				p + Vector2(0, -sz), p + Vector2(sz, 0),
				p + Vector2(0, sz), p + Vector2(-sz, 0)
			])
			draw_colored_polygon(diamond, c)
		2:
			draw_rect(Rect2(p.x - sz * 0.7, p.y - sz * 0.7, sz * 1.4, sz * 1.4), c)
		3:
			draw_line(p - Vector2(sz * 2.2, 0), p + Vector2(sz * 2.2, 0), c, maxf(1.0, sz * 0.45), true)
		4:
			draw_line(p - Vector2(sz, 0), p + Vector2(sz, 0), c, maxf(1.0, sz * 0.35), true)
			draw_line(p - Vector2(0, sz), p + Vector2(0, sz), c, maxf(1.0, sz * 0.35), true)
		5:
			draw_arc(p, sz, 0, TAU, 12, c, maxf(1.0, sz * 0.25), true)


# ── ACTIONS ───────────────────────────────────────────────────────
func _do_splat() -> void:
	var t := _text_edit.text if _text_edit else "SIGNAL"
	_kick_generate(t, true)
	_shake = 0.55


func _do_boom() -> void:
	entrance = 1
	# force explode entrance UI state via regen then kick
	var t := _text_edit.text if _text_edit else "SIGNAL"
	await _generate_text(t, true)
	for i in range(count):
		var idx := i * STRIDE
		var dx: float = pts[idx] - CENTER.x
		var dy: float = pts[idx + 1] - CENTER.y
		var d := sqrt(dx * dx + dy * dy) + 0.01
		pts[idx + 12] += (dx / d) * (400.0 + randf() * 600.0)
		pts[idx + 13] += (dy / d) * (400.0 + randf() * 600.0)
	_shake = 1.4
	_status_text()


func _export_png() -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null:
		if _status:
			_status.text = "EXPORT FAIL"
		return
	DirAccess.make_dir_recursive_absolute("user://splat_exports")
	var ts := int(Time.get_unix_time_from_system())
	var path := "user://splat_exports/trailer_%d.png" % ts
	img.save_png(path)
	var desk := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var out := desk.path_join("splat_trailer_%d.png" % ts)
	img.save_png(out)
	if _status:
		_status.text = "SAVED  " + out
	print("[EXPORT] ", out)


# ── UI ────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -178
	panel.offset_left = 32
	panel.offset_right = -32
	panel.offset_bottom = -10
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.07, 0.94)
	style.border_color = Color(0.2, 0.25, 0.38, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)

	var title := Label.new()
	title.text = "SPLAT TRAILER LAB  ·  GODOT  ·  TYPE → SIZE → SHAPE → EXPLODE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	v.add_child(title)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	v.add_child(row1)

	_text_edit = LineEdit.new()
	_text_edit.text = "SIGNAL"
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.placeholder_text = "type your words…"
	_text_edit.add_theme_font_size_override("font_size", 18)
	_text_edit.text_submitted.connect(func(_t): _do_splat())
	row1.add_child(_text_edit)

	var b_splat := Button.new()
	b_splat.text = "SPLAT"
	b_splat.custom_minimum_size = Vector2(100, 40)
	b_splat.pressed.connect(_do_splat)
	row1.add_child(b_splat)

	var b_boom := Button.new()
	b_boom.text = "BOOM"
	b_boom.custom_minimum_size = Vector2(90, 40)
	b_boom.pressed.connect(func(): _do_boom())
	row1.add_child(b_boom)

	var b_png := Button.new()
	b_png.text = "PNG"
	b_png.custom_minimum_size = Vector2(70, 40)
	b_png.pressed.connect(func(): _export_png())
	row1.add_child(b_png)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)

	var lsz := Label.new()
	lsz.text = "SIZE"
	row2.add_child(lsz)
	_size_slider = HSlider.new()
	_size_slider.min_value = 0.3
	_size_slider.max_value = 4.0
	_size_slider.step = 0.05
	_size_slider.value = 1.0
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_slider.value_changed.connect(func(val):
		size_mul = val
		_status_text()
	)
	row2.add_child(_size_slider)

	var lct := Label.new()
	lct.text = "COUNT"
	row2.add_child(lct)
	_count_slider = HSlider.new()
	_count_slider.min_value = 3000
	_count_slider.max_value = float(MAX_PTS)
	_count_slider.step = 500
	_count_slider.value = 10000
	_count_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_count_slider)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	v.add_child(row3)
	for i in range(SHAPE_NAMES.size()):
		var b := Button.new()
		b.text = SHAPE_NAMES[i]
		b.toggle_mode = true
		b.button_pressed = (i == 0)
		var idx := i
		b.pressed.connect(func():
			shape_mode = idx
			for c in row3.get_children():
				if c is Button:
					c.button_pressed = (c == b)
			_status_text()
		)
		row3.add_child(b)

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 6)
	v.add_child(row4)
	for i in range(ENT_NAMES.size()):
		var b2 := Button.new()
		b2.text = ENT_NAMES[i]
		b2.toggle_mode = true
		b2.button_pressed = (i == 0)
		var idx2 := i
		b2.pressed.connect(func():
			entrance = idx2
			for c in row4.get_children():
				if c is Button:
					c.button_pressed = (c == b2)
			_do_splat()
		)
		row4.add_child(b2)

	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 6)
	v.add_child(row5)
	var bprev := Button.new()
	bprev.text = "◀ LOOK"
	row5.add_child(bprev)
	bprev.pressed.connect(func():
		look_i = (look_i - 1 + LOOKS.size()) % LOOKS.size()
		cam_mode = int(LOOKS[look_i].cam)
		_do_splat()
	)
	var bnext := Button.new()
	bnext.text = "LOOK ▶"
	row5.add_child(bnext)
	bnext.pressed.connect(func():
		look_i = (look_i + 1) % LOOKS.size()
		cam_mode = int(LOOKS[look_i].cam)
		_do_splat()
	)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	v.add_child(_status)


func _status_text() -> void:
	if _status == null:
		return
	_status.text = "%s  ·  %s  ·  %s  ·  size %.2f  ·  %d pts" % [
		LOOKS[look_i].name, ENT_NAMES[entrance], SHAPE_NAMES[shape_mode], size_mul, count
	]


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_SPACE:
				if ev.shift_pressed:
					_do_boom()
				else:
					_shake_blast()
			KEY_ENTER, KEY_KP_ENTER:
				_do_splat()
			KEY_LEFT:
				look_i = (look_i - 1 + LOOKS.size()) % LOOKS.size()
				cam_mode = int(LOOKS[look_i].cam)
				_do_splat()
			KEY_RIGHT:
				look_i = (look_i + 1) % LOOKS.size()
				cam_mode = int(LOOKS[look_i].cam)
				_do_splat()
			KEY_X:
				_export_png()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				shape_mode = ev.keycode - KEY_1
				_status_text()
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_dragging = ev.pressed
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = minf(cam_zoom * 1.08, 3.0)
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = maxf(cam_zoom / 1.08, 0.35)
	if ev is InputEventMouseMotion and _dragging:
		cam_off += ev.relative


func _shake_blast() -> void:
	_shake = 1.0
	for i in range(count):
		var idx := i * STRIDE
		var dx: float = pts[idx] - CENTER.x
		var dy: float = pts[idx + 1] - CENTER.y
		var d := sqrt(dx * dx + dy * dy) + 0.01
		pts[idx + 12] += (dx / d) * (200.0 + randf() * 300.0)
		pts[idx + 13] += (dy / d) * (200.0 + randf() * 300.0)
