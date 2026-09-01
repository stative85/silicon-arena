extends RefCounted

## ═══════════════════════════════════════════════════════════════════
## SPLAT LOADER — Reads splat data from multiple formats
## Returns a populated SplatData instance. No rendering, no motion.
## ═══════════════════════════════════════════════════════════════════

const SplatDataScript = preload("res://scripts/splat/splat_data.gd")

const ARENA_SIZE := Vector2(1540, 720)
const MAX_SPLATS := 50000

func load_auto(path: String) :
	## Auto-detect format by extension
	if path.ends_with(".json"):
		return load_packed_json(path)
	if path.ends_with(".bin") or path.ends_with(".splat"):
		return load_binary(path)
	return load_image(path)

# ── Packed JSON ───────────────────────────────────────────────────
func load_packed_json(path: String) :
	## Format: {"meta":{...}, "splats":[[x,y,z,sx,sy,r,g,b,a],...]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[SPLAT LOADER] Cannot open: %s" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var json = JSON.parse_string(text)
	if json == null or not json is Dictionary:
		print("[SPLAT LOADER] Invalid JSON: %s" % path)
		return null

	var raw_meta: Dictionary = json.get("meta", {})
	var raw_splats: Array = json.get("splats", [])
	if raw_splats.is_empty():
		print("[SPLAT LOADER] No splats in file")
		return null

	var data = SplatDataScript.new()
	data.meta["width"] = float(raw_meta.get("width", 1280))
	data.meta["height"] = float(raw_meta.get("height", 720))
	data.meta["name"] = str(raw_meta.get("name", "untitled"))
	data.meta["source"] = path

	var scale_x: float = ARENA_SIZE.x / float(data.meta["width"])
	var scale_y: float = ARENA_SIZE.y / float(data.meta["height"])
	var point_count := mini(raw_splats.size(), MAX_SPLATS)
	data.resize(point_count)

	var actual := 0
	for i in range(point_count):
		var s = raw_splats[i]
		if not s is Array or s.size() < 9:
			continue

		var px: float = float(s[0]) * scale_x
		var py: float = float(s[1]) * scale_y
		var pz: float = float(s[2])
		if pz > 1.0: pz /= 255.0  # quantized

		var sz: float = float(s[3])
		if sz > 10.0: sz /= 10.0

		var cr: float = float(s[5]); var cg: float = float(s[6])
		var cb: float = float(s[7]); var ca: float = float(s[8])
		if cr > 1.0 or cg > 1.0 or cb > 1.0 or ca > 1.0:
			cr /= 255.0; cg /= 255.0; cb /= 255.0; ca /= 255.0

		var layer := _z_to_layer(pz)
		data.set_point(actual, px, py, pz, clampf(sz, 1.0, 20.0),
			clampf(cr, 0, 1), clampf(cg, 0, 1), clampf(cb, 0, 1), clampf(ca, 0, 1), layer)
		actual += 1

	data.count = actual
	data.points.resize(actual * data.STRIDE)
	data.sort_by_layer()
	print("[SPLAT LOADER] %d points from JSON (%s)" % [actual, path.get_file()])
	return data

# ── Binary ────────────────────────────────────────────────────────
func load_binary(path: String) :
	## Format: [x:f32, y:f32, z:f32, r:u8, g:u8, b:u8, a:u8, size:f32] = 20 bytes
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[SPLAT LOADER] Cannot open: %s" % path)
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()

	var bpp := 20
	var point_count := mini(bytes.size() / bpp, MAX_SPLATS)
	if point_count == 0:
		return null

	var data = SplatDataScript.new()
	data.meta["source"] = path
	data.resize(point_count)

	for i in range(point_count):
		var off := i * bpp
		var px := bytes.decode_float(off)
		var py := bytes.decode_float(off + 4)
		var pz := bytes.decode_float(off + 8)
		var cr := float(bytes[off + 12]) / 255.0
		var cg := float(bytes[off + 13]) / 255.0
		var cb := float(bytes[off + 14]) / 255.0
		var ca := float(bytes[off + 15]) / 255.0
		var sz := bytes.decode_float(off + 16)

		# Remap normalized (-1..1) to arena space
		if px < 0.0 or py < 0.0:
			px = (px + 1.0) * 0.5 * ARENA_SIZE.x
			py = (py + 1.0) * 0.5 * ARENA_SIZE.y

		var layer := _z_to_layer(pz)
		data.set_point(i, px, py, pz, clampf(sz, 1.0, 20.0), cr, cg, cb, ca, layer)

	data.sort_by_layer()
	print("[SPLAT LOADER] %d points from binary (%s)" % [point_count, path.get_file()])
	return data

# ── Image decomposition ──────────────────────────────────────────
func load_image(path: String, target_count: int = 3000) :
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex = load(path) as Texture2D
		if tex: img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.new()
		if img.load(path) != OK: img = null
	if img == null:
		print("[SPLAT LOADER] Cannot load image: %s" % path)
		return null

	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var iw := img.get_width()
	var ih := img.get_height()
	if iw == 0 or ih == 0: return null

	var scale_x := ARENA_SIZE.x / float(iw)
	var scale_y := ARENA_SIZE.y / float(ih)
	target_count = clampi(target_count, 500, MAX_SPLATS)

	# Importance sampling
	var step := maxi(1, int(sqrt(float(iw * ih) / float(target_count * 4))))
	var candidates: Array = []  # [x, y, Color, weight, brightness]

	for y in range(0, ih, step):
		for x in range(0, iw, step):
			var c := img.get_pixel(x, y)
			if c.a < 0.1: continue
			var brightness := (c.r + c.g + c.b) / 3.0
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			var weight := brightness * 0.5 + sat * 0.3 + 0.2
			candidates.append([x, y, c, weight, brightness])

	candidates.sort_custom(func(a, b): return a[3] > b[3])

	var to_use := mini(candidates.size(), target_count)
	var data = SplatDataScript.new()
	data.meta["width"] = float(iw)
	data.meta["height"] = float(ih)
	data.meta["source"] = path
	data.resize(to_use)

	for i in range(to_use):
		var cand = candidates[i]
		var px: float = float(cand[0]) * scale_x + randf_range(-scale_x * 0.4, scale_x * 0.4)
		var py: float = float(cand[1]) * scale_y + randf_range(-scale_y * 0.4, scale_y * 0.4)
		var c: Color = cand[2]
		var bright: float = cand[4]
		var pz := 1.0 - bright
		var sz: float = lerpf(3.0, 8.0, 1.0 - bright) * maxf(scale_x, scale_y) * 0.3
		var layer := _z_to_layer(pz)
		data.set_point(i, px, py, pz, sz, c.r, c.g, c.b, c.a, layer)

	data.sort_by_layer()
	print("[SPLAT LOADER] %d points from image %dx%d (%s)" % [to_use, iw, ih, path.get_file()])
	return data

# ── Procedural generation (no image needed) ──────────────────────
func generate_procedural(point_count: int = 2000):
	## Creates a nebula-like splat cloud from pure math. No files needed.
	var data = SplatDataScript.new()
	data.meta["name"] = "procedural_nebula"
	data.meta["source"] = "generated"
	point_count = clampi(point_count, 200, MAX_SPLATS)
	data.resize(point_count)

	for i in range(point_count):
		# Cluster around center with gaussian-ish distribution
		var angle := randf() * TAU
		var dist := absf(randf() + randf() + randf()) / 3.0  # pseudo-gaussian 0..1
		var px: float = ARENA_SIZE.x * 0.5 + cos(angle) * dist * ARENA_SIZE.x * 0.45
		var py: float = ARENA_SIZE.y * 0.5 + sin(angle) * dist * ARENA_SIZE.y * 0.45
		var pz := dist  # center = near, edges = far

		# Color: nebula palette (purples, blues, cyans, pinks)
		var hue := fmod(angle / TAU + dist * 0.3 + randf() * 0.1, 1.0)
		var sat := 0.5 + randf() * 0.4
		var val := 0.4 + (1.0 - dist) * 0.5
		var c := Color.from_hsv(hue, sat, val)

		var sz := lerpf(3.0, 10.0, 1.0 - dist) + randf() * 2.0
		var layer := _z_to_layer(pz)
		data.set_point(i, px, py, pz, sz, c.r, c.g, c.b, 0.8, layer)

	data.sort_by_layer()
	print("[SPLAT LOADER] Generated %d procedural splats" % point_count)
	return data

# ── Helpers ───────────────────────────────────────────────────────
func _z_to_layer(z: float) -> int:
	if z < 0.3: return 2  # FG
	if z < 0.6: return 1  # MID
	return 0  # BG
