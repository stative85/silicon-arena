extends Node2D

## ═══════════════════════════════════════════════════════════════════
## SPLAT ENGINE — Public API / Coordinator
## This is the ONLY class external code should touch.
## Owns data, wires loader → motion → renderer.
## ═══════════════════════════════════════════════════════════════════

const LoaderScript = preload("res://scripts/splat/splat_loader.gd")
const MotionScript = preload("res://scripts/splat/splat_motion.gd")
const RendererScript = preload("res://scripts/splat/splat_renderer_mm.gd")

var _loader = null  # SplatLoader
var _motion = null  # SplatMotion
var _renderer = null # SplatRendererMM (Node2D)
var _data = null     # SplatData
var _time := 0.0
var _loaded := false

# ── Public state ──────────────────────────────────────────────────
var point_count: int:
	get: return int(_data.count) if _data else 0

var is_loaded: bool:
	get: return _loaded

# ── Reactive inputs (set these from outside) ──────────────────────
var doom_factor := 0.0:
	set(v):
		doom_factor = v
		if _renderer: _renderer.doom_factor = v
var heat_level := 0.0:
	set(v):
		heat_level = v
		if _renderer: _renderer.heat_level = v
var arena_focus := "normal":
	set(v):
		arena_focus = v
		if _renderer: _renderer.arena_focus = v

func _ready() -> void:
	_loader = LoaderScript.new()
	_motion = MotionScript.new()
	_renderer = RendererScript.new()
	add_child(_renderer)

# ── Loading ───────────────────────────────────────────────────────
func load_file(path: String) -> bool:
	var data = _loader.load_auto(path)
	if data == null:
		return false
	_data = data
	_renderer.setup(_data)
	_loaded = true
	_time = 0.0
	print("[SPLAT ENGINE] Loaded %d points from %s" % [_data.count, path.get_file()])
	return true

func load_from_folder(folder_path: String) -> bool:
	## Auto-load first compatible file from a directory
	var extensions: Array[String] = [".json", ".bin", ".splat", ".png", ".jpg"]
	print("[SPLAT ENGINE] Scanning folder: %s" % folder_path)
	if not DirAccess.dir_exists_absolute(folder_path):
		print("[SPLAT ENGINE] Folder does not exist: %s" % folder_path)
		return false
	var dir := DirAccess.open(folder_path)
	if dir == null:
		print("[SPLAT ENGINE] Cannot open folder: %s" % folder_path)
		return false
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			for ext: String in extensions:
				if fname.ends_with(ext):
					print("[SPLAT ENGINE] Found file: %s/%s" % [folder_path, fname])
					return load_file(folder_path + "/" + fname)
		fname = dir.get_next()
	print("[SPLAT ENGINE] No compatible files in: %s" % folder_path)
	return false

func generate_procedural(count: int = 2000) -> bool:
	var data = _loader.generate_procedural(count)
	if data == null:
		return false
	_data = data
	_renderer.setup(_data)
	_loaded = true
	_time = 0.0
	print("[SPLAT ENGINE] Generated %d procedural splats" % _data.count)
	return true

func clear() -> void:
	if _data:
		_data.clear()
	_loaded = false
	_time = 0.0

# ── Motion control ────────────────────────────────────────────────
func apply_preset(preset_name: String) -> void:
	_motion.apply_preset(preset_name)

func get_preset_names() -> Array[String]:
	return _motion.get_preset_names()

func set_motion_mode(m: int) -> void:
	_motion.mode = m

func set_motion_intensity(v: float) -> void:
	_motion.intensity = v

func set_motion_turbulence(v: float) -> void:
	_motion.turbulence = v

# ── Reactive triggers ─────────────────────────────────────────────
func trigger_scatter(strength: float = 1.0) -> void:
	_motion.scatter = clampf(strength, 0.0, 2.0)
	_renderer.camera_shake = clampf(strength * 0.8, 0.0, 2.0)

func trigger_beat(bass: float, mids: float = 0.0, highs: float = 0.0) -> void:
	_motion.beat = clampf(bass, 0.0, 1.0)
	_motion.mids = clampf(mids, 0.0, 1.0)
	_motion.highs = clampf(highs, 0.0, 1.0)
	_renderer.beat_intensity = clampf(bass, 0.0, 1.0)
	_renderer.mid_intensity = clampf(mids, 0.0, 1.0)
	_renderer.high_intensity = clampf(highs, 0.0, 1.0)

# ── Render control ────────────────────────────────────────────────
func set_render_mode(m: int) -> void:
	_renderer.render_mode = m

func set_layer_visible(layer: int, vis: bool) -> void:
	if layer >= 0 and layer < 3:
		_renderer.layer_visible[layer] = vis

func set_camera_offset(offset: Vector2) -> void:
	_renderer.camera_offset = offset

func set_camera_zoom(z: float) -> void:
	_renderer.camera_zoom = z

func get_camera_offset() -> Vector2:
	return _renderer.camera_offset

func get_camera_zoom() -> float:
	return _renderer.camera_zoom

# ── Export ─────────────────────────────────────────────────────────
func export_frame(viewport: Viewport) -> String:
	var image := viewport.get_texture().get_image()
	if image == null:
		return ""
	var dir_path := "user://splat_exports"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var ts := int(Time.get_unix_time_from_system())
	var file_path := "%s/splat_%d.png" % [dir_path, ts]
	image.save_png(file_path)
	print("[SPLAT ENGINE] Exported: %s" % file_path)
	return file_path

# ── Update loop ───────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _loaded or _data == null:
		return
	_time += delta
	_motion.decay(delta)
	_motion.simulate_points(_data.points, _data.count, _data.STRIDE, _time, delta)
