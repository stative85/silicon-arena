extends Node2D

## ═══════════════════════════════════════════════════════════════════
## SPLAT RENDERER — Draw-based renderer
## Uses _draw() for reliable rendering. Works on any GPU.
## ═══════════════════════════════════════════════════════════════════

const ARENA_SIZE := Vector2(1540, 720)

# Render modes
enum RenderMode { SOFT_GLOW, HARD_DOT, ADDITIVE }
var render_mode: int = RenderMode.SOFT_GLOW

# Layer visibility
var layer_visible := [true, true, true]

# Camera
var camera_offset := Vector2.ZERO
var camera_zoom := 1.0
var camera_shake := 0.0
var _shake_offset := Vector2.ZERO

# Reactivity
var doom_factor := 0.0
var heat_level := 0.0
var beat_intensity := 0.0
var mid_intensity := 0.0
var high_intensity := 0.0
var arena_focus := "normal"

# Internal
var _data = null
var _time := 0.0
var _initialized := false

func setup(data) -> void:
	_data = data
	_initialized = true
	print("[SPLAT RENDER] Ready — %d points" % _data.count)
	queue_redraw()

func _process(delta: float) -> void:
	if not _initialized:
		return
	_time += delta

	camera_shake = maxf(camera_shake - delta * 3.0, 0.0)
	if camera_shake > 0.01:
		_shake_offset = Vector2(
			randf_range(-1, 1) * camera_shake * 8.0,
			randf_range(-1, 1) * camera_shake * 6.0)
	else:
		_shake_offset = Vector2.ZERO

	queue_redraw()

func _draw() -> void:
	if not _initialized or _data == null:
		return

	var pts: PackedFloat32Array = _data.points
	var cnt: int = _data.count
	var stride: int = int(_data.STRIDE)

	if cnt == 0:
		return

	# Dark base
	draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color(0.015, 0.015, 0.03, 0.95))

	# Focus tint
	var fr := 1.0; var fg := 1.0; var fb := 1.0
	match arena_focus:
		"beef": fr = 1.0; fg = 0.85; fb = 0.8
		"agape": fr = 0.85; fg = 0.9; fb = 1.0

	# Draw all points (layer sorted in data already)
	for i in range(cnt):
		var idx := i * stride
		var ly := int(pts[idx + 11])
		if not layer_visible[ly]:
			continue

		var px: float = pts[idx + 0] + _shake_offset.x + camera_offset.x
		var py: float = pts[idx + 1] + _shake_offset.y + camera_offset.y
		var sz: float = pts[idx + 3] * camera_zoom
		var cr: float = pts[idx + 4]
		var cg: float = pts[idx + 5]
		var cb: float = pts[idx + 6]
		var ca: float = pts[idx + 7]
		var phase: float = pts[idx + 10]

		# Beat size
		sz *= 1.0 + beat_intensity * 0.5

		# High flicker
		if high_intensity > 0.1:
			ca *= 1.0 - high_intensity * 0.3 * (0.5 + 0.5 * sin(_time * 20.0 + phase))

		# Doom shift
		if doom_factor > 0.05:
			cr = lerpf(cr, 0.9, doom_factor * 0.4)
			cg = lerpf(cg, 0.08, doom_factor * 0.3)
			cb = lerpf(cb, 0.05, doom_factor * 0.3)

		# Heat
		if heat_level > 0.1:
			cr = minf(cr + heat_level * 0.15, 1.0)

		# Mid jitter
		if mid_intensity > 0.05:
			px += sin(_time * 12.0 + phase) * mid_intensity * 4.0
			py += cos(_time * 10.0 + phase) * mid_intensity * 3.0

		# Focus tint
		cr *= fr; cg *= fg; cb *= fb

		var pos := Vector2(px, py)

		match render_mode:
			RenderMode.SOFT_GLOW:
				draw_circle(pos, sz * 1.4, Color(cr, cg, cb, ca * 0.12))
				draw_circle(pos, sz, Color(cr, cg, cb, ca * 0.4))
				draw_circle(pos, sz * 0.35, Color(
					minf(cr + 0.15, 1.0), minf(cg + 0.15, 1.0),
					minf(cb + 0.15, 1.0), ca * 0.65))
			RenderMode.HARD_DOT:
				draw_circle(pos, sz * 0.6, Color(cr, cg, cb, ca * 0.85))
			RenderMode.ADDITIVE:
				var boost := 1.0 + beat_intensity * 0.5
				draw_circle(pos, sz * 1.3, Color(
					minf(cr * boost, 1.0), minf(cg * boost, 1.0),
					minf(cb * boost, 1.0), ca * 0.2))
				draw_circle(pos, sz * 0.5, Color(
					minf(cr * boost + 0.2, 1.0), minf(cg * boost + 0.2, 1.0),
					minf(cb * boost + 0.2, 1.0), ca * 0.6))
