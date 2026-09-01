extends RefCounted

## ═══════════════════════════════════════════════════════════════════
## SPLAT DATA — Core data container
## Flat PackedFloat32Array with stride-based access.
## Zero GC pressure. GPU-portable.
## ═══════════════════════════════════════════════════════════════════

# Stride layout per point
const STRIDE := 12
const F_X := 0     # current position x
const F_Y := 1     # current position y
const F_Z := 2     # depth (0=near, 1=far)
const F_SZ := 3    # base size (radius)
const F_R := 4     # color red
const F_G := 5     # color green
const F_B := 6     # color blue
const F_A := 7     # color alpha
const F_OX := 8    # origin x (for spring return)
const F_OY := 9    # origin y (for spring return)
const F_PH := 10   # phase offset (unique per point, for wave variation)
const F_LY := 11   # layer (0=BG, 1=MID, 2=FG)

var points := PackedFloat32Array()
var count := 0

# Pre-sorted layer ranges: [start_index, end_index] per layer
# Avoids iterating full array 3x during render
var layer_ranges: Array = [Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0)]

var meta := {
	"width": 1280.0,
	"height": 720.0,
	"name": "untitled",
	"source": "",
}

func resize(new_count: int) -> void:
	count = new_count
	points.resize(count * STRIDE)

func clear() -> void:
	count = 0
	points.resize(0)
	layer_ranges = [Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0)]

func is_empty() -> bool:
	return count == 0

# ── Per-point accessors ───────────────────────────────────────────
func get_pos(i: int) -> Vector2:
	var idx := i * STRIDE
	return Vector2(points[idx + F_X], points[idx + F_Y])

func set_pos(i: int, pos: Vector2) -> void:
	var idx := i * STRIDE
	points[idx + F_X] = pos.x
	points[idx + F_Y] = pos.y

func get_origin(i: int) -> Vector2:
	var idx := i * STRIDE
	return Vector2(points[idx + F_OX], points[idx + F_OY])

func get_color(i: int) -> Color:
	var idx := i * STRIDE
	return Color(points[idx + F_R], points[idx + F_G], points[idx + F_B], points[idx + F_A])

func set_color(i: int, c: Color) -> void:
	var idx := i * STRIDE
	points[idx + F_R] = c.r; points[idx + F_G] = c.g
	points[idx + F_B] = c.b; points[idx + F_A] = c.a

func get_size(i: int) -> float:
	return points[i * STRIDE + F_SZ]

func get_z(i: int) -> float:
	return points[i * STRIDE + F_Z]

func get_phase(i: int) -> float:
	return points[i * STRIDE + F_PH]

func get_layer(i: int) -> int:
	return int(points[i * STRIDE + F_LY])

# ── Bulk operations ───────────────────────────────────────────────
func set_point(i: int, x: float, y: float, z: float, sz: float,
		r: float, g: float, b: float, a: float, layer: int) -> void:
	var idx := i * STRIDE
	points[idx + F_X] = x; points[idx + F_Y] = y; points[idx + F_Z] = z
	points[idx + F_SZ] = sz
	points[idx + F_R] = r; points[idx + F_G] = g; points[idx + F_B] = b; points[idx + F_A] = a
	points[idx + F_OX] = x; points[idx + F_OY] = y
	points[idx + F_PH] = randf() * TAU
	points[idx + F_LY] = float(layer)

func sort_by_layer() -> void:
	## Sort points so all layer-0 come first, then layer-1, then layer-2.
	## Enables single-pass rendering with layer_ranges.
	if count == 0:
		return

	# Count per layer
	var counts := [0, 0, 0]
	for i in range(count):
		var ly := clampi(int(points[i * STRIDE + F_LY]), 0, 2)
		counts[ly] += 1

	# Build output arrays per layer
	var buckets: Array[PackedFloat32Array] = [
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()
	]
	buckets[0].resize(counts[0] * STRIDE)
	buckets[1].resize(counts[1] * STRIDE)
	buckets[2].resize(counts[2] * STRIDE)
	var offsets := [0, 0, 0]

	for i in range(count):
		var idx := i * STRIDE
		var ly := clampi(int(points[idx + F_LY]), 0, 2)
		var dst: int = int(offsets[ly]) * STRIDE
		for f in range(STRIDE):
			buckets[ly][dst + f] = points[idx + f]
		offsets[ly] += 1

	# Merge back
	var pos := 0
	for ly in range(3):
		var start := pos
		for j in range(buckets[ly].size()):
			points[pos] = buckets[ly][j]
			pos += 1
		var end: int = start + int(counts[ly])
		layer_ranges[ly] = Vector2i(start / STRIDE, end)

	# Fix layer_ranges to be point indices, not byte offsets
	var running := 0
	for ly in range(3):
		layer_ranges[ly] = Vector2i(running, running + counts[ly])
		running += counts[ly]
