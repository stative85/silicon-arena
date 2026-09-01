extends RefCounted

## ═══════════════════════════════════════════════════════════════════
## SPLAT MOTION — Motion field simulation
## Pure data transform. No rendering. No loading.
## ═══════════════════════════════════════════════════════════════════

const SplatDataScript = preload("res://scripts/splat/splat_data.gd")

const ARENA_CENTER := Vector2(770, 360)
const ARENA_SIZE := Vector2(1540, 720)

enum Mode { DRIFT, VORTEX, COLLAPSE, EXPLOSION, BASS_PULSE, NOISE, NONE }

var mode: int = Mode.DRIFT
var intensity := 1.0
var turbulence := 0.3
var spring := 0.02  # pull-to-origin

# Layer parallax multipliers
var layer_scale := [0.5, 1.0, 1.5]

# Reactive inputs (set externally each frame)
var beat := 0.0
var mids := 0.0
var highs := 0.0
var scatter := 0.0
var doom := 0.0

# Presets
const PRESETS := {
	"subtle_drift": { "mode": Mode.DRIFT, "intensity": 0.4, "turbulence": 0.1 },
	"vortex":       { "mode": Mode.VORTEX, "intensity": 0.8, "turbulence": 0.4 },
	"doom_approach": { "mode": Mode.COLLAPSE, "intensity": 1.2, "turbulence": 0.5 },
	"bass_pulse":   { "mode": Mode.BASS_PULSE, "intensity": 1.0, "turbulence": 0.3 },
	"explosion":    { "mode": Mode.EXPLOSION, "intensity": 1.5, "turbulence": 0.6 },
	"nebula":       { "mode": Mode.NOISE, "intensity": 0.6, "turbulence": 0.8 },
}

func apply_preset(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	var p: Dictionary = PRESETS[preset_name]
	mode = p.get("mode", Mode.DRIFT)
	intensity = p.get("intensity", 1.0)
	turbulence = p.get("turbulence", 0.3)

func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for k in PRESETS:
		names.append(k)
	return names

func decay(delta: float) -> void:
	scatter = maxf(scatter - delta * 2.0, 0.0)
	beat = maxf(beat - delta * 4.0, 0.0)
	mids = maxf(mids - delta * 3.0, 0.0)
	highs = maxf(highs - delta * 5.0, 0.0)

func simulate_points(pts: PackedFloat32Array, count: int, stride: int, time: float, delta: float) -> void:
	## Update all point positions based on current motion mode
	var cnt := count
	var dt60 := delta * 60.0  # normalize to 60fps

	for i in range(cnt):
		var idx := i * stride
		var px: float = pts[idx + 0]  # X
		var py: float = pts[idx + 1]  # Y
		var ox: float = pts[idx + 8]  # OX
		var oy: float = pts[idx + 9]  # OY
		var phase: float = pts[idx + 10]  # PH
		var ly: int = clampi(int(pts[idx + 11]), 0, 2)  # LY
		var lscale: float = layer_scale[ly]
		var inten: float = intensity * lscale

		var dx := 0.0
		var dy := 0.0

		match mode:
			Mode.DRIFT:
				dx = sin(time * 0.7 + phase) * 3.0 * inten
				dy = cos(time * 0.5 + phase * 1.3) * 2.0 * inten
				dx += sin(time * 1.8 + phase * 2.7) * turbulence * 2.0
				dy += cos(time * 2.1 + phase * 3.1) * turbulence * 1.5

			Mode.VORTEX:
				var tcx := ARENA_CENTER.x - ox
				var tcy := ARENA_CENTER.y - oy
				var angle := atan2(tcy, tcx) + time * 0.5 * inten
				var dist := sqrt(tcx * tcx + tcy * tcy)
				dx = cos(angle) * dist * 0.03 * inten
				dy = sin(angle) * dist * 0.03 * inten
				dx += sin(time * 3.0 + phase) * turbulence * 3.0
				dy += cos(time * 2.5 + phase) * turbulence * 3.0

			Mode.COLLAPSE:
				var tcx := ARENA_CENTER.x - px
				var tcy := ARENA_CENTER.y - py
				var d := sqrt(tcx * tcx + tcy * tcy)
				if d > 0.01:
					dx = (tcx / d) * inten * 0.5
					dy = (tcy / d) * inten * 0.5
				dx += sin(time * 2.0 + phase) * turbulence * 2.0
				dy += cos(time * 1.7 + phase) * turbulence * 2.0

			Mode.EXPLOSION:
				var fcx := ox - ARENA_CENTER.x
				var fcy := oy - ARENA_CENTER.y
				var d := sqrt(fcx * fcx + fcy * fcy)
				if d > 0.01:
					dx = (fcx / d) * inten * 2.0 * (1.0 + sin(time * 3.0 + phase) * turbulence)
					dy = (fcy / d) * inten * 2.0 * (1.0 + cos(time * 2.5 + phase) * turbulence)

			Mode.BASS_PULSE:
				var fcx := ox - ARENA_CENTER.x
				var fcy := oy - ARENA_CENTER.y
				var d := sqrt(fcx * fcx + fcy * fcy)
				if d > 0.01:
					var pulse_str := beat * inten * 3.0
					dx = (fcx / d) * pulse_str
					dy = (fcy / d) * pulse_str
				dx += sin(time * 1.5 + phase) * 1.5
				dy += cos(time * 1.2 + phase) * 1.0

			Mode.NOISE:
				dx = sin(px * 0.01 + time * 0.8) * cos(py * 0.013 + time * 0.6) * 8.0 * inten * turbulence
				dy = cos(px * 0.012 + time * 0.7) * sin(py * 0.009 + time * 0.9) * 6.0 * inten * turbulence

			Mode.NONE:
				pass

		# Spring return
		dx += (ox - px) * spring
		dy += (oy - py) * spring

		# Scatter override
		if scatter > 0.01:
			var fcx := px - ARENA_CENTER.x
			var fcy := py - ARENA_CENTER.y
			var d := sqrt(fcx * fcx + fcy * fcy)
			if d > 0.01:
				dx += (fcx / d) * scatter * 120.0
				dy += (fcy / d) * scatter * 80.0

		pts[idx + 0] = clampf(px + dx * dt60, -50, ARENA_SIZE.x + 50)
		pts[idx + 1] = clampf(py + dy * dt60, -50, ARENA_SIZE.y + 50)
