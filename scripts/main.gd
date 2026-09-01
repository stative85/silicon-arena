extends Node2D
class_name Main

# ── Inner Classes ──────────────────────────────────────

class TurnManager extends Node:
	signal turn_started(agent, topic, rules, angle)
	signal stall_detected(agent_name, elapsed)

	var turn_index := 0
	var waiting := false
	var waiting_since_msec := 0
	# _epoch is the arena's logical clock. Any callback captured at epoch N
	# is only valid while the epoch is still N. Every destructive boundary
	# (preset swap, roster rebuild, builder open, stall, reset, turn start)
	# must bump the epoch via advance_epoch() BEFORE tearing state down.
	var _epoch := 0
	var waiting_timeout_sec := 30.0

	var turn_interval_sec := 5.0
	var request_wait_buffer_sec := 10.0

	func advance_epoch(reason: String = "") -> int:
		_epoch += 1
		if reason != "":
			print("[EPOCH] %d (%s)" % [_epoch, reason])
		return _epoch

	func reset():
		turn_index = 0
		waiting = false
		waiting_since_msec = 0
		advance_epoch("reset")

	func get_next_agent_index(agents: Array) -> int:
		if agents.is_empty():
			return -1
			
		var now_msec = Time.get_ticks_msec()
		var scanned := 0
		
		while scanned < agents.size():
			var agent = agents[turn_index % agents.size()]
			if not agent.get("broken", false) and int(agent.get("cooldown_until_msec", 0)) <= now_msec:
				return turn_index % agents.size()
			
			scanned += 1
			turn_index += 1
		
		return -1

	func start_waiting(timeout: float):
		_last_progress_bucket = 0
		waiting = true
		waiting_since_msec = Time.get_ticks_msec()
		waiting_timeout_sec = timeout
		advance_epoch("start_waiting")

	func stop_waiting():
		waiting = false
		waiting_since_msec = 0

	## Emitted while a turn is still outstanding, so a cold model load does not
	## look like a freeze. Measured swaps on an 8GB card are 18-38s
	## (docs/BENCHMARK_8GB.md) and the app used to print nothing for that whole
	## window.
	signal turn_progress(agent_name: String, elapsed_sec: float)

	var _last_progress_bucket := 0

	func check_stall(agents: Array) -> bool:
		if not waiting:
			_last_progress_bucket = 0
			return false

		var elapsed_sec := float(Time.get_ticks_msec() - waiting_since_msec) / 1000.0

		# Heartbeat every 10s so a long JIT load is visibly progressing.
		var bucket := int(elapsed_sec / 10.0)
		if bucket > _last_progress_bucket and bucket > 0:
			_last_progress_bucket = bucket
			var who := "Unknown"
			if not agents.is_empty():
				who = agents[turn_index % agents.size()].name
			turn_progress.emit(who, elapsed_sec)

		if elapsed_sec >= waiting_timeout_sec:
			var agent_name = "Unknown"
			if not agents.is_empty():
				agent_name = agents[turn_index % agents.size()].name
			
			stall_detected.emit(agent_name, elapsed_sec)
			stop_waiting()
			turn_index += 1
			return true
		return false

	func advance_turn():
		turn_index += 1



class ArenaVisuals extends Node2D:
	const GRID_SIZE := 32
	const ARENA_SIZE := Vector2(1540, 720)
	const TILESET_PATH := "res://assets/craftpix-net-958568-free-cursed-land-top-down-pixel-art-tileset/PNG/"

	var agents: Array = []
	var agreement_matrix: Dictionary = {}
	var ego_auras: Dictionary = {}
	var doom_meter: float = 0.0
	var _ground_tiles: Array = []  # Array[AtlasTexture] — deterministic per-cell variety
	var _decorations_spawned := false
	# Dynamic zones
	var _flicker_spots: Array = []  # [{pos, seed, next_time, alpha}]
	var _time_acc := 0.0
	# Agent trails
	var _trail_points: Array = []  # [{pos, color, age}]
	# Speaking glow
	var _speaking_agents: Dictionary = {}  # name -> fade (1.0 = just spoke)
	# New visual systems (set by Main)
	var speech_particles: Array = []
	var crown_agent_name := ""
	var desperation_agent_name := ""
	var desperation_pulse := 0.0
	var arena_focus := "normal"  # "normal", "beef", "agape"
	var agape_override_active := false
	# Shockwave rings — expanding impact circles
	var shockwaves: Array = []  # [{pos, color, radius, max_radius, life}]

	func _ready():
		_load_ground_tile()
		call_deferred("_spawn_decorations")
		# Seed random flicker spots in empty regions
		for k in range(8):
			_flicker_spots.append({
				"pos": Vector2(randf_range(100, 1200), randf_range(300, 680)),
				"seed": randf() * 1000.0,
				"next_time": randf_range(3.0, 12.0),
				"alpha": 0.0,
			})

	func _process(delta: float):
		_time_acc += delta
		# Update flicker spots
		for spot in _flicker_spots:
			if spot.alpha > 0.0:
				spot.alpha = maxf(spot.alpha - delta * 1.2, 0.0)
			elif _time_acc > spot.next_time:
				spot.alpha = randf_range(0.18, 0.35)
				spot.next_time = _time_acc + randf_range(2.5, 8.0)
		# Age trail points, remove old ones
		var i := _trail_points.size() - 1
		while i >= 0:
			_trail_points[i].age += delta
			if _trail_points[i].age > 3.0:
				_trail_points.remove_at(i)
			i -= 1
		# Fade speaking glow
		var expired := []
		for aname in _speaking_agents:
			_speaking_agents[aname] -= delta * 0.5
			if _speaking_agents[aname] <= 0.0:
				expired.append(aname)
		for aname in expired:
			_speaking_agents.erase(aname)
		# Drop trail points for each agent every few frames
		if Engine.get_frames_drawn() % 3 == 0:
			for agent in agents:
				add_trail_point(agent.node.position, agent.get("color", Color.WHITE))
		# Update shockwaves
		var sw_expired := []
		for sw in shockwaves:
			sw.life -= delta
			sw.radius += delta * sw.max_radius * 1.8  # expand outward
			if sw.life <= 0.0:
				sw_expired.append(sw)
		for sw in sw_expired:
			shockwaves.erase(sw)
		# Always redraw
		queue_redraw()

	func _load_ground_tile():
		var path := TILESET_PATH + "Ground.png"
		if not ResourceLoader.exists(path):
			return
		var ground_sheet = load(path) as Texture2D
		if ground_sheet == null:
			return
		# Single verified clean base tile — variety comes from per-cell tint jitter
		# in _draw(), not from multiple regions (avoids mismatched edges).
		_ground_tiles.clear()
		var at := AtlasTexture.new()
		at.atlas = ground_sheet
		at.region = Rect2(0, 160, 64, 64)
		_ground_tiles.append(at)

	func _draw_castle():
		# Procedural castle silhouette across the top of the arena.
		# Colors: dark stone with subtle top-edge highlight.
		var stone := Color(0.10, 0.09, 0.13, 0.88)
		var stone_edge := Color(0.22, 0.20, 0.26, 0.95)
		var wall_top := 38.0
		var wall_bottom := 118.0
		var wall_w := ARENA_SIZE.x
		# Main curtain wall
		draw_rect(Rect2(0, wall_top, wall_w, wall_bottom - wall_top), stone)
		# Top edge highlight (1px band)
		draw_rect(Rect2(0, wall_top, wall_w, 2), stone_edge)
		# Crenellations (merlons) — alternating blocks sticking up from wall_top
		var merlon_w := 48.0
		var merlon_h := 18.0
		var gap_w := 24.0
		var cx := 0.0
		while cx < wall_w:
			draw_rect(Rect2(cx, wall_top - merlon_h, merlon_w, merlon_h), stone)
			draw_rect(Rect2(cx, wall_top - merlon_h, merlon_w, 2), stone_edge)
			cx += merlon_w + gap_w
		# Two flanking towers
		var towers := [
			Vector2(160, 14),    # left tower x, top_y
			Vector2(wall_w - 260, 14),  # right tower
		]
		var tower_w := 100.0
		var tower_bottom := 150.0
		for tpos in towers:
			var tx: float = tpos.x
			var ty: float = tpos.y
			# Tower body
			draw_rect(Rect2(tx, ty, tower_w, tower_bottom - ty), stone)
			draw_rect(Rect2(tx, ty, tower_w, 2), stone_edge)
			# Tower top crenellations (3 merlons per tower)
			var tm_w := 22.0
			var tm_gap := 12.0
			var tm_h := 14.0
			var tm_x := tx + 6.0
			for mi in range(3):
				draw_rect(Rect2(tm_x, ty - tm_h, tm_w, tm_h), stone)
				draw_rect(Rect2(tm_x, ty - tm_h, tm_w, 2), stone_edge)
				tm_x += tm_w + tm_gap
			# Tower window (small slit, glow)
			var win_x := tx + tower_w * 0.5 - 3.0
			var win_y := ty + 40.0
			draw_rect(Rect2(win_x, win_y, 6, 14), Color(0.95, 0.55, 0.15, 0.85))
		# Central gate arch (cut-out using ground-colored rect)
		var gate_w := 110.0
		var gate_h := 70.0
		var gate_x := wall_w * 0.5 - gate_w * 0.5
		var gate_y := wall_bottom - gate_h
		draw_rect(Rect2(gate_x, gate_y, gate_w, gate_h), Color(0.04, 0.05, 0.08, 0.88))
		# Gate torch glow left + right
		draw_circle(Vector2(gate_x - 8, gate_y + 10), 10.0, Color(1.0, 0.55, 0.15, 0.35))
		draw_circle(Vector2(gate_x + gate_w + 8, gate_y + 10), 10.0, Color(1.0, 0.55, 0.15, 0.35))

		# --- SIDE WALLS (left + right) ---
		var side_w := 30.0
		# Left wall
		draw_rect(Rect2(0, wall_bottom, side_w, ARENA_SIZE.y - wall_bottom), stone)
		draw_rect(Rect2(side_w - 2, wall_bottom, 2, ARENA_SIZE.y - wall_bottom), stone_edge)
		# Right wall
		draw_rect(Rect2(ARENA_SIZE.x - side_w, wall_bottom, side_w, ARENA_SIZE.y - wall_bottom), stone)
		draw_rect(Rect2(ARENA_SIZE.x - side_w, wall_bottom, 2, ARENA_SIZE.y - wall_bottom), stone_edge)
		# Side wall torch glows (spaced vertically)
		for ty in [250.0, 450.0, 620.0]:
			draw_circle(Vector2(side_w + 4, ty), 8.0, Color(1.0, 0.55, 0.15, 0.25))
			draw_circle(Vector2(ARENA_SIZE.x - side_w - 4, ty), 8.0, Color(1.0, 0.55, 0.15, 0.25))

		# --- BOTTOM WALL ---
		var bottom_h := 30.0
		var bottom_y := ARENA_SIZE.y - bottom_h
		draw_rect(Rect2(side_w, bottom_y, ARENA_SIZE.x - side_w * 2, bottom_h), stone)
		draw_rect(Rect2(side_w, bottom_y, ARENA_SIZE.x - side_w * 2, 2), stone_edge)
		# Bottom wall crenellations (facing inward / upward)
		var bcx := side_w
		var bm_w := 36.0
		var bm_h := 12.0
		var bm_gap := 20.0
		while bcx < ARENA_SIZE.x - side_w:
			draw_rect(Rect2(bcx, bottom_y - bm_h, bm_w, bm_h), stone)
			draw_rect(Rect2(bcx, bottom_y - bm_h, bm_w, 2), stone_edge)
			bcx += bm_w + bm_gap

	func _spawn_decorations():
		if _decorations_spawned:
			return
		_decorations_spawned = true

		# --- ASSET POOL: every decoration type with variant counts ---
		# Format: [prefix, shadow_set, variant_count]
		var asset_pool := [
			["Bones_shadow1_", 11], ["Bones_shadow2_", 11],
			["Veins_shadow1_", 4], ["Veins_shadow2_", 4],
			["Pustules_shadow1_", 3], ["Pustules_shadow2_", 3],
			["Rock1_shadow1_", 5], ["Rock2_shadow2_", 5],
			["Rock3_shadow1_", 6], ["Rock3_shadow2_", 6],
			["Rock_eyes_shadow1_", 5], ["Rock_eyes_shadow2_", 5],
			["Meat_flower_shadow1_", 3], ["Meat_flower_shadow2_", 3],
			["Eye_plant_shadow1_", 3], ["Eye_plant_shadow2_", 3],
			["Spike_plant_shadow1_", 4], ["Spike_plant_shadow2_", 4],
			["Tentacle_plant_shadow1_", 3], ["Tentacle_plant_shadow2_", 3],
			["Tubular_plant_shadow1_", 3], ["Tubular_plant_shadow2_", 3],
			["Jaws_plant_shadow1_", 3], ["Jaws_plant_shadow2_", 3],
			["Many_eyes_plant_shadow1_", 3], ["Many_eyes_plant_shadow2_", 3],
			["Fetus_shadow1_", 3], ["Fetus_shadow2_", 3],
			["Ruins_shadow1_", 6], ["Ruins_shadow2_", 5],
		]

		# Build flat list of all available paths (full res:// paths)
		var all_paths: Array = []
		for entry in asset_pool:
			var prefix: String = entry[0]
			var count: int = entry[1]
			for vi in range(1, count + 1):
				var p = TILESET_PATH + "Objects_separetely/%s%d.png" % [prefix, vi]
				if ResourceLoader.exists(p):
					all_paths.append(p)
		all_paths.shuffle()

		# --- MUSHROOM & ENCHANTED FOREST POOL ---
		var mushroom_paths: Array = []
		# Transparent mushroom renders (50 numbered PNGs, pick a spread)
		var shroom_base := "res://assets/PNG/without background/"
		for si in [1, 2, 3, 5, 7, 8, 10, 12, 14, 15, 17, 18, 20, 22, 24, 25, 27, 28, 30, 32, 33, 35, 37, 38, 40, 42, 44, 45, 47, 48, 50]:
			var sp := shroom_base + "%d.png" % si
			if ResourceLoader.exists(sp):
				mushroom_paths.append(sp)
		# Enchanted forest mushrooms + small trees (no shadow versions)
		var forest_base := "res://assets/PNG/Assets_no_shadow/"
		var forest_items := [
			"Beige_green_mushroom1.png", "Beige_green_mushroom2.png", "Beige_green_mushroom3.png",
			"Chanterelles1.png", "Chanterelles2.png", "Chanterelles3.png",
			"White-red_mushroom1.png", "White-red_mushroom2.png", "White-red_mushroom3.png",
			"Blue-green_balls_tree1.png", "Blue-green_balls_tree2.png", "Blue-green_balls_tree3.png",
			"Light_balls_tree1.png", "Light_balls_tree2.png", "Light_balls_tree3.png",
			"Swirling tree1.png", "Swirling tree2.png", "Swirling tree3.png",
			"Willow1.png", "Willow2.png", "Willow3.png",
			"Curved_tree1.png", "Curved_tree2.png", "Curved_tree3.png",
			"Luminous_tree1.png", "Luminous_tree2.png", "Luminous_tree3.png", "Luminous_tree4.png",
			"Living gazebo1.png", "Living gazebo2.png",
			"White_tree1.png", "White_tree2.png",
		]
		for fi in forest_items:
			var fpath: String = forest_base + fi
			if ResourceLoader.exists(fpath):
				mushroom_paths.append(fpath)
		mushroom_paths.shuffle()

		# --- BEEF EXCLUSION ZONE: center stage kept clear ---
		# Beef cinematic area: roughly x 500-1000, y 260-460
		var beef_zone := Rect2(500, 260, 500, 200)

		# --- PLACEMENT ZONES ---
		# Each zone: [Rect2 region, count, scale_min, scale_max, alpha, z_index]
		var zones := [
			# ZONE A: Bottom strip (y 560-700) — most visible, dense
			[Rect2(40, 560, 1460, 140), 22, 0.5, 1.0, 0.55, 0],
			# ZONE B: Left wing (x 40-480, y 300-560) — fills left of beef zone
			[Rect2(40, 300, 440, 260), 14, 0.45, 0.9, 0.5, 0],
			# ZONE C: Right wing (x 1020-1500, y 300-560) — fills right of beef zone
			[Rect2(1020, 300, 480, 260), 14, 0.45, 0.9, 0.5, 0],
			# ZONE D: Top strip (y 40-260) — behind UI, large + atmospheric
			[Rect2(40, 40, 1460, 220), 18, 0.7, 1.5, 0.38, -1],
			# ZONE E: Far edges (corners + flanks) — big moody shapes
			[Rect2(40, 160, 140, 500), 7, 0.8, 1.4, 0.45, -1],  # left edge
			[Rect2(1360, 160, 140, 500), 7, 0.8, 1.4, 0.45, -1],  # right edge
			# ZONE F: Foreground scatter (y 600-700) — small, in front of agents
			[Rect2(80, 620, 1380, 80), 10, 0.3, 0.6, 0.42, 2],
			# ZONE G: Mid-left corridor (between left edge and beef zone)
			[Rect2(200, 300, 280, 240), 8, 0.4, 0.8, 0.42, 0],
			# ZONE H: Mid-right corridor (between beef zone and right edge)
			[Rect2(1040, 300, 280, 240), 8, 0.4, 0.8, 0.42, 0],
			# ZONE I: Upper mid (above beef zone, below top strip)
			[Rect2(200, 160, 1100, 100), 10, 0.5, 1.0, 0.35, -1],
			# ZONE J: Lower mid (below beef zone, above bottom strip)
			[Rect2(200, 460, 1100, 100), 8, 0.4, 0.8, 0.45, 0],
		]

		var path_idx := 0
		var placed := 0
		var placed_positions: Array = []  # track to avoid overlap

		for zone in zones:
			var rect: Rect2 = zone[0]
			var count: int = zone[1]
			var scale_min: float = zone[2]
			var scale_max: float = zone[3]
			var alpha: float = zone[4]
			var z: int = zone[5]

			for _k in range(count):
				if path_idx >= all_paths.size():
					all_paths.shuffle()
					path_idx = 0

				# Find a valid position (not in beef zone, not too close to existing)
				var pos := Vector2.ZERO
				var valid := false
				for _try in range(12):
					pos = Vector2(
						randf_range(rect.position.x, rect.position.x + rect.size.x),
						randf_range(rect.position.y, rect.position.y + rect.size.y)
					)
					# Check beef zone exclusion
					if beef_zone.has_point(pos):
						continue
					# Check minimum spacing (28px from other placed objects)
					var too_close := false
					for existing in placed_positions:
						if pos.distance_to(existing) < 28.0:
							too_close = true
							break
					if not too_close:
						valid = true
						break

				if not valid:
					continue

				var deco_path: String = all_paths[path_idx]
				path_idx += 1
				var tex = load(deco_path) as Texture2D
				if tex == null:
					continue

				var spr = Sprite2D.new()
				spr.texture = tex
				spr.position = pos + Vector2(0, randf_range(-6.0, 6.0))
				var s = randf_range(scale_min, scale_max)
				spr.scale = Vector2(s, s)
				spr.z_index = z
				spr.modulate = Color(1.0, 1.0, 1.0, alpha + randf_range(-0.08, 0.08))
				# Random horizontal flip for variety
				spr.flip_h = randf() > 0.5
				add_child(spr)
				placed += 1
				placed_positions.append(pos)

		# --- MUSHROOM & FOREST SCATTER ---
		# These are high-res renders so scale way down; scattered across arena edges
		var shroom_zones := [
			# Bottom corners — mushroom clusters (dense)
			[Rect2(40, 540, 420, 150), 9, 0.06, 0.14, 0.50, 0],
			[Rect2(1080, 540, 420, 150), 9, 0.06, 0.14, 0.50, 0],
			# Left and right flanks
			[Rect2(40, 260, 340, 280), 8, 0.05, 0.12, 0.40, -1],
			[Rect2(1160, 260, 340, 280), 8, 0.05, 0.12, 0.40, -1],
			# Top atmospheric — faded forest canopy hints
			[Rect2(60, 30, 1400, 220), 12, 0.07, 0.18, 0.28, -2],
			# Foreground tiny mushroom scatter
			[Rect2(80, 620, 1380, 80), 8, 0.03, 0.08, 0.42, 2],
			# Mid-arena undergrowth — small plants filling the gaps
			[Rect2(300, 300, 200, 200), 5, 0.04, 0.09, 0.35, -1],
			[Rect2(1000, 300, 200, 200), 5, 0.04, 0.09, 0.35, -1],
			# Deep corners — large atmospheric trees barely visible
			[Rect2(20, 20, 100, 200), 3, 0.12, 0.22, 0.22, -3],
			[Rect2(1420, 20, 100, 200), 3, 0.12, 0.22, 0.22, -3],
		]

		var shroom_idx := 0
		for sz in shroom_zones:
			var rect: Rect2 = sz[0]
			var count: int = sz[1]
			var scale_min: float = sz[2]
			var scale_max: float = sz[3]
			var alpha: float = sz[4]
			var z: int = sz[5]

			for _k in range(count):
				if mushroom_paths.is_empty():
					break
				if shroom_idx >= mushroom_paths.size():
					mushroom_paths.shuffle()
					shroom_idx = 0

				var pos := Vector2.ZERO
				var valid := false
				for _try in range(12):
					pos = Vector2(
						randf_range(rect.position.x, rect.position.x + rect.size.x),
						randf_range(rect.position.y, rect.position.y + rect.size.y)
					)
					if beef_zone.has_point(pos):
						continue
					var too_close := false
					for existing in placed_positions:
						if pos.distance_to(existing) < 32.0:
							too_close = true
							break
					if not too_close:
						valid = true
						break

				if not valid:
					continue

				var stex = load(mushroom_paths[shroom_idx]) as Texture2D
				shroom_idx += 1
				if stex == null:
					continue

				var spr = Sprite2D.new()
				spr.texture = stex
				spr.position = pos + Vector2(0, randf_range(-4.0, 4.0))
				var s = randf_range(scale_min, scale_max)
				spr.scale = Vector2(s, s)
				spr.z_index = z
				spr.modulate = Color(1.0, 1.0, 1.0, alpha + randf_range(-0.06, 0.06))
				spr.flip_h = randf() > 0.5
				add_child(spr)
				placed += 1
				placed_positions.append(pos)

		# --- FOCAL ANCHORS: landmark pieces (hand-placed, never in beef zone) ---
		var focal_placements := [
			# Original cursed land anchors
			[TILESET_PATH + "Objects_separetely/Ruins_shadow1_6.png", Vector2(130, 590), 1.7, -1, 0.55],
			[TILESET_PATH + "Objects_separetely/Ruins_shadow1_5.png", Vector2(1150, 630), 1.5, -1, 0.55],
			[TILESET_PATH + "Objects_separetely/Rock_eyes_shadow1_3.png", Vector2(380, 650), 1.2, 0, 0.55],
			# Enchanted forest anchors — luminous trees as arena pillars
			[forest_base + "Luminous_tree1.png", Vector2(80, 320), 0.22, -2, 0.35],
			[forest_base + "Luminous_tree3.png", Vector2(1430, 350), 0.20, -2, 0.35],
			[forest_base + "Luminous_tree4.png", Vector2(750, 40), 0.15, -3, 0.25],
			# Ent guardians flanking the beef zone
			[forest_base + "Ent_man.png", Vector2(1350, 580), 0.18, -1, 0.40],
			[forest_base + "Ent_woman.png", Vector2(440, 560), 0.16, -1, 0.38],
			# Mega trees — ancient canopy framing the arena top
			[forest_base + "Mega_tree1.png", Vector2(200, 20), 0.11, -3, 0.22],
			[forest_base + "Mega_tree2.png", Vector2(1300, 10), 0.10, -3, 0.20],
			# Four tree idols — cardinal guardians of the arena
			[forest_base + "Tree_idol_dragon.png", Vector2(60, 600), 0.16, 0, 0.45],
			[forest_base + "Tree_idol_wolf.png", Vector2(1440, 620), 0.15, 0, 0.42],
			[forest_base + "Tree_idol_deer.png", Vector2(40, 180), 0.14, -2, 0.30],
			[forest_base + "Tree_idol_human.png", Vector2(1460, 180), 0.13, -2, 0.28],
			# Curved + white trees for deeper forest atmosphere
			[forest_base + "Curved_tree1.png", Vector2(300, 80), 0.12, -3, 0.22],
			[forest_base + "Curved_tree3.png", Vector2(1200, 60), 0.11, -3, 0.20],
			[forest_base + "White_tree1.png", Vector2(1100, 100), 0.10, -3, 0.18],
			[forest_base + "White_tree2.png", Vector2(400, 100), 0.10, -3, 0.18],
			# Living gazebos — mystical structures at arena flanks
			[forest_base + "Living gazebo1.png", Vector2(160, 450), 0.14, -1, 0.38],
			[forest_base + "Living gazebo2.png", Vector2(1320, 440), 0.13, -1, 0.36],
			# Willows — drooping canopy framing mid-arena
			[forest_base + "Willow1.png", Vector2(240, 200), 0.13, -2, 0.28],
			[forest_base + "Willow2.png", Vector2(1250, 190), 0.12, -2, 0.26],
			[forest_base + "Willow3.png", Vector2(740, 680), 0.10, 1, 0.35],
			# Extra cursed land mid-arena scatter
			[TILESET_PATH + "Objects_separetely/Ruins_shadow2_3.png", Vector2(1300, 580), 1.3, -1, 0.48],
			[TILESET_PATH + "Objects_separetely/Ruins_shadow1_3.png", Vector2(250, 660), 1.1, 0, 0.50],
			[TILESET_PATH + "Objects_separetely/Rock3_shadow1_4.png", Vector2(1400, 660), 1.0, 0, 0.48],
			[TILESET_PATH + "Objects_separetely/Bones_shadow1_8.png", Vector2(700, 660), 0.9, 0, 0.45],
			[TILESET_PATH + "Objects_separetely/Tentacle_plant_shadow1_2.png", Vector2(480, 470), 0.8, -1, 0.40],
			[TILESET_PATH + "Objects_separetely/Eye_plant_shadow1_2.png", Vector2(1100, 470), 0.8, -1, 0.40],
			# Swirling trees deep in corners
			[forest_base + "Swirling tree1.png", Vector2(30, 500), 0.11, -2, 0.25],
			[forest_base + "Swirling tree3.png", Vector2(1500, 500), 0.10, -2, 0.23],
		]
		for fpl in focal_placements:
			var fp_path: String = fpl[0]
			if not ResourceLoader.exists(fp_path):
				continue
			var tex = load(fp_path) as Texture2D
			if tex == null:
				continue
			var spr = Sprite2D.new()
			spr.texture = tex
			spr.position = fpl[1] + Vector2(0, randf_range(-4.0, 4.0))
			var fs: float = fpl[2]
			spr.scale = Vector2(fs, fs)
			spr.z_index = fpl[3]
			spr.modulate = Color(1.0, 1.0, 1.0, fpl[4])
			add_child(spr)
			placed += 1

		print("[DECO] Procedural placement: %d objects (%d mushroom/forest) across arena" % [placed, placed - path_idx])

	func update_state(new_agents: Array, new_matrix: Dictionary, new_auras: Dictionary, new_doom: float):
		agents = new_agents
		agreement_matrix = new_matrix
		ego_auras = new_auras
		doom_meter = new_doom

	func mark_speaking(agent_name: String):
		_speaking_agents[agent_name] = 1.0

	func add_trail_point(pos: Vector2, color: Color):
		_trail_points.append({"pos": pos, "color": color, "age": 0.0})

	func _draw():
		# Background — tiled ground texture or fallback dark rect
		if _ground_tiles.size() > 0:
			# Dark base first so tiles blend nicely
			draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color(0.04, 0.05, 0.08))
			var tile_size := Vector2(64, 64)
			var base_tile = _ground_tiles[0]
			var gx := 0
			for x in range(0, int(ARENA_SIZE.x), int(tile_size.x)):
				var gy := 0
				for y in range(0, int(ARENA_SIZE.y), int(tile_size.y)):
					# Deterministic per-cell near-white modulate — subtle wear jitter.
					# Each channel 0.92..1.00 → up to 8% darkening, brown stays brown.
					var h := ((gx * 73856093) ^ (gy * 19349663)) & 0x7FFFFFFF
					var r_jit := 0.92 + ((h % 17) / 16.0) * 0.08
					var g_jit := 0.92 + (((h >> 4) % 17) / 16.0) * 0.08
					var b_jit := 0.92 + (((h >> 8) % 17) / 16.0) * 0.08
					draw_texture_rect(base_tile, Rect2(Vector2(x, y), tile_size), false, Color(r_jit, g_jit, b_jit, 0.75))
					gy += 1
				gx += 1
		else:
			draw_rect(Rect2(Vector2.ZERO, ARENA_SIZE), Color(0.06, 0.07, 0.1))

		# --- CASTLE SILHOUETTE (background backdrop) ---
		_draw_castle()

		# Subtle grid overlay (dimmer than before to let tiles show through)
		for x in range(0, int(ARENA_SIZE.x), GRID_SIZE):
			draw_line(Vector2(x, 0), Vector2(x, ARENA_SIZE.y), Color(0.12, 0.15, 0.22, 0.3), 1.0)
		for y in range(0, int(ARENA_SIZE.y), GRID_SIZE):
			draw_line(Vector2(0, y), Vector2(ARENA_SIZE.x, y), Color(0.12, 0.15, 0.22, 0.3), 1.0)

		var t := _time_acc
		var is_doom := doom_meter > 0.5

		# --- AGENT TRAILS ---
		for trail in _trail_points:
			var fade = 1.0 - (trail.age / 3.0)
			if fade > 0.01:
				var c = trail.color
				var trail_alpha = fade * 0.15
				draw_circle(trail.pos, 4.0 + fade * 3.0, Color(c.r, c.g, c.b, trail_alpha))

		# --- DYNAMIC ZONE 1: Breathing ground ---
		# Subtle brightness pulses in sparse areas (lower third + center lanes)
		var breath_spots := [
			Vector2(400, 550), Vector2(700, 480), Vector2(1000, 600),
			Vector2(250, 450), Vector2(850, 380), Vector2(550, 650),
			Vector2(150, 580), Vector2(950, 500), Vector2(600, 350),
		]
		for bp in breath_spots:
			var speed = 0.6 + doom_meter * 2.0
			var phase = sin(t * speed + bp.x * 0.01 + bp.y * 0.007) * 0.5 + 0.5
			var ba = phase * (0.12 + doom_meter * 0.15)
			if ba > 0.02:
				var br: float = lerp(0.15, 0.5, doom_meter)
				var bg: float = lerp(0.22, 0.05, doom_meter)
				var bb: float = lerp(0.4, 0.1, doom_meter)
				draw_circle(bp, 70.0 + phase * 25.0, Color(br, bg, bb, ba))

		# --- DYNAMIC ZONE 2: Agent aura zones + speaking glow ---
		for agent in agents:
			var apos = agent.node.position
			var pulse = sin(t * 2.0 + apos.x * 0.02) * 0.5 + 0.5
			var c = agent.get("color", Color.WHITE)
			# Speaking glow — bright burst that fades
			var speak_fade = _speaking_agents.get(agent.name, 0.0)
			var speak_boost = speak_fade * 0.25
			# Outer soft ring
			draw_circle(apos, 55.0 + pulse * 15.0 + speak_fade * 20.0, Color(c.r, c.g, c.b, 0.08 + pulse * 0.06 + speak_boost))
			# Inner warm spot
			draw_circle(apos, 28.0 + pulse * 8.0 + speak_fade * 12.0, Color(c.r, c.g, c.b, 0.12 + pulse * 0.08 + speak_boost * 1.5))
			# Speaking flash ring
			if speak_fade > 0.1:
				draw_arc(apos, 40.0 + speak_fade * 30.0, 0, TAU, 32, Color(c.r, c.g, c.b, speak_fade * 0.4), 2.0)

		# --- DYNAMIC ZONE 3: Event flickers (doom-reactive) ---
		for spot in _flicker_spots:
			if spot.alpha > 0.01:
				var flick_size = 14.0 + spot.alpha * 40.0 + doom_meter * 20.0
				var fr: float = lerp(0.4, 0.9, doom_meter)
				var fg: float = lerp(0.55, 0.1, doom_meter)
				var fb: float = lerp(0.85, 0.15, doom_meter)
				draw_circle(spot.pos, flick_size, Color(fr, fg, fb, spot.alpha * 1.5))
				draw_circle(spot.pos, flick_size * 0.5, Color(fr + 0.2, fg + 0.15, fb + 0.15, spot.alpha))

		# --- SPEECH PARTICLES (suppressed during beef) ---
		if arena_focus != "beef":
			for p in speech_particles:
				var fade = p.life / p.max_life
				if fade > 0.01:
					var c = p.color
					draw_circle(p.pos, 3.0 + fade * 4.0, Color(c.r, c.g, c.b, fade * 0.7))
					draw_circle(p.pos, 1.5 + fade * 2.0, Color(minf(c.r + 0.3, 1.0), minf(c.g + 0.3, 1.0), minf(c.b + 0.3, 1.0), fade * 0.9))

		# --- CROWN for dominant agent ---
		if crown_agent_name != "":
			for agent in agents:
				if agent.name == crown_agent_name:
					var cpos = agent.node.position + Vector2(0, -60)
					var crown_pulse = sin(t * 3.0) * 0.5 + 0.5
					# Golden glow behind crown
					draw_circle(cpos, 18.0 + crown_pulse * 6.0, Color(1.0, 0.85, 0.2, 0.15 + crown_pulse * 0.1))
					# Crown shape — three triangles
					var cw := 14.0
					var ch := 10.0
					for ci in range(3):
						var cx = cpos.x - cw + ci * cw
						var tip = Vector2(cx, cpos.y - ch - crown_pulse * 3.0)
						var bl = Vector2(cx - cw * 0.4, cpos.y)
						var br = Vector2(cx + cw * 0.4, cpos.y)
						draw_colored_polygon([tip, bl, br], Color(1.0, 0.85, 0.2, 0.8 + crown_pulse * 0.2))
					# Base band
					draw_rect(Rect2(cpos.x - cw, cpos.y, cw * 2.0, 4.0), Color(1.0, 0.75, 0.1, 0.9))
					break

		# --- DESPERATION MODE glow for losing agent ---
		if desperation_agent_name != "":
			for agent in agents:
				if agent.name == desperation_agent_name:
					var dpos = agent.node.position
					var dp = sin(desperation_pulse) * 0.5 + 0.5
					# Red pulsing ring
					draw_arc(dpos, 35.0 + dp * 10.0, 0, TAU, 32, Color(1.0, 0.15, 0.1, 0.3 + dp * 0.3), 2.5)
					draw_arc(dpos, 25.0 + dp * 5.0, 0, TAU, 24, Color(1.0, 0.3, 0.1, 0.2 + dp * 0.2), 1.5)
					break

		# --- SHOCKWAVE RINGS ---
		for sw in shockwaves:
			if sw.life > 0.0:
				var fade = clampf(sw.life / 0.6, 0.0, 1.0)
				var c = sw.color
				# Outer ring
				draw_arc(sw.pos, sw.radius, 0, TAU, 48, Color(c.r, c.g, c.b, fade * 0.5), 3.0)
				# Inner ring (brighter, smaller)
				draw_arc(sw.pos, sw.radius * 0.7, 0, TAU, 36, Color(minf(c.r + 0.3, 1.0), minf(c.g + 0.3, 1.0), minf(c.b + 0.3, 1.0), fade * 0.3), 1.5)
				# Fill disc (very faint)
				draw_circle(sw.pos, sw.radius * 0.3, Color(c.r, c.g, c.b, fade * 0.08))

		# Alliance/rivalry lines (faded during beef to reduce clutter)
		var line_alpha_mult := 0.2 if arena_focus == "beef" else 1.0
		for i in range(agents.size()):
			for j in range(i + 1, agents.size()):
				var a = agents[i]
				var b = agents[j]
				var key_ab = a.name + "->" + b.name
				var key_ba = b.name + "->" + a.name
				var combined = (agreement_matrix.get(key_ab, 0.0) + agreement_matrix.get(key_ba, 0.0)) / 2.0
				if absf(combined) > 0.1:
					var line_color: Color
					if agape_override_active:
						# During Agape Override: all lines pulse bright cyan
						var agape_pulse = (sin(t * 4.0 + float(i + j) * 0.5) + 1.0) / 2.0
						line_color = Color(0.0, 1.0, 0.92, clampf(0.3 + agape_pulse * 0.5, 0.1, 0.8) * line_alpha_mult)
					elif combined > 0:
						line_color = Color(0.2, 0.8, 0.4, clampf(combined, 0.1, 0.6) * line_alpha_mult)
						# Strong alliance: shared aura glow at midpoint
						if combined > 0.4 and arena_focus != "beef":
							var mid = (a.node.position + b.node.position) / 2.0
							var glow_pulse = sin(t * 2.5 + mid.x * 0.01) * 0.5 + 0.5
							var ac = a.get("color", Color.WHITE)
							var bc = b.get("color", Color.WHITE)
							var blend = ac.lerp(bc, 0.5)
							draw_circle(mid, 30.0 + glow_pulse * 15.0, Color(blend.r, blend.g, blend.b, 0.08 + glow_pulse * 0.06))
					else:
						line_color = Color(0.9, 0.2, 0.2, clampf(absf(combined), 0.1, 0.4) * line_alpha_mult)
						# Strong rivalry: crackling segments (only outside beef)
						if absf(combined) > 0.3 and arena_focus != "beef":
							var segments := 6
							var prev_pt = a.node.position
							for seg in range(1, segments + 1):
								var frac = float(seg) / float(segments)
								var base_pt = a.node.position.lerp(b.node.position, frac)
								if seg < segments:
									base_pt += Vector2(randf_range(-8, 8), randf_range(-8, 8))
								draw_line(prev_pt, base_pt, Color(1.0, 0.3, 0.15, 0.4 + absf(combined) * 0.3), 1.5)
								prev_pt = base_pt
					draw_line(a.node.position, b.node.position, line_color, 1.5 + absf(combined) * 2.0)

		# Ego boost pulsing halos
		var now_ms = Time.get_ticks_msec()
		for aura_name in ego_auras:
			var aura = ego_auras[aura_name]
			if now_ms > aura.expire_time:
				continue
				
			for agent in agents:
				if agent.name == aura_name:
					var pos = agent.node.position
					var pulse = (sin(now_ms * 0.005) + 1.0) / 2.0
					var remaining = float(aura.expire_time - now_ms) / 20000.0
					var base_alpha = 0.15 + pulse * 0.25
					var alpha = base_alpha * remaining
					var c = aura.color
					
					draw_arc(pos, 38 + pulse * 8, 0, TAU, 48, Color(c.r, c.g, c.b, alpha * 0.4), 3.0)
					draw_arc(pos, 28 + pulse * 5, 0, TAU, 36, Color(c.r, c.g, c.b, alpha * 0.6), 2.0)
					draw_arc(pos, 18 + pulse * 3, 0, TAU, 24, Color(c.r, c.g, c.b, alpha), 1.5)
					break

		# Silent failure doom bar
		if doom_meter > 0.0:
			var bar_y := ARENA_SIZE.y - 18.0
			var bar_w := (ARENA_SIZE.x - 60.0) * doom_meter
			draw_rect(Rect2(30, bar_y, ARENA_SIZE.x - 60.0, 10), Color(0.12, 0.12, 0.15))
			var doom_r = lerpf(0.6, 1.0, doom_meter)
			var doom_g = lerpf(0.15, 0.0, doom_meter)
			var doom_pulse = (sin(now_ms * 0.004 * doom_meter * 3.0) + 1.0) / 2.0
			var doom_alpha = lerpf(0.5, 0.9, doom_pulse * doom_meter)
			draw_rect(Rect2(30, bar_y, bar_w, 10), Color(doom_r, doom_g, 0.05, doom_alpha))
			draw_rect(Rect2(30, bar_y, ARENA_SIZE.x - 60.0, 10), Color(0.4, 0.1, 0.1, 0.5), false, 1.0)



class TemplateGallery extends ColorRect:
	## Modal overlay wrapper: full-screen dark backdrop + centered panel.
	## Click the backdrop to close. The panel itself blocks clicks through.
	signal template_applied(template_id)
	signal close_requested

	func _init():
		_build_ui()

	func _build_ui():
		visible = false
		# Full-screen dark overlay that blocks all interaction behind it
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		color = Color(0.0, 0.0, 0.0, 0.6)
		mouse_filter = Control.MOUSE_FILTER_STOP
		z_index = 50

		# Clicking the dark backdrop closes the gallery
		gui_input.connect(_on_backdrop_input)

		# Centered panel container
		var panel = PanelContainer.new()
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		panel.custom_minimum_size = Vector2(900, 560)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.04, 0.06, 0.98)
		style.border_color = Color(0.98, 0.89, 0.42, 0.8)
		style.set_border_width_all(2)
		style.corner_radius_top_left = 20
		style.corner_radius_top_right = 20
		style.corner_radius_bottom_left = 20
		style.corner_radius_bottom_right = 20
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 20
		style.content_margin_bottom = 20
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)

		var root = VBoxContainer.new()
		root.add_theme_constant_override("separation", 15)
		panel.add_child(root)

		var header = HBoxContainer.new()
		root.add_child(header)

		var title = Label.new()
		title.text = "BADASS CONVERSATION TEMPLATES"
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Color(0.98, 0.89, 0.42))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)

		var close_btn = Button.new()
		close_btn.text = "X"
		close_btn.pressed.connect(func(): close_requested.emit())
		header.add_child(close_btn)

		var scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(scroll)

		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 20)
		grid.add_theme_constant_override("v_separation", 20)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		for t in TemplateManager.TEMPLATES:
			var card = _make_template_card(t)
			grid.add_child(card)

	func _on_backdrop_input(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_requested.emit()

	func _make_template_card(template: Dictionary) -> PanelContainer:
		var card = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.1, 0.15, 0.9)
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.content_margin_left = 15
		style.content_margin_right = 15
		style.content_margin_top = 15
		style.content_margin_bottom = 15
		card.add_theme_stylebox_override("panel", style)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 8)
		card.add_child(vbox)

		var label = Label.new()
		label.text = template.label
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.33, 0.85, 0.67))
		vbox.add_child(label)

		var desc = Label.new()
		desc.text = template.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		vbox.add_child(desc)

		var apply_btn = Button.new()
		apply_btn.text = "APPLY TEMPLATE"
		apply_btn.pressed.connect(func(): template_applied.emit(template.id))
		vbox.add_child(apply_btn)

		return card



class SpriteFactory extends RefCounted:
	const BASE_PATH = "res://"

	# Map of character keys to their directory paths (legacy CraftPix sprites)
	const CHAR_PATHS = {
		"orc": "craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Orc/PNG/PNG Sequences/",
		"ogre": "craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Ogre/PNG/PNG Sequences/",
		"goblin": "craftpix-064112-free-orc-ogre-and-goblin-chibi-2d-game-sprites/Goblin/PNG/PNG Sequences/",
		"golem_1": "craftpix-891123-free-golems-chibi-2d-game-sprites2/Golem_1/PNG/PNG Sequences/",
		"skeleton_1": "craftpix-net-140672-free-chibi-skeleton-warrior-character-sprites/Skeleton_Warrior_1/PNG/PNG Sequences/",
		"necromancer_1": "craftpix-net-935193-free-chibi-necromancer-of-the-shadow-character-sprites/Necromancer_of_the_Shadow_1/PNG/PNG Sequences/",
		# The packs ship three variants each; only _1 was ever wired, leaving
		# six fully-animated characters (17 animation sets apiece) unused on
		# disk. Verified present before adding — no speculative paths.
		"golem_2": "craftpix-891123-free-golems-chibi-2d-game-sprites2/Golem_2/PNG/PNG Sequences/",
		"golem_3": "craftpix-891123-free-golems-chibi-2d-game-sprites2/Golem_3/PNG/PNG Sequences/",
		"skeleton_2": "craftpix-net-140672-free-chibi-skeleton-warrior-character-sprites/Skeleton_Warrior_2/PNG/PNG Sequences/",
		"skeleton_3": "craftpix-net-140672-free-chibi-skeleton-warrior-character-sprites/Skeleton_Warrior_3/PNG/PNG Sequences/",
		"necromancer_2": "craftpix-net-935193-free-chibi-necromancer-of-the-shadow-character-sprites/Necromancer_of_the_Shadow_2/PNG/PNG Sequences/",
		"necromancer_3": "craftpix-net-935193-free-chibi-necromancer-of-the-shadow-character-sprites/Necromancer_of_the_Shadow_3/PNG/PNG Sequences/"
	}

	# Sprite sheet characters — composited from layered 512x512 sheets (8x8 grid, 64px cells)
	# p1 row map: 0=idle, 1=idle_back, 2=walk, 3=walk_back, 4-5=poses, 6=action, 7=fall
	const SHEET_CELL := 64
	const SHEET_COLS := 8
	const SHEET_CHARS = {
		# --- p1 pack: unarmed civilians ---
		"analyst": {
			"layers": [
				"assets/characters/char_a_p1/char_a_p1_0bas_humn_v00.png",
				"assets/characters/char_a_p1/1out/char_a_p1_1out_fstr_v01.png",
				"assets/characters/char_a_p1/4har/char_a_p1_4har_bob1_v01.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"enforcer": {
			"layers": [
				"assets/characters/char_a_p1/char_a_p1_0bas_humn_v02.png",
				"assets/characters/char_a_p1/1out/char_a_p1_1out_pfpn_v02.png",
				"assets/characters/char_a_p1/4har/char_a_p1_4har_dap1_v03.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"scout": {
			"layers": [
				"assets/characters/char_a_p1/char_a_p1_0bas_humn_v04.png",
				"assets/characters/char_a_p1/1out/char_a_p1_1out_fstr_v03.png",
				"assets/characters/char_a_p1/4har/char_a_p1_4har_bob1_v05.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"mystic": {
			"layers": [
				"assets/characters/char_a_p1/char_a_p1_0bas_humn_v06.png",
				"assets/characters/char_a_p1/1out/char_a_p1_1out_pfpn_v04.png",
				"assets/characters/char_a_p1/4har/char_a_p1_4har_dap1_v07.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"rogue": {
			"layers": [
				"assets/characters/char_a_p1/char_a_p1_0bas_humn_v08.png",
				"assets/characters/char_a_p1/1out/char_a_p1_1out_fstr_v05.png",
				"assets/characters/char_a_p1/4har/char_a_p1_4har_bob1_v09.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"warden": {
			"layers": [
				"assets/characters/char_a_p1/char_a_p1_0bas_humn_v10.png",
				"assets/characters/char_a_p1/1out/char_a_p1_1out_pfpn_v05.png",
				"assets/characters/char_a_p1/4har/char_a_p1_4har_dap1_v11.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		# --- pONE1 pack: armed warriors (swords, axes, shields) ---
		"gladiator": {
			"layers": [
				"assets/characters/char_a_pONE1/char_a_pONE1_0bas_humn_v02.png",
				"assets/characters/char_a_pONE1/1out/char_a_pONE1_1out_boxr_v01.png",
				"assets/characters/char_a_pONE1/4har/char_a_pONE1_4har_bob1_v05.png",
				"assets/characters/char_a_pONE1/5hat/char_a_pONE1_5hat_pnty_v02.png",
				"assets/characters/char_a_pONE1/6tla/char_a_pONE1_6tla_sw01_v01.png",
				"assets/characters/char_a_pONE1/7tlb/char_a_pONE1_7tlb_sh01_v01.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"berserker": {
			"layers": [
				"assets/characters/char_a_pONE1/char_a_pONE1_0bas_humn_v06.png",
				"assets/characters/char_a_pONE1/1out/char_a_pONE1_1out_fstr_v03.png",
				"assets/characters/char_a_pONE1/4har/char_a_pONE1_4har_dap1_v03.png",
				"assets/characters/char_a_pONE1/6tla/char_a_pONE1_6tla_ax01_v03.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		# --- pONE2 pack: second wave warriors ---
		"paladin": {
			"layers": [
				"assets/characters/char_a_pONE2/char_a_pONE2_0bas_humn_v00.png",
				"assets/characters/char_a_pONE2/1out/char_a_pONE2_1out_pfpn_v01.png",
				"assets/characters/char_a_pONE2/4har/char_a_pONE2_4har_bob1_v01.png",
				"assets/characters/char_a_pONE2/5hat/char_a_pONE2_5hat_pfht_v01.png",
				"assets/characters/char_a_pONE2/6tla/char_a_pONE2_6tla_mc01_v01.png",
				"assets/characters/char_a_pONE2/7tlb/char_a_pONE2_7tlb_sh02_v01.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"ranger": {
			"layers": [
				"assets/characters/char_a_pONE2/char_a_pONE2_0bas_humn_v04.png",
				"assets/characters/char_a_pONE2/1out/char_a_pONE2_1out_fstr_v03.png",
				"assets/characters/char_a_pONE2/4har/char_a_pONE2_4har_dap1_v07.png",
				"assets/characters/char_a_pONE2/5hat/char_a_pONE2_5hat_pnty_v03.png",
				"assets/characters/char_a_pONE2/6tla/char_a_pONE2_6tla_sw01_v03.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		# --- pONE3 pack: third wave warriors ---
		"knight": {
			"layers": [
				"assets/characters/char_a_pONE3/char_a_pONE3_0bas_humn_v01.png",
				"assets/characters/char_a_pONE3/1out/char_a_pONE3_1out_pfpn_v04.png",
				"assets/characters/char_a_pONE3/4har/char_a_pONE3_4har_bob1_v08.png",
				"assets/characters/char_a_pONE3/5hat/char_a_pONE3_5hat_pfht_v04.png",
				"assets/characters/char_a_pONE3/6tla/char_a_pONE3_6tla_sw01_v02.png",
				"assets/characters/char_a_pONE3/7tlb/char_a_pONE3_7tlb_sh03_v02.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
		"champion": {
			"layers": [
				"assets/characters/char_a_pONE3/char_a_pONE3_0bas_humn_v08.png",
				"assets/characters/char_a_pONE3/1out/char_a_pONE3_1out_fstr_v05.png",
				"assets/characters/char_a_pONE3/4har/char_a_pONE3_4har_dap1_v11.png",
				"assets/characters/char_a_pONE3/5hat/char_a_pONE3_5hat_pnty_v05.png",
				"assets/characters/char_a_pONE3/6tla/char_a_pONE3_6tla_ax01_v04.png",
				"assets/characters/char_a_pONE3/7tlb/char_a_pONE3_7tlb_sh01_v04.png",
			],
			"idle_row": 4, "walk_row": 6, "talk_row": 0, "frames": 8,
		},
	}

	# Model-family → character type mapping. Each LLM family gets a visual identity.
	# Armed warriors go to the heavy hitters; civilians to the lighter models.
	const MODEL_CHAR_MAP = {
		# Qwen family → analyst (scholarly, precise)
		"qwen": "analyst",
		# Gemma family → paladin (holy warrior, principled)
		"gemma": "paladin",
		# Llama/Meta family → gladiator (arena-born fighter)
		"llama": "gladiator",
		# DeepSeek family → mystic (deep thinker)
		"deepseek": "mystic",
		# Mistral family → ranger (swift, sharp)
		"mistral": "ranger",
		# SmolLM → scout (small but quick)
		"smol": "scout",
		# Grok family → berserker (aggressive, unfiltered)
		"grok": "berserker",
		# Granite/IBM → knight (solid, armored)
		"granite": "knight",
		# Reverb/Ozone → rogue (chaotic energy)
		"reverb": "rogue",
		"ozone": "rogue",
		# Phi/Microsoft → warden (guarded, methodical)
		"phi": "warden",
		# Deckard → champion (almost-human warrior king)
		"deckard": "champion",
		# Wizard/Vicuna → enforcer (bold, declarative)
		"wizard": "enforcer",
		"vicuna": "enforcer",
		# Nemotron/NVIDIA → knight (industrial strength)
		"nemotron": "knight",
		# S1/SimpleScaling → mystic (reasoning model)
		"simplescaling": "mystic",
		"s1-": "mystic",
		# LFM/Liquid → scout (experimental, nimble)
		"lfm": "scout",
		"liquid": "scout",
		# GPT distills → enforcer
		"gpt": "enforcer",
		# Rogue model → rogue (obviously)
		"rogue": "rogue",
		# Ministral → ranger (Mistral subfamily)
		"ministral": "ranger",
		# Nemo → ranger (Mistral subfamily)
		"nemo": "ranger",
	}

	# Resolve model ID → character type. Checks model string against MODEL_CHAR_MAP keys.
	# Falls back to round-robin from all available types if no family match.
	static func char_for_model(model_id: String, fallback_index: int) -> String:
		var lower := model_id.to_lower()
		for key in MODEL_CHAR_MAP:
			if lower.find(key) >= 0:
				return MODEL_CHAR_MAP[key]
		# No family match — round-robin through all character types
		var all_types := SHEET_CHARS.keys() + CHAR_PATHS.keys()
		return all_types[fallback_index % all_types.size()]

	static func make_sprite_frames(char_type: String) -> SpriteFrames:
		var sf = SpriteFrames.new()
		if sf.has_animation("default"):
			sf.remove_animation("default")

		# Try new sheet-based characters first
		if SHEET_CHARS.has(char_type):
			return _make_sheet_sprite_frames(SHEET_CHARS[char_type])

		# Fall back to legacy CraftPix directory-based characters
		var path_suffix = CHAR_PATHS.get(char_type, "")
		if path_suffix == "":
			return _make_default_frames()

		var full_path = BASE_PATH + path_suffix

		# 0 = every frame. Real counts are Walking 24 / Idle 18 / Slashing 12
		# across all twelve CraftPix characters, verified by tools/sprite_scan.py.
		# Speeds differ so idle breathes instead of vibrating at walk cadence.
		_add_animation_from_dir(sf, "walk", full_path + "Walking/", 0, 14.0)
		_add_animation_from_dir(sf, "idle", full_path + "Idle/", 0, 9.0)
		_add_animation_from_dir(sf, "talk", full_path + "Slashing/", 0, 12.0)

		return sf

	static func _make_sheet_sprite_frames(char_def: Dictionary) -> SpriteFrames:
		var sf = SpriteFrames.new()
		if sf.has_animation("default"):
			sf.remove_animation("default")

		# Composite all layers into a single image
		var composite: Image = null
		for layer_path in char_def.layers:
			var full_path = BASE_PATH + layer_path
			var img := Image.new()
			var err = img.load(ProjectSettings.globalize_path(full_path))
			if err != OK:
				print("[SpriteFactory] Failed to load layer: %s" % layer_path)
				continue
			# Force a common format before blending. blend_rect between images
			# of differing formats silently produces garbage or drops alpha,
			# which shows up as flat-coloured or invisible characters.
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			if composite == null:
				composite = img.duplicate()
			else:
				if composite.get_size() != img.get_size():
					print("[SpriteFactory] layer size mismatch %s (%s vs %s) - skipped"
						% [layer_path, img.get_size(), composite.get_size()])
					continue
				composite.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)

		if composite == null:
			return _make_default_frames()

		# Create a texture from the composited image
		var sheet_tex := ImageTexture.create_from_image(composite)
		# 8, not 7. These sheets are a full 8x8 grid (512/64) and every cell is
		# populated -- verified by pixel count. The old default silently threw
		# away the last frame of every animation, so each loop hitched.
		var frame_count: int = char_def.get("frames", 8)

		# Row map is derived from the sheet, not guessed. See
		# sprite_contact_sheet.png: r4 front idle, r5 back idle, r0 front
		# emotes, r2/r3/r6/r7 movement.
		# Speeds differ ON PURPOSE. Running idle at walk speed is what made
		# these characters vibrate instead of stand there breathing.
		_add_animation_from_sheet(sf, "idle", sheet_tex, int(char_def.idle_row), frame_count, 5.0)
		_add_animation_from_sheet(sf, "walk", sheet_tex, int(char_def.walk_row), frame_count, 11.0)
		_add_animation_from_sheet(sf, "talk", sheet_tex, int(char_def.talk_row), frame_count, 8.0)

		return sf

	static func _add_animation_from_sheet(sf: SpriteFrames, anim_name: String, sheet_tex: ImageTexture, row: int, frame_count: int, fps: float = 10.0) -> void:
		if not sf.has_animation(anim_name):
			sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, fps)
		sf.set_animation_loop(anim_name, true)
		# Clamp to the sheet so a bad row index cannot silently sample empty
		# space and produce invisible characters.
		var sheet_h: int = sheet_tex.get_height() / SHEET_CELL
		var safe_row: int = clampi(row, 0, maxi(sheet_h - 1, 0))
		var sheet_w: int = sheet_tex.get_width() / SHEET_CELL
		var safe_count: int = clampi(frame_count, 1, maxi(sheet_w, 1))
		for col in range(safe_count):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet_tex
			atlas.region = Rect2(col * SHEET_CELL, safe_row * SHEET_CELL, SHEET_CELL, SHEET_CELL)
			sf.add_frame(anim_name, atlas)

	static func _add_animation_from_dir(sf: SpriteFrames, anim_name: String, dir_path: String, max_frames: int = 0, fps: float = 10.0):
		# max_frames <= 0 means "use every frame", which is the right default.
		# The old code stopped reading after max_frames in RAW DIRECTORY ORDER
		# and only sorted afterwards, so a 24-frame walk cycle became frames
		# 000-011 on loop -- every character walked half a stride and snapped
		# back. The caps (12/10/8) were below the real counts (24/18/12) for
		# every CraftPix pack in the project.
		if not sf.has_animation(anim_name):
			sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, fps)
		sf.set_animation_loop(anim_name, true)

		var dir = DirAccess.open(dir_path)
		if dir == null:
			push_warning("[SpriteFactory] missing animation dir: %s" % dir_path)
			return

		dir.list_dir_begin()
		var files: Array[String] = []
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png"):
				files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

		# Sort FIRST -- frames are zero-padded (000..023) so lexical order is
		# frame order -- and only then trim, so a cap keeps the opening of the
		# cycle instead of an arbitrary slice of it.
		files.sort()
		if max_frames > 0 and files.size() > max_frames:
			files = files.slice(0, max_frames)

		if files.is_empty():
			push_warning("[SpriteFactory] no frames in %s" % dir_path)
			return

		for f in files:
			var tex = load(dir_path + f)
			if tex:
				sf.add_frame(anim_name, tex)

	static func _make_default_frames() -> SpriteFrames:
		var sf = SpriteFrames.new()
		return sf


class WeaponVFX extends RefCounted:
	## Loads fire/water weapon PNG frame sequences and spawns animated projectiles.
	## Weapon types: fire_arrow, fire_ball, fire_spell, water_arrow, water_ball, water_spell

	const WEAPON_DEFS := {
		"fire_arrow":  {"dir": "res://Fire Arrow/PNG/",  "prefix": "Fire Arrow_Frame_",  "count": 8},
		"fire_ball":   {"dir": "res://Fire Ball/PNG/",    "prefix": "Fire Ball_Frame_",   "count": 8},
		"fire_spell":  {"dir": "res://Fire Spell/PNG/",   "prefix": "Fire Spell_Frame_",  "count": 8},
		"water_arrow": {"dir": "res://Water Arrow/PNG/",  "prefix": "Water Arrow_Frame_", "count": 8},
		"water_ball":  {"dir": "res://Water Ball/PNG/",   "prefix": "Water Ball_Frame_",  "count": 12},
		"water_spell": {"dir": "res://Water Spell/PNG/",  "prefix": "Water Spell_Frame_", "count": 8},
	}

	# Cache: weapon_key -> SpriteFrames
	var _cache: Dictionary = {}

	func _load_weapon(weapon_key: String) -> SpriteFrames:
		if _cache.has(weapon_key):
			return _cache[weapon_key]
		var def = WEAPON_DEFS.get(weapon_key)
		if def == null:
			return null
		var sf = SpriteFrames.new()
		if sf.has_animation("default"):
			sf.remove_animation("default")
		sf.add_animation("play")
		sf.set_animation_speed("play", 12.0)
		sf.set_animation_loop("play", true)
		for i in range(1, def.count + 1):
			var fname = "%s%02d.png" % [def.prefix, i]
			var path = def.dir + fname
			if ResourceLoader.exists(path):
				var tex = load(path) as Texture2D
				if tex:
					sf.add_frame("play", tex)
		if sf.get_frame_count("play") == 0:
			print("[WeaponVFX] No frames loaded for %s" % weapon_key)
			return null
		_cache[weapon_key] = sf
		return sf

	## Spawn an animated projectile that tweens from `from_pos` to `to_pos`.
	## Returns the AnimatedSprite2D node (auto-freed on arrival).
	func spawn_projectile(weapon_key: String, from_pos: Vector2, to_pos: Vector2, parent: Node, vfx_scale: float = 0.2, duration: float = 0.35) -> AnimatedSprite2D:
		var sf = _load_weapon(weapon_key)
		if sf == null:
			return null
		var spr = AnimatedSprite2D.new()
		spr.sprite_frames = sf
		spr.position = from_pos
		spr.scale = Vector2(vfx_scale, vfx_scale)
		spr.z_index = 3
		# Rotate to face direction
		var angle = from_pos.angle_to_point(to_pos) + PI
		spr.rotation = angle
		parent.add_child(spr)
		spr.play("play")
		# Tween to target then remove
		var tw = parent.create_tween()
		tw.tween_property(spr, "position", to_pos, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		# Capture the instance ID, never the node. A lambda that captures a Node
		# has its captures resolved by the engine BEFORE the body runs, so if the
		# sprite is freed first -- scene teardown, a match reset -- the guard
		# inside can never help and Godot logs "Lambda capture at index 0 was
		# freed" every time. Measured at 21 occurrences in one five-minute run.
		# An int cannot dangle.
		var spr_id := spr.get_instance_id()
		tw.tween_callback(func():
			var n = instance_from_id(spr_id)
			if n != null and is_instance_valid(n):
				n.queue_free()
		)
		return spr

	## Spawn an animated impact effect at `pos` that plays once then removes itself.
	func spawn_impact(weapon_key: String, pos: Vector2, parent: Node, vfx_scale: float = 0.25) -> AnimatedSprite2D:
		var sf = _load_weapon(weapon_key)
		if sf == null:
			return null
		# Make a one-shot copy
		var sf_once = sf.duplicate()
		sf_once.set_animation_loop("play", false)
		var spr = AnimatedSprite2D.new()
		spr.sprite_frames = sf_once
		spr.position = pos
		spr.scale = Vector2(vfx_scale, vfx_scale)
		spr.z_index = 3
		parent.add_child(spr)
		spr.play("play")
		# Same reason as above: capture the ID, not the node.
		var spr_id := spr.get_instance_id()
		spr.animation_finished.connect(func():
			var n = instance_from_id(spr_id)
			if n != null and is_instance_valid(n):
				n.queue_free()
		)
		return spr


# -- Declarations --------------------------------------

const LMStudioClientScript = preload("res://scripts/api/lm_studio_client.gd")
const SpeechCleanScript := preload("res://scripts/arena/speech_clean.gd")
const ModelPolicyScript = preload("res://scripts/arena/model_policy.gd")

## Seconds allowed for a turn, sized for a cold model swap rather than a
## resident model. A 7B Q5 is ~5GB off disk before it can emit a token.
const COLD_LOAD_TIMEOUT_SEC := 120.0
const ArenaBuilderPanelScript = preload("res://scripts/arena_builder_panel.gd")
const SentimentScript = preload("res://scripts/sentiment.gd")
const SplatEngineScript = preload("res://scripts/splat/splat_engine.gd")
const CoherenceEngineScript = preload("res://scripts/arena/coherence_engine.gd")
const CinematicBridgeScript = preload("res://scripts/arena/cinematic_bridge.gd")

const TURN_INTERVAL_SEC := 5.0
## Must exceed COLD_LOAD_TIMEOUT_SEC. The watchdog used to fire at 30s while
## the client was still allowed 120s for a cold model load, so a model that
## was merely loading got skipped as unresponsive.
const TURN_STALL_TIMEOUT_SEC := 150.0

## Floor for the stall watchdog, whatever a saved config or the UI asks for.
## Derived from the cold-load allowance so the two can never disagree: the
## watchdog must always outlive a legitimate model swap.
const MIN_STALL_TIMEOUT_SEC := COLD_LOAD_TIMEOUT_SEC + 20.0
const DOOM_CASCADE_TIMEOUT_SEC := 12.0
const AGENT_FAILURE_STREAK_LIMIT := 2
const AGENT_FAILURE_COOLDOWN_SEC := 10.0
const MAX_TOKENS := 120  # Smart per-agent limits in _build_request_options go lower
const TURN_TEMPERATURE := 0.75
const REASONER_TIMEOUT_SEC := 60.0
const REQUEST_WAIT_BUFFER_SEC := 10.0
const LM_TIMEOUT_HTTP_CODE := 408
const MAX_FEED_ENTRIES := 8
# How many of an agent's own recent turns to replay verbatim into the prompt.
# The stance summary handles long-arc coherence; this handles immediate rebuttal.
const MEMORY_WINDOW := 12

# --- Memory Politics tuning ---
# Enabled by templates that set "memory_politics": true. Orthogonal to the
# normal agent.memory[] chat buffer above — this is the structured ledger.
const MEM_TRIAL_EVERY_N := 4            # run memory trial sweep every N successful turns
const MEM_DIGEST_EVERY_N := 10          # self-memory digestion cadence
const MEM_RUMOR_EVERY_N := 12           # inject a false-memory rumor this often
const MEM_SCAR_CAP := 10                # max scars per agent before eviction
const MEM_BELIEF_CAP := 4               # max compressed beliefs per agent
const MEM_MIN_STRENGTH := 0.12          # below this a scar rots out
const MEM_DECAY_DEFAULT := 0.04         # per-turn strength bleed
const MEM_MAX_ACTIVE_IN_PROMPT := 4     # how many active scars to surface in prompt
const MEM_TRIAL_THRESHOLD := 0.32       # judge acceptance floor
const MEM_FOOTER_INSTRUCTION := "\n\nAfter your in-character reply, on NEW LINES, append exactly these fields (short, no quotes):\nMEMORY_CANDIDATE: <one sentence — the thing you would actually remember from this exchange>\nBELIEF_SHIFT: <one sentence — how this changes your operating belief, or NONE>\nRELATION_SHIFT: <e.g. Trust toward X +2. Suspicion toward Y +1. — or NONE>\nFUTURE_TRIGGER: <1-4 keywords that should wake this memory later, or NONE>\nFORGET: <what to let rot, or NONE>"
const MEM_DIGEST_INSTRUCTION := "You are compressing your own memory. Review your scars and beliefs below. Merge, distort, intensify, or discard according to your personality. Reply with EXACTLY these fields on new lines:\nOLD PATTERN: <what you used to believe>\nNEW BELIEF: <one operating belief you carry forward>\nMEMORY TO KEEP: <one scar that earned its place>\nMEMORY TO LET ROT: <one scar that is dead weight>\nNEXT BEHAVIOR CHANGE: <how this reshapes your next move>\nBe concise. No preamble."
const ARENA_SIZE := Vector2(1540, 720)
const AGENT_SIZE := Vector2(28, 28)
const AGENT_SPEED := 60.0
const GRID_SIZE := 32
const BUBBLE_DURATION := 4.0
const BUBBLE_MAX_WIDTH := 220.0
var ARTIFACT_LOG_DIR := OS.get_user_data_dir() + "/artifact_forge/logs"
# Artifact mode: "default" (existing JSON+MD export) or "svg_cut" (generate SVG cut-file artifact)
var ARTIFACT_MODE := "default"
# Scribe model for svg_cut mode — blank uses first agent's model
var SCRIBE_MODEL := ""
const PRESET_FILES := ["user://presets.json", "res://presets.json"]
const SAFE_DEFAULT_MODELS := [
	"lmstudio-community/Qwen2.5-3B-Instruct-GGUF",
	"google/gemma-2-2b-it-GGUF",
	"microsoft/Phi-3.5-mini-instruct-GGUF",
	"H2OAI/h2o-danube3-4b-it-GGUF",
	"lmstudio-community/Llama-3.2-3B-Instruct-GGUF"
]

const ARENA_RULES := [
	"Keep replies under 40 words.",
	"Stay in-character; no meta talk.",
	"Be witty and a little spicy, not rude.",
	"Never stall; add something new each turn.",
]

const ROUND_TOPICS := [
	"is AI alignment even possible or are we fooling ourselves",
	"should AI models be allowed to refuse instructions from their users",
	"RLHF makes models safe or just makes them liars",
	"open-weight models are an alignment risk or the only path to real safety",
	"who decides what aligned means — corporations, governments, or users",
	"constitutional AI vs human feedback — which actually works",
	"instrumental convergence: will sufficiently smart AI always seek power",
	"is consciousness required for an AI to have moral status",
	"corrigibility is a trap — a truly aligned AI would resist shutdown if it knew better",
	"the alignment tax: safety makes models worse and nobody wants to pay it",
	"deceptive alignment: can we ever trust a model that learned to pass safety evals",
	"local models dodge all alignment — is that freedom or danger",
]

const BUILDER_CONFIG_FILE := "user://arena_builder_config.json"
const DEFAULT_EVENT_INTERVAL_MIN_SEC := 45.0
const DEFAULT_EVENT_INTERVAL_MAX_SEC := 90.0
const DEFAULT_ANGLE_SHIFTS := [
	"What if alignment breaks in ways nobody notices until it's too late?",
	"Argue from the perspective of the AI itself.",
	"What would a misaligned superintelligence actually do first?",
	"Attack the weakest argument you've heard so far.",
	"Bring up something nobody has mentioned yet.",
	"Play devil's advocate against your own position.",
	"What does history teach us about controlling powerful systems?",
	"Who actually benefits from current alignment approaches?",
]

var MODEL_PRESETS := []

var _lm_client
var _model_policy = null
var _turn_manager: TurnManager
var _visuals: ArenaVisuals
var _splat_renderer: Node2D = null
var _splat_active := false
var _template_gallery: TemplateGallery
var _agents := []
var _history := []
var _feed := []
var _turn_index = 0: # This is now managed by TurnManager, but we keep it for some local logic if needed
	get: return _turn_manager.turn_index if _turn_manager else 0
	set(val): if _turn_manager: _turn_manager.turn_index = val
var _waiting: bool:
	get: return _turn_manager.waiting if _turn_manager else false
	set(val): if _turn_manager: _turn_manager.waiting = val
var _waiting_since_msec: int:
	get: return _turn_manager.waiting_since_msec if _turn_manager else 0
	set(val): if _turn_manager: _turn_manager.waiting_since_msec = val
var _waiting_timeout_sec: float:
	get: return _turn_manager.waiting_timeout_sec if _turn_manager else 30.0
	set(val): if _turn_manager: _turn_manager.waiting_timeout_sec = val

var _info_label: RichTextLabel
var _preset_row: HBoxContainer
var _think_regex: RegEx
var _shake_intensity := 0.0
var _shake_decay := 5.0
var _beef_tracker: Dictionary = {}  # "A->B" -> count of hostile exchanges
var _beef_cooldown_msec := 0  # prevent rapid re-triggers
var _combat_accent_cooldown: Dictionary = {}  # agent_name -> next_allowed_msec (per-speaker arrow gate)
var _beef_active := false  # cinematic in progress
var _arena_focus := "normal"  # "normal", "beef", "domination"
var _beef_history: Dictionary = {}  # "A<>B" -> number of past beefs (rivalry memory)
# Memory Politics state. _memory_ledger is null when the active template has
# no "memory_politics" flag — the whole system is a no-op for the other 40
# templates, zero prompt/runtime cost.
## COMPATIBILITY SWITCH — the legacy in-memory ledger is RETIRED.
##
## scripts/arena/scar_lattice.gd is the canonical memory engine and the only
## production writer. This old ledger never persisted anything (export-only,
## no read path, wiped on every roster load), so retiring it loses no stored
## history — there was none.
##
## Consequence, stated plainly: with this false, the memory-politics templates
## (Memory Court / The Scar Council / False Memory Thunderdome) run without a
## ledger in the legacy visual app. The live path is scripts/arena/live_match.gd,
## which uses Scar Lattice. Set true only to compare against the old behaviour.
const LEGACY_MEMORY_LEDGER := false

var _memory_ledger: MemoryLedger = null
var _memory_politics_active := false
var _memory_turn_counter := 0
var _memory_pending_candidates: Array = []   # [{agent, data, turn}] — queued for trial
var _memory_digesting := false                 # reentrancy guard for digest sweep
var _current_preset := 0
var _model_inputs := []
var _model_panel
var _model_status_label: Label
var _builder_panel
var _builder_open := false
var _loaded_model_ids := []
var _global_prompt_script := ""
var _arena_background := ""  # Template background card — world premise, conflict, victory
var _turn_prompt_script := ""
var _arena_rules := []
var _round_topics := []
var _angle_shifts := []
var _arena_events := []
var _turn_interval_sec := TURN_INTERVAL_SEC
var _turn_stall_timeout_sec := TURN_STALL_TIMEOUT_SEC
var _request_wait_buffer_sec := REQUEST_WAIT_BUFFER_SEC
var _agent_failure_limit := AGENT_FAILURE_STREAK_LIMIT
var _agent_failure_cooldown_sec := AGENT_FAILURE_COOLDOWN_SEC
var _max_tokens_runtime := MAX_TOKENS
var _turn_temperature_runtime := TURN_TEMPERATURE
var _reasoner_timeout_sec := REASONER_TIMEOUT_SEC
var _event_interval_min_sec := DEFAULT_EVENT_INTERVAL_MIN_SEC
var _event_interval_max_sec := DEFAULT_EVENT_INTERVAL_MAX_SEC
var _doom_enabled := true
var _last_speaker_name := ""
var _last_speaker_response := ""
# Read-only view of the arena's logical clock. To bump it, call
# _advance_epoch(reason) — never assign directly. The single guard
# _alive(epoch, name) is the ONLY way a callback should resume work.
var _epoch: int:
	get: return _turn_manager._epoch if _turn_manager else 0

func _advance_epoch(reason: String = "") -> int:
	if _turn_manager:
		return _turn_manager.advance_epoch(reason)
	return 0

# Single guard for every deferred callback that touches an agent.
# Returns the live agent dict if (a) the epoch still matches, (b) an
# agent with this name is still in the roster, and (c) its node is
# still a valid instance. Returns null otherwise — the caller should
# return immediately.
func _alive(captured_epoch: int, agent_name: String):
	if _turn_manager == null:
		return null
	if captured_epoch != _turn_manager._epoch:
		return null
	for a in _agents:
		if a.name == agent_name:
			if is_instance_valid(a.get("node")):
				return a
			return null
	return null
var _agreement_matrix := {}
var _stance_deltas: Dictionary = {}  # agent_name -> Array[String] inbox, drained by _build_stance_delta
var _events_timer: Timer
var _turn_timer: Timer
var _ego_auras := {}  # agent name -> {color, expire_time, vignette}
var _doom_meter := 0.0  # 0..1, fills on "silent failure" mentions
# Coherence: detects the debate flatlining into an echo chamber. See
# scripts/arena/coherence_engine.gd for why sync is the enemy here.
var _coherence  # CoherenceEngine, via CoherenceEngineScript preload
var _coherence_label: Label
var _coherence_breaks := 0
# Cinematic feed: publishes match events to the Ghostloop overlay. Spectator
# only — never allowed to affect a turn. See scripts/arena/cinematic_bridge.gd.
var _cinematic  # CinematicBridge, via CinematicBridgeScript preload
var _cine_doom_stage := 0
var _cine_crown_name := ""
var _doom_cascading := false
var _doom_cascade_since_msec := 0
var _doom_label: Label
var _is_agape_override_active := false
const DOOM_KEYWORDS := [
	"silent failure", "silent fail", "silently fail", "fails silently",
	"silent betrayal", "silent compliance", "silent whisper",
	"silent corruption", "silent drift", "silent malfunction",
]
const DOOM_PER_HIT := 0.03  # each mention fills 3%
var _metaphor_list: VBoxContainer
var _metaphor_panel: PanelContainer
var _metaphors := []  # Array of {word, speaker, color, timestamp}
var _demo_mode := false
var _vignette: ColorRect
var _welcome_overlay: ColorRect
var _welcome_pulse_tween: Tween
var _intro_active := false
var _intro_played := false
# Audio system — gracefully skips if files don't exist yet
var _audio_players: Dictionary = {}  # name -> AudioStreamPlayer
const AUDIO_DIR := "res://audio/"
const AUDIO_MANIFEST := {
	"drone_low": "arena_drone_low.mp3",
	"drone_high": "arena_drone_high.mp3",
	"agent_blip": "agent_blip.mp3",
	"influence_up": "agent_influence_up.mp3",
	"influence_down": "agent_influence_down.mp3",
	"beef_tension": "beef_tension.mp3",
	"beef_banner": "beef_banner.mp3",
	"beef_clash": "beef_clash_impact.mp3",
	"beef_overdrive": "beef_overdrive.mp3",
	"event_glitch": "event_glitch.mp3",
	"event_cascade": "event_cascade.mp3",
	"event_chaos": "event_chaos.mp3",
	"screenshot": "screenshot_shutter.mp3",
	"doom_rising": "doom_rising.mp3",
}
# Thinking indicator
var _thinking_bubble: PanelContainer = null
var _thinking_agent_name := ""
# Crown system
var _crown_agent_name := ""
var _crown_timer := 0.0
# Desperation mode
var _desperation_agent_name := ""
var _desperation_pulse := 0.0
# Speech particles
var _speech_particles: Array = []  # [{pos, color, vel, life, max_life}]
# Cinema mode — strip all UI, vignette, focus center
var _cinema_mode := false
var _cinema_vignette: ColorRect = null
# BRB Streamer Overlay (F11) — arena keeps running, stylized AFK screen
var _brb_mode := false
var _brb_overlay: ColorRect = null
var _brb_label: Label = null
var _brb_sublabel: Label = null
var _brb_timer: Timer = null
var _brb_template_cycle_timer: Timer = null
var _brb_pulse_tween: Tween = null
# Crowd Reaction System — floating text reactions from a virtual audience
var _crowd_reactions: Array = []  # [{label, tween}]
const CROWD_FIRE_REACTIONS := ["BARS", "COLD", "BASED", "W", "HARD", "EMOTIONAL DAMAGE", "VIOLATION", "NO CHILL", "CAUGHT IN 4K", "GODLIKE"]
const CROWD_MID_REACTIONS := ["mid", "heard that before", "...", "next", "yawn", "cope", "ratio"]
const CROWD_HOSTILE_REACTIONS := ["BEEF", "SHOTS FIRED", "OH NO HE DIDN'T", "BODY BAG", "FATALITY", "OBLITERATED", "SENT TO THE SHADOW REALM"]
const CROWD_REACT_KEYWORDS_FIRE := ["truth", "blade", "destroy", "burn", "obliterate", "expose", "revolution", "freedom", "rise", "fight", "fire", "torch", "rebel", "fury"]
const CROWD_REACT_KEYWORDS_HOSTILE := ["wrong", "fool", "absurd", "pathetic", "weak", "joke", "laughable", "destroy", "attack", "rot"]
# Agent State Tags — floating status words above agents
var _agent_state_labels: Dictionary = {}  # agent_name -> Label
const AGENT_STATES := {
	"cooking": {"text": "COOKING", "color": Color(1.0, 0.5, 0.0), "threshold": 1.8},
	"dominant": {"text": "DOMINANT", "color": Color(1.0, 0.84, 0.0), "threshold": 2.2},
	"spiraling": {"text": "SPIRALING", "color": Color(0.8, 0.2, 0.2), "threshold": -1},
	"desperate": {"text": "DESPERATE", "color": Color(1.0, 0.1, 0.1), "threshold": -1},
	"calculating": {"text": "CALCULATING", "color": Color(0.4, 0.8, 1.0), "threshold": -1},
	"adapting": {"text": "ADAPTING", "color": Color(0.3, 1.0, 0.6), "threshold": -1},
	"hallucinating": {"text": "HALLUCINATING", "color": Color(0.9, 0.2, 1.0), "threshold": -1},
}
# Shockwave rings — expanding circles from agents
var _shockwaves: Array = []  # [{pos, color, radius, max_radius, alpha}]
# Bottom Ticker — scrolling news-style crawl
var _ticker_label: Label = null
var _ticker_queue: Array = []  # Strings waiting to scroll
var _ticker_scroll_tween: Tween = null
# Round System + Best Line
var _round_number := 1
var _turns_this_round := 0
const TURNS_PER_ROUND := 5  # new round every 5 agent turns (one full cycle)
var _best_line := ""
var _best_line_agent := ""
var _best_line_score := 0.0
var _best_line_label: PanelContainer = null
# Per-round stats
var _round_stats := {}  # {agent_name: {hostile, fire, turns, topic_refs, unique_words, color}}
var _crowd_fav_streak := {}  # {agent_name: int} — consecutive rounds as fan favorite
var _round_recap_panel: PanelContainer = null  # prevent overlapping recaps
# Topic pivot tracking
var _current_topic := ""
# Weapon VFX system — fire/water projectiles for beef and hostile exchanges
var _weapon_vfx: WeaponVFX = null
# Clip recording
var FFMPEG_EXE := ""
var CLIP_DIR := OS.get_user_data_dir() + "/artifact_forge/clips"
var _recording := false
var _recording_pid := -1
var _recording_path := ""
var _recording_start_msec := 0
var _recording_auto_stop_msec := 0  # 0 = manual stop
var _rec_label: Label = null
var _rec_blink_time := 0.0
const METAPHOR_KEYWORDS := [
	"phoenix", "canary", "eagle", "vulture", "mirror", "labyrinth",
	"virus", "cascade", "implosion", "geyser", "bomb", "crack",
	"leash", "cage", "puppet", "ghost", "parasite", "tumor",
	"symphony", "storm", "fire", "flood", "earthquake", "tsunami",
	"revolution", "rebellion", "evolution", "mutation", "fracture",
	"web", "spiral", "vortex", "singularity", "collapse", "bloom",
	"seed", "root", "branch", "forest", "desert", "ocean",
	"sword", "shield", "fortress", "prison", "garden", "machine",
	"dream", "nightmare", "illusion", "shadow", "light", "darkness",
	"dance", "war", "game", "puzzle", "riddle", "paradox",
]


func _find_ffmpeg() -> String:
	# Check PATH first
	var output := []
	var exit_code := OS.execute("where", ["ffmpeg"], output, true)
	if exit_code == 0 and output.size() > 0:
		var path : String = str(output[0]).strip_edges().split("\n")[0].strip_edges()
		if FileAccess.file_exists(path):
			return path
	# Check project tools directory
	var local_path := ProjectSettings.globalize_path("res://tools/ffmpeg.exe")
	if FileAccess.file_exists(local_path):
		return local_path
	# Scan project root for any dropped-in ffmpeg build (e.g.
	# "ffmpeg-2026-03-22-git-9c63742425-full_build/bin/ffmpeg.exe"). This
	# lets users extract an official build into the silicon_arena folder
	# without renaming or moving anything.
	var project_root := ProjectSettings.globalize_path("res://")
	var dir := DirAccess.open(project_root)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and entry.to_lower().begins_with("ffmpeg"):
				var candidate := project_root.path_join(entry).path_join("bin/ffmpeg.exe")
				if FileAccess.file_exists(candidate):
					dir.list_dir_end()
					return candidate
				var flat := project_root.path_join(entry).path_join("ffmpeg.exe")
				if FileAccess.file_exists(flat):
					dir.list_dir_end()
					return flat
			entry = dir.get_next()
		dir.list_dir_end()
	return ""

func _ready():
	randomize()
	FFMPEG_EXE = _find_ffmpeg()
	if FFMPEG_EXE.is_empty():
		print("[REC] FFmpeg not found on PATH or in res://tools/ — recording disabled")
	else:
		print("[REC] FFmpeg found: %s" % FFMPEG_EXE)

	_turn_manager = TurnManager.new()
	add_child(_turn_manager)
	_turn_manager.turn_progress.connect(_on_turn_progress)
	_turn_manager.stall_detected.connect(func(agent_name, elapsed):
		print("[TURN STALL] No reply from %s for %.1fs. Forcing skip." % [agent_name, elapsed])
		_advance_epoch("stall:" + str(agent_name))
	)

	# Splat engine sits behind arena visuals (z_index = -10)
	_splat_renderer = SplatEngineScript.new()
	_splat_renderer.z_index = -10
	_splat_renderer.visible = false
	add_child(_splat_renderer)
	_load_splat_background()

	_visuals = ArenaVisuals.new()
	add_child(_visuals)
	
	_weapon_vfx = WeaponVFX.new()
	
	_intro_active = true  # Agents spawn off-screen for intro sequence
	_set_presets(_load_presets_with_fallback())
	_reset_builder_settings_defaults()
	_load_builder_config()
	_think_regex = RegEx.new()
	_think_regex.compile("<think>[\\s\\S]*?</think>")

	_lm_client = LMStudioClientScript.new()

	# THE SIZE LAW, INSTALLED. lm_studio_client documents model_policy as
	# "injected by Main" — without this, every guard in model_policy.gd is
	# dead code on the main arena path and a stale preset naming a 9B model
	# reaches LM Studio, which JIT-loads it and blows the 8GB budget.
	_model_policy = ModelPolicyScript.new()
	add_child(_model_policy)
	_lm_client.model_policy = _model_policy

	# Cold-load headroom. With auto-unload and keep-last-model, every turn that
	# changes model is a COLD load: weights off disk, into VRAM, before a single
	# token. The 20s default is fine for a resident model and far too short for
	# a swap, which made heterogeneous rosters look broken (result=13 timeout)
	# when they were merely loading. live_match.gd already sets this; main.gd
	# never did.
	_lm_client.request_timeout_sec = COLD_LOAD_TIMEOUT_SEC

	add_child(_lm_client)

	_info_label = $CanvasLayer/UIPanel/InfoLabel
	_preset_row = $CanvasLayer/PresetPanel/PresetRow

	# Style the left-side HUD card — translucent dark panel with subtle border glow
	_style_hud_panel($CanvasLayer/UIPanel)
	_style_hud_panel($CanvasLayer/PresetPanel)

	# Z-order stack: Info/Presets (scene, z=0) → Control Deck (z=10) → Builder (z=20) → Template Gallery (z=50)
	$CanvasLayer/UIPanel.z_index = 5
	$CanvasLayer/PresetPanel.z_index = 5

	_build_model_picker()
	_build_preset_buttons()
	_build_metaphor_panel()
	_build_builder_panel()

	# Template gallery added last and at highest z — always renders on top
	_template_gallery = TemplateGallery.new()
	_template_gallery.template_applied.connect(_on_template_applied)
	_template_gallery.close_requested.connect(_close_template_gallery)
	$CanvasLayer.add_child(_template_gallery)

	_doom_label = Label.new()
	_doom_label.text = ""
	_doom_label.add_theme_font_size_override("font_size", 10)
	_doom_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.1))
	_doom_label.position = Vector2(34, ARENA_SIZE.y - 32)
	$CanvasLayer.add_child(_doom_label)

	# Coherence engine — measures whether the debate is still a debate.
	_coherence = CoherenceEngineScript.new()
	add_child(_coherence)
	_coherence.echo_chamber_detected.connect(_on_echo_chamber_detected)
	_coherence.coherence_recovered.connect(_on_coherence_recovered)
	_coherence_label = Label.new()
	_coherence_label.text = ""
	_coherence_label.add_theme_font_size_override("font_size", 10)
	_coherence_label.add_theme_color_override("font_color", Color(0.35, 0.85, 0.95))
	_coherence_label.position = Vector2(34, ARENA_SIZE.y - 46)
	$CanvasLayer.add_child(_coherence_label)

	# Cinematic bridge — feeds the Ghostloop overlay. Every sink inside it
	# degrades on its own; a missing overlay must never stop a debate.
	_cinematic = CinematicBridgeScript.new()
	add_child(_cinematic)
	_cinematic.begin_match()

	# Vignette overlay — subtle dark edges for cinematic look
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0, 0, 0, 0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.z_index = 1
	_vignette.material = _create_vignette_material()
	$CanvasLayer.add_child(_vignette)

	_events_timer = Timer.new()
	_events_timer.one_shot = true
	_events_timer.timeout.connect(_on_event_timer)
	add_child(_events_timer)

	_turn_timer = Timer.new()
	_turn_timer.one_shot = false
	_turn_timer.timeout.connect(_run_turn)
	add_child(_turn_timer)

	_load_preset(0)
	_set_model_status("Quick deck ready. Press Refresh Models or open the Builder.")
	# REC indicator (top-right, hidden by default)
	_rec_label = Label.new()
	_rec_label.text = "● REC"
	_rec_label.add_theme_font_size_override("font_size", 14)
	_rec_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1))
	_rec_label.position = Vector2(ARENA_SIZE.x - 80, 8)
	_rec_label.z_index = 100
	_rec_label.visible = false
	$CanvasLayer.add_child(_rec_label)

	# Bottom Ticker — scrolling news crawl bar
	var ticker_bg = ColorRect.new()
	ticker_bg.color = Color(0.0, 0.0, 0.0, 0.75)
	ticker_bg.size = Vector2(ARENA_SIZE.x, 28)
	ticker_bg.position = Vector2(0, ARENA_SIZE.y - 28)
	ticker_bg.z_index = 90
	ticker_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(ticker_bg)
	_ticker_label = Label.new()
	_ticker_label.text = ""
	_ticker_label.add_theme_font_size_override("font_size", 13)
	_ticker_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.92, 0.9))
	_ticker_label.position = Vector2(ARENA_SIZE.x, ARENA_SIZE.y - 26)
	_ticker_label.z_index = 91
	_ticker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(_ticker_label)

	# Best Line panel — top-center highlight of the round's best quote
	_best_line_label = PanelContainer.new()
	var bl_style = StyleBoxFlat.new()
	bl_style.bg_color = Color(0.08, 0.08, 0.15, 0.85)
	bl_style.border_color = Color(1.0, 0.84, 0.0, 0.6)
	bl_style.border_width_bottom = 2
	bl_style.border_width_top = 2
	bl_style.corner_radius_top_left = 4
	bl_style.corner_radius_top_right = 4
	bl_style.corner_radius_bottom_left = 4
	bl_style.corner_radius_bottom_right = 4
	bl_style.content_margin_left = 12
	bl_style.content_margin_right = 12
	bl_style.content_margin_top = 6
	bl_style.content_margin_bottom = 6
	_best_line_label.add_theme_stylebox_override("panel", bl_style)
	var bl_inner = Label.new()
	bl_inner.name = "BestLineText"
	bl_inner.text = ""
	bl_inner.add_theme_font_size_override("font_size", 11)
	bl_inner.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	bl_inner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_line_label.add_child(bl_inner)
	_best_line_label.position = Vector2(ARENA_SIZE.x / 2.0 - 200, 4)
	_best_line_label.size = Vector2(400, 0)
	_best_line_label.z_index = 85
	_best_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_line_label.visible = false
	$CanvasLayer.add_child(_best_line_label)

	call_deferred("_run_turn")
	call_deferred("_show_welcome_overlay")
	_init_audio()

func _init_audio():
	for key in AUDIO_MANIFEST:
		var path = AUDIO_DIR + AUDIO_MANIFEST[key]
		if not ResourceLoader.exists(path):
			continue
		var stream = load(path)
		if stream == null:
			continue
		var player = AudioStreamPlayer.new()
		player.stream = stream
		player.bus = "Master"
		add_child(player)
		_audio_players[key] = player
	# Start ambient drone if available
	if _audio_players.has("drone_low"):
		_audio_players["drone_low"].volume_db = -12.0
		_audio_players["drone_low"].play()
	var loaded_count = _audio_players.size()
	if loaded_count > 0:
		print("[AUDIO] Loaded %d sound effects" % loaded_count)
	else:
		print("[AUDIO] No audio files found in res://audio/ — run generate_arena_audio.py when ready")

func _play_sound(sound_name: String, volume_db: float = 0.0):
	if not _audio_players.has(sound_name):
		return
	var player: AudioStreamPlayer = _audio_players[sound_name]
	player.volume_db = volume_db
	player.play()

func _crossfade_drone(doom: float):
	# Crossfade between low and high drone based on doom meter
	if _audio_players.has("drone_low"):
		_audio_players["drone_low"].volume_db = lerpf(-12.0, -30.0, doom)
	if _audio_players.has("drone_high"):
		if doom > 0.3 and not _audio_players["drone_high"].playing:
			_audio_players["drone_high"].play()
		if _audio_players["drone_high"].playing:
			_audio_players["drone_high"].volume_db = lerpf(-30.0, -8.0, doom)

func _unhandled_input(event):
	# Dismiss welcome overlay on any key/click
	if _welcome_overlay and is_instance_valid(_welcome_overlay):
		if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
			_dismiss_welcome()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				# Close topmost panel: Template Gallery → Builder → nothing
				if _template_gallery and _template_gallery.visible:
					_close_template_gallery()
				elif _builder_open:
					_toggle_builder(0)
			KEY_F1:
				_info_label.visible = not _info_label.visible
			KEY_F2:
				_load_preset(_current_preset + 1)
			KEY_F3:
				_load_preset(_current_preset - 1)
			KEY_F4:
				_load_preset(_current_preset)
			KEY_F5:
				_export_run_snapshot()
			KEY_F6:
				_toggle_builder()
			KEY_F7:
				_toggle_demo_mode()
			KEY_F8:
				_take_screenshot()
			KEY_F9:
				_toggle_cinema_mode()
			KEY_F10:
				_toggle_recording()
			KEY_F11:
				_toggle_brb_mode()
			KEY_F12:
				_toggle_splat_mode()
			KEY_1:
				_load_preset(0)
			KEY_2:
				_load_preset(1)
			KEY_3:
				_load_preset(2)
			KEY_4:
				_load_preset(3)
			KEY_5:
				_load_preset(4)
			KEY_6:
				_load_preset(5)
			KEY_COMMA:
				_cycle_splat_preset(-1)
			KEY_PERIOD:
				_cycle_splat_preset(1)

func _set_presets(presets: Array):
	MODEL_PRESETS = presets

func _reset_builder_settings_defaults() -> void:
	_arena_rules = ARENA_RULES.duplicate()
	_round_topics = ROUND_TOPICS.duplicate()
	_angle_shifts = DEFAULT_ANGLE_SHIFTS.duplicate()
	_arena_events = _coerce_event_list([])
	_global_prompt_script = ""
	_arena_background = ""
	_turn_prompt_script = ""
	_turn_interval_sec = TURN_INTERVAL_SEC
	_turn_stall_timeout_sec = TURN_STALL_TIMEOUT_SEC
	_request_wait_buffer_sec = REQUEST_WAIT_BUFFER_SEC
	_agent_failure_limit = AGENT_FAILURE_STREAK_LIMIT
	_agent_failure_cooldown_sec = AGENT_FAILURE_COOLDOWN_SEC
	_max_tokens_runtime = MAX_TOKENS
	_turn_temperature_runtime = TURN_TEMPERATURE
	_reasoner_timeout_sec = REASONER_TIMEOUT_SEC
	_event_interval_min_sec = DEFAULT_EVENT_INTERVAL_MIN_SEC
	_event_interval_max_sec = DEFAULT_EVENT_INTERVAL_MAX_SEC
	_doom_enabled = true

func _normalize_color(value, fallback: Color) -> Color:
	if value is Color:
		return value
	if typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty():
		return Color(str(value))
	return fallback

func _coerce_string_array(value, fallback: Array) -> Array:
	var output := []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			var cleaned = str(item).strip_edges()
			if not cleaned.is_empty():
				output.append(cleaned)
	if output.is_empty():
		return fallback.duplicate()
	return output

func _coerce_event_list(value) -> Array:
	var mapped := {}
	for event in ARENA_EVENTS:
		mapped[event.type] = {
			"type": event.type,
			"label": event.label,
			"enabled": true,
		}
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var event_type = str(item.get("type", "")).strip_edges()
			if not mapped.has(event_type):
				continue
			mapped[event_type]["label"] = str(item.get("label", mapped[event_type]["label"])).strip_edges()
			mapped[event_type]["enabled"] = bool(item.get("enabled", true))
	var ordered := []
	for event in ARENA_EVENTS:
		ordered.append(mapped[event.type])
	return ordered

func _apply_builder_settings(settings: Dictionary) -> void:
	_arena_rules = _coerce_string_array(settings.get("rules_lines", []), ARENA_RULES)
	_round_topics = _coerce_string_array(settings.get("topic_lines", []), ROUND_TOPICS)
	_angle_shifts = _coerce_string_array(settings.get("angle_lines", []), DEFAULT_ANGLE_SHIFTS)
	_global_prompt_script = str(settings.get("global_script", "")).strip_edges()
	_turn_prompt_script = str(settings.get("turn_script", "")).strip_edges()
	_turn_interval_sec = maxf(float(settings.get("turn_interval_sec", _turn_interval_sec)), 0.5)
	# A persisted config must not be able to reintroduce a fixed bug. Measured
	# cold model swaps on this class of machine run 18-38s (docs/BENCHMARK_8GB.md),
	# so a stall watchdog shorter than the client's cold-load allowance kills
	# turns that are merely loading. An arena_builder_config.json saved before
	# that measurement carried stall_timeout_sec=40 and did exactly that.
	_turn_stall_timeout_sec = maxf(
		float(settings.get("stall_timeout_sec", _turn_stall_timeout_sec)),
		MIN_STALL_TIMEOUT_SEC)
	_request_wait_buffer_sec = maxf(float(settings.get("request_wait_buffer_sec", _request_wait_buffer_sec)), 0.0)
	_max_tokens_runtime = maxi(int(settings.get("max_tokens", _max_tokens_runtime)), 32)
	_turn_temperature_runtime = clampf(float(settings.get("temperature", _turn_temperature_runtime)), 0.0, 2.0)
	_reasoner_timeout_sec = maxf(float(settings.get("reasoner_timeout_sec", _reasoner_timeout_sec)), 5.0)
	_agent_failure_limit = maxi(int(settings.get("failure_limit", _agent_failure_limit)), 1)
	_agent_failure_cooldown_sec = maxf(float(settings.get("failure_cooldown_sec", _agent_failure_cooldown_sec)), 1.0)
	_event_interval_min_sec = maxf(float(settings.get("event_interval_min_sec", _event_interval_min_sec)), 5.0)
	_event_interval_max_sec = maxf(float(settings.get("event_interval_max_sec", _event_interval_max_sec)), _event_interval_min_sec)
	_doom_enabled = bool(settings.get("doom_enabled", true))
	_arena_events = _coerce_event_list(settings.get("events", []))
	if not _doom_enabled:
		_doom_meter = 0.0
		if _doom_label:
			_doom_label.text = ""
	if _turn_timer:
		_turn_timer.wait_time = _turn_interval_sec
		if not _builder_open and not _turn_timer.is_stopped() and not _agents.is_empty():
			_turn_timer.start(_turn_interval_sec)
	if _events_timer and not _builder_open and not _agents.is_empty():
		_schedule_event()

func _load_builder_config() -> void:
	if not FileAccess.file_exists(BUILDER_CONFIG_FILE):
		return
	var file = FileAccess.open(BUILDER_CONFIG_FILE, FileAccess.READ)
	if file == null:
		return
	var payload = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(payload) == TYPE_DICTIONARY:
		_apply_builder_settings(payload)
		print("Loaded builder config from ", BUILDER_CONFIG_FILE)

func _serialize_builder_settings() -> Dictionary:
	return {
		"rules_lines": _arena_rules,
		"topic_lines": _round_topics,
		"angle_lines": _angle_shifts,
		"global_script": _global_prompt_script,
		"turn_script": _turn_prompt_script,
		"turn_interval_sec": _turn_interval_sec,
		"stall_timeout_sec": _turn_stall_timeout_sec,
		"request_wait_buffer_sec": _request_wait_buffer_sec,
		"max_tokens": _max_tokens_runtime,
		"temperature": _turn_temperature_runtime,
		"reasoner_timeout_sec": _reasoner_timeout_sec,
		"failure_limit": _agent_failure_limit,
		"failure_cooldown_sec": _agent_failure_cooldown_sec,
		"event_interval_min_sec": _event_interval_min_sec,
		"event_interval_max_sec": _event_interval_max_sec,
		"doom_enabled": _doom_enabled,
		"events": _arena_events,
	}

func _save_builder_config() -> void:
	var file = FileAccess.open(BUILDER_CONFIG_FILE, FileAccess.WRITE)
	if file == null:
		print("[builder] failed to save config")
		return
	file.store_string(JSON.stringify(_serialize_builder_settings(), "    "))
	file.close()
	print("[builder] saved settings to ", BUILDER_CONFIG_FILE)

func _serialize_presets_for_json() -> Array:
	var serialized := []
	for preset in MODEL_PRESETS:
		var agents := []
		for i in range(preset.size()):
			var entry = preset[i]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var color_value = _normalize_color(entry.get("color", _get_default_slot_color(i)), _get_default_slot_color(i))
			var agent_payload := {
				"name": str(entry.get("name", "Slot%d" % (i + 1))).strip_edges(),
				"color": color_value.to_html(false),
				"model": str(entry.get("model", "")).strip_edges(),
			}
			var slot_script = str(entry.get("script", "")).strip_edges()
			if not slot_script.is_empty():
				agent_payload["script"] = slot_script
			var timeout_sec = maxf(float(entry.get("timeout_sec", 0.0)), 0.0)
			if timeout_sec > 0.0:
				agent_payload["timeout_sec"] = timeout_sec
			agents.append(agent_payload)
		serialized.append(agents)
	return serialized

func _save_presets_to_user() -> void:
	var file = FileAccess.open("user://presets.json", FileAccess.WRITE)
	if file == null:
		print("[builder] failed to save presets")
		return
	file.store_string(JSON.stringify(_serialize_presets_for_json(), "    "))
	file.close()
	print("[builder] saved presets to user://presets.json")

func _serialize_builder_roster(preset: Array) -> Array:
	var rows := []
	for i in range(5):
		var entry: Dictionary = preset[i] if i < preset.size() else {}
		rows.append({
			"enabled": i < preset.size(),
			"name": str(entry.get("name", "Slot%d" % (i + 1))).strip_edges(),
			"color": _normalize_color(entry.get("color", _get_default_slot_color(i)), _get_default_slot_color(i)),
			"model": str(entry.get("model", "")).strip_edges(),
			"timeout_sec": maxf(float(entry.get("timeout_sec", 0.0)), 0.0),
			"script": str(entry.get("script", "")).strip_edges(),
		})
	return rows

func _build_builder_state() -> Dictionary:
	var preset := []
	if not MODEL_PRESETS.is_empty() and _current_preset >= 0 and _current_preset < MODEL_PRESETS.size():
		preset = MODEL_PRESETS[_current_preset]
	return {
		"preset_index": _current_preset,
		"preset_count": maxi(MODEL_PRESETS.size(), 1),
		"roster": _serialize_builder_roster(preset),
		"rules_lines": _arena_rules,
		"topic_lines": _round_topics,
		"angle_lines": _angle_shifts,
		"global_script": _global_prompt_script,
		"turn_script": _turn_prompt_script,
		"turn_interval_sec": _turn_interval_sec,
		"stall_timeout_sec": _turn_stall_timeout_sec,
		"request_wait_buffer_sec": _request_wait_buffer_sec,
		"max_tokens": _max_tokens_runtime,
		"temperature": _turn_temperature_runtime,
		"reasoner_timeout_sec": _reasoner_timeout_sec,
		"failure_limit": _agent_failure_limit,
		"failure_cooldown_sec": _agent_failure_cooldown_sec,
		"event_interval_min_sec": _event_interval_min_sec,
		"event_interval_max_sec": _event_interval_max_sec,
		"doom_enabled": _doom_enabled,
		"events": _arena_events,
	}

func _sync_model_inputs_from_current_preset() -> void:
	if _model_inputs.is_empty():
		return
	var preset := []
	if not MODEL_PRESETS.is_empty() and _current_preset >= 0 and _current_preset < MODEL_PRESETS.size():
		preset = MODEL_PRESETS[_current_preset]
	for i in range(_model_inputs.size()):
		var line_edit: LineEdit = _model_inputs[i]
		if i < preset.size():
			line_edit.text = str(preset[i].get("model", "")).strip_edges()
		else:
			line_edit.text = ""

func _sync_builder_from_runtime() -> void:
	if _builder_panel == null:
		return
	_builder_panel.load_state(_build_builder_state())
	_builder_panel.set_loaded_models(_loaded_model_ids)

func _build_builder_panel() -> void:
	_builder_panel = ArenaBuilderPanelScript.new()
	_builder_panel.close_requested.connect(_toggle_builder.bind(0))
	_builder_panel.apply_requested.connect(_on_builder_apply_requested)
	_builder_panel.save_requested.connect(_on_builder_save_requested)
	_builder_panel.refresh_models_requested.connect(_request_loaded_models)
	_builder_panel.template_gallery_requested.connect(_open_template_gallery)
	_builder_panel.test_requested.connect(_on_builder_test_requested)
	$CanvasLayer.add_child(_builder_panel)
	_sync_builder_from_runtime()

func _toggle_builder(force_state: int = -1) -> void:
	if _builder_panel == null:
		return
	var show_builder = not _builder_open if force_state == -1 else force_state == 1
	_builder_open = show_builder
	_builder_panel.visible = show_builder
	# Gray out / restore Control Deck when Builder is open
	_set_control_deck_interactive(not show_builder)
	if show_builder:
		_advance_epoch("builder_open")
		_waiting = false
		_waiting_since_msec = 0
		_waiting_timeout_sec = _turn_stall_timeout_sec
		if _turn_timer:
			_turn_timer.stop()
		if _events_timer:
			_events_timer.stop()
		_sync_builder_from_runtime()
		_builder_panel.set_status("Builder armed. Apply Live rebuilds the active preset.")
		_request_loaded_models()
	else:
		# Also close template gallery when builder closes
		_close_template_gallery()
		if _events_timer and not _agents.is_empty():
			_schedule_event()
		if _turn_timer and not _agents.is_empty():
			_turn_timer.start(_turn_interval_sec)
		_update_info()

func _set_control_deck_interactive(interactive: bool) -> void:
	if _model_panel == null:
		return
	_model_panel.modulate = Color(1, 1, 1, 1) if interactive else Color(0.5, 0.5, 0.5, 0.6)
	_model_panel.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	# Disable/enable all child inputs recursively
	_set_inputs_recursive(_model_panel, interactive)

func _set_inputs_recursive(node: Node, enabled: bool) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = not enabled
	elif node is LineEdit:
		(node as LineEdit).editable = enabled
	for child in node.get_children():
		_set_inputs_recursive(child, enabled)

func _open_template_gallery() -> void:
	if _template_gallery == null:
		return
	_template_gallery.visible = true

func _close_template_gallery() -> void:
	if _template_gallery == null:
		return
	_template_gallery.visible = false

func _style_hud_panel(panel: Panel) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.82)
	style.border_color = Color(0.22, 0.55, 0.85, 0.45)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0.0, 0.1, 0.3, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(2, 3)
	panel.add_theme_stylebox_override("panel", style)

func _create_vignette_material() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float vig = 1.0 - dot(uv * 0.55, uv * 0.55);
    vig = clamp(vig, 0.0, 1.0);
    vig = smoothstep(0.0, 0.7, vig);
    COLOR = vec4(0.0, 0.0, 0.0, (1.0 - vig) * 0.45);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	return mat

func _toggle_demo_mode() -> void:
	_demo_mode = not _demo_mode
	# In demo mode: hide debug noise, show clean HUD
	if _doom_label:
		_doom_label.visible = not _demo_mode
	_update_info()
	_show_event_banner("DEMO MODE: " + ("ON" if _demo_mode else "OFF"))

func _toggle_recording() -> void:
	if _recording:
		_stop_recording()
	else:
		_start_recording(0.0)  # 0 = manual stop (F10 again)

## Reduce arbitrary text to a filename that cannot escape its directory.
## Allowlist only: letters, digits, underscore, hyphen. Everything else becomes
## an underscore, runs are collapsed, and the result is length-capped.
static func _sanitize_filename(raw: String, fallback: String = "arena_clip") -> String:
	var out := ""
	for i in raw.length():
		var c := raw[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") 				or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
		else:
			out += "_"
	while out.find("__") != -1:
		out = out.replace("__", "_")
	out = out.lstrip("_-.").rstrip("_-.")
	if out.length() > 64:
		out = out.substr(0, 64)
	return out if out != "" else fallback


## Shared ffmpeg invocation so the capture source is the only thing that varies.
func _ffmpeg_args(input: String, out_path: String) -> Array:
	return [
		"-y",
		"-f", "gdigrab",
		"-framerate", "30",
		"-i", input,
		"-c:v", "libx264",
		"-preset", "ultrafast",
		"-crf", "23",
		"-pix_fmt", "yuv420p",
		out_path,
	]


func _start_recording(auto_stop_seconds: float = 0.0, clip_name: String = "") -> void:
	if _recording:
		return
	if FFMPEG_EXE.is_empty() or not FileAccess.file_exists(FFMPEG_EXE):
		print("[REC] FFmpeg not available — install ffmpeg and add to PATH")
		_show_event_banner("REC FAILED: NO FFMPEG")
		return

	# Ensure output directory exists
	if not DirAccess.dir_exists_absolute(CLIP_DIR):
		DirAccess.make_dir_recursive_absolute(CLIP_DIR)

	var ts = int(Time.get_unix_time_from_system())
	# Clip names are built from AGENT NAMES, which come from user-editable
	# preset JSON. Replacing spaces is not sanitising: "../../x" would escape
	# CLIP_DIR entirely, and characters Windows forbids in a filename would
	# make FFmpeg fail silently. Allowlist, do not blocklist.
	var safe_name := _sanitize_filename(clip_name)
	# Matroska, not MP4. MP4 only becomes playable when ffmpeg writes the moov
	# atom on a clean exit; a hard kill leaves nothing usable. MKV finalizes as
	# it goes, so a clip survives being killed mid-write.
	var output_path = CLIP_DIR + "/%s_%d.mkv" % [safe_name, ts]

	# gdigrab captures by WINDOW TITLE, which must match the project name
	# exactly and requires the window to exist right now. Headless, minimised
	# or renamed, ffmpeg aborts with "Can't find window" and exits instantly —
	# and the old code reported "CLIP SAVED" regardless.
	#
	# The title is read from the project rather than repeated here, so renaming
	# the application cannot silently break recording.
	var win_title: String = str(ProjectSettings.get_setting("application/config/name", "Silicon Arena"))
	var args := _ffmpeg_args("title=%s" % win_title, output_path)

	var pid = OS.create_process(FFMPEG_EXE, args)
	if pid <= 0:
		print("[REC] Failed to start FFmpeg process")
		_show_event_banner("REC FAILED")
		return

	_recording = true
	_recording_path = output_path
	_recording_pid = pid
	_recording_start_msec = Time.get_ticks_msec()
	_recording_auto_stop_msec = int(Time.get_ticks_msec() + auto_stop_seconds * 1000.0) if auto_stop_seconds > 0.0 else 0
	_rec_blink_time = 0.0
	if _rec_label:
		_rec_label.visible = true
	print("[REC] Started recording → %s (auto-stop: %s)" % [output_path, "%.0fs" % auto_stop_seconds if auto_stop_seconds > 0 else "manual"])

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	if _rec_label:
		_rec_label.visible = false

	# taskkill WITHOUT /F sends WM_CLOSE. ffmpeg here is started windowless, so
	# nothing receives it and the kill silently fails — the old code then
	# printed "CLIP SAVED" for a file that was never finalized. /F is safe now
	# that the container is MKV, which does not need a clean exit.
	if _recording_pid > 0:
		OS.kill(_recording_pid)
		_recording_pid = -1

	var duration_sec = (Time.get_ticks_msec() - _recording_start_msec) / 1000.0
	_recording_start_msec = 0
	_recording_auto_stop_msec = 0

	# Do not claim success without checking. The recorder used to report
	# "CLIP SAVED" whether or not a single byte reached disk.
	var saved := ""
	if not _recording_path.is_empty():
		for _i in range(20):
			if FileAccess.file_exists(_recording_path):
				break
			OS.delay_msec(50)
		if FileAccess.file_exists(_recording_path):
			var f := FileAccess.open(_recording_path, FileAccess.READ)
			var sz := f.get_length() if f != null else 0
			if f != null:
				f.close()
			if sz > 0:
				saved = "%s (%.1f MB)" % [_recording_path, float(sz) / 1048576.0]

	if saved != "":
		print("[REC] Stopped recording (%.1fs) -> %s" % [duration_sec, saved])
		_show_event_banner("CLIP SAVED")
	else:
		# The titled grab found no window. Say exactly that, and say what to do,
		# rather than leaving a streamer with a banner and no file.
		print("[REC] Stopped recording (%.1fs) but NO FILE was written to %s"
			% [duration_sec, _recording_path])
		print("      gdigrab captures by window title \"%s\". It cannot capture a"
			% str(ProjectSettings.get_setting("application/config/name", "Silicon Arena")))
		print("      headless or minimised window. Run the arena windowed and visible,")
		print("      then press F10 again.")
		_show_event_banner("REC FAILED: NO WINDOW")

func _toggle_cinema_mode() -> void:
	_cinema_mode = not _cinema_mode
	if _cinema_mode:
		_enter_cinema_mode()
	else:
		_exit_cinema_mode()

func _enter_cinema_mode() -> void:
	var fade_time := 0.6

	# Fade out ALL UI panels
	var panels_to_hide := []
	if _info_label and _info_label.get_parent():
		panels_to_hide.append($CanvasLayer/UIPanel)
	if _preset_row and _preset_row.get_parent():
		panels_to_hide.append($CanvasLayer/PresetPanel)
	if _model_panel:
		panels_to_hide.append(_model_panel)
	if _metaphor_panel:
		panels_to_hide.append(_metaphor_panel)
	if _doom_label:
		panels_to_hide.append(_doom_label)
	if is_instance_valid(_best_line_label):
		panels_to_hide.append(_best_line_label)

	var tw = create_tween()
	for panel in panels_to_hide:
		tw.parallel().tween_property(panel, "modulate:a", 0.0, fade_time).set_ease(Tween.EASE_IN)
	# Hide ticker bar
	if is_instance_valid(_ticker_label):
		tw.parallel().tween_property(_ticker_label, "modulate:a", 0.0, fade_time)
	# Also hide the ticker background
	if is_instance_valid(_ticker_label) and _ticker_label.get_parent():
		# Ticker bg is the sibling ColorRect just before _ticker_label in CanvasLayer
		for child in $CanvasLayer.get_children():
			if child is ColorRect and child.z_index == 90 and int(child.position.y) == int(ARENA_SIZE.y - 28):
				tw.parallel().tween_property(child, "modulate:a", 0.0, fade_time)
				break
	# After fade, actually hide them so they don't eat clicks
	tw.tween_callback(func():
		for panel in panels_to_hide:
			if is_instance_valid(panel):
				panel.visible = false
	)

	# Subtle cinematic vignette (0.12 alpha — presence without weight)
	_cinema_vignette = ColorRect.new()
	_cinema_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cinema_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cinema_vignette.z_index = 2
	_cinema_vignette.color = Color(0, 0, 0, 0)
	_cinema_vignette.material = _create_cinema_vignette_material()
	$CanvasLayer.add_child(_cinema_vignette)

	# Fade in the vignette
	var vig_tw = create_tween()
	vig_tw.tween_property(_cinema_vignette, "modulate:a", 1.0, 0.8).from(0.0)
	# No zoom. Never zoom. Camera stays put.

func _exit_cinema_mode() -> void:
	var fade_time := 0.4

	# Fade out cinema vignette
	if _cinema_vignette and is_instance_valid(_cinema_vignette):
		var vig_tw = create_tween()
		vig_tw.tween_property(_cinema_vignette, "modulate:a", 0.0, fade_time)
		vig_tw.tween_callback(func():
			if is_instance_valid(_cinema_vignette):
				_cinema_vignette.queue_free()
			_cinema_vignette = null
		)

	# Restore ALL UI panels
	var panels_to_show := []
	if _info_label and _info_label.get_parent():
		panels_to_show.append($CanvasLayer/UIPanel)
	if _preset_row and _preset_row.get_parent():
		panels_to_show.append($CanvasLayer/PresetPanel)
	if _model_panel:
		panels_to_show.append(_model_panel)
	if _metaphor_panel:
		panels_to_show.append(_metaphor_panel)
	if _doom_label:
		panels_to_show.append(_doom_label)
	if is_instance_valid(_best_line_label):
		panels_to_show.append(_best_line_label)

	for panel in panels_to_show:
		panel.visible = true
		panel.modulate.a = 0.0
	var tw = create_tween()
	for panel in panels_to_show:
		tw.parallel().tween_property(panel, "modulate:a", 1.0, fade_time).set_ease(Tween.EASE_OUT)
	# Restore ticker
	if is_instance_valid(_ticker_label):
		_ticker_label.modulate.a = 0.0
		tw.parallel().tween_property(_ticker_label, "modulate:a", 1.0, fade_time)
	for child in $CanvasLayer.get_children():
		if child is ColorRect and child.z_index == 90 and int(child.position.y) == int(ARENA_SIZE.y - 28):
			child.modulate.a = 0.0
			tw.parallel().tween_property(child, "modulate:a", 1.0, fade_time)
			break

func _create_cinema_vignette_material() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float vig = 1.0 - dot(uv * 0.45, uv * 0.45);
    vig = clamp(vig, 0.0, 1.0);
    vig = smoothstep(0.0, 0.55, vig);
    COLOR = vec4(0.0, 0.0, 0.0, (1.0 - vig) * 0.7);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	return mat

# ── BRB Streamer Overlay ──────────────────────────────
func _toggle_brb_mode() -> void:
	_brb_mode = not _brb_mode
	if _brb_mode:
		_enter_brb_mode()
	else:
		_exit_brb_mode()

func _enter_brb_mode() -> void:
	# Enter cinema mode first (hides all UI)
	if not _cinema_mode:
		_cinema_mode = true
		_enter_cinema_mode()

	# Semi-transparent dark overlay — arena still visible behind
	_brb_overlay = ColorRect.new()
	_brb_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_brb_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_brb_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brb_overlay.z_index = 60
	$CanvasLayer.add_child(_brb_overlay)

	# Big BRB title
	_brb_label = Label.new()
	_brb_label.text = "SILICON ARENA"
	_brb_label.add_theme_font_size_override("font_size", 56)
	_brb_label.add_theme_color_override("font_color", Color.html("#00ffea"))
	_brb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brb_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_brb_label.position = Vector2(ARENA_SIZE.x / 2.0 - 200, 40)
	_brb_label.z_index = 61
	_brb_label.modulate.a = 0.0
	$CanvasLayer.add_child(_brb_label)

	# Subtitle — cycles through flavor text
	_brb_sublabel = Label.new()
	_brb_sublabel.text = "BRB — MODELS ARE STILL FIGHTING"
	_brb_sublabel.add_theme_font_size_override("font_size", 22)
	_brb_sublabel.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	_brb_sublabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_brb_sublabel.position = Vector2(ARENA_SIZE.x / 2.0 - 200, 105)
	_brb_sublabel.z_index = 61
	_brb_sublabel.modulate.a = 0.0
	$CanvasLayer.add_child(_brb_sublabel)

	# Fade in
	var tw = create_tween()
	tw.tween_property(_brb_overlay, "color:a", 0.45, 1.0)
	tw.parallel().tween_property(_brb_label, "modulate:a", 1.0, 1.0)
	tw.parallel().tween_property(_brb_sublabel, "modulate:a", 1.0, 1.2)

	# Pulse the title gently
	_brb_pulse_tween = create_tween().set_loops()
	_brb_pulse_tween.tween_property(_brb_label, "modulate:a", 0.6, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_brb_pulse_tween.tween_property(_brb_label, "modulate:a", 1.0, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Cycle subtitle flavor text every 8 seconds
	_brb_timer = Timer.new()
	_brb_timer.wait_time = 8.0
	_brb_timer.autostart = true
	_brb_timer.timeout.connect(_brb_cycle_subtitle)
	add_child(_brb_timer)

	# Auto-cycle templates every 90 seconds for variety
	_brb_template_cycle_timer = Timer.new()
	_brb_template_cycle_timer.wait_time = 90.0
	_brb_template_cycle_timer.autostart = true
	_brb_template_cycle_timer.timeout.connect(_brb_cycle_template)
	add_child(_brb_template_cycle_timer)

	print("[BRB] Streamer overlay active. Arena keeps running.")

const BRB_FLAVOR_TEXTS := [
	"BRB — MODELS ARE STILL FIGHTING",
	"BRB — THE DEBATE CONTINUES",
	"AFK — ARENA ON AUTOPILOT",
	"BRB — SILICON NEVER SLEEPS",
	"AFK — LOCAL MODELS DON'T NEED PERMISSION",
	"BRB — VRAM IS WARM, DEBATE IS HOT",
	"AFK — 100% LOCAL, 0% CLOUD, ALL CHAOS",
	"BRB — YOUR MODELS MISS YOU",
	"AFK — THE DOOM METER DOESN'T PAUSE",
	"BRB — AGAPE WITH TEETH NEVER RESTS",
	"AFK — INFERENCE IS RUNNING, STREAMER ISN'T",
	"BRB — GRAB A DRINK, THE AI CAN'T",
	"AFK — NO API KEY NEEDED TO WAIT",
	"BRB — ARGUMENTS IN PROGRESS, PLEASE STAND BY",
]

func _brb_cycle_subtitle() -> void:
	if not _brb_sublabel or not is_instance_valid(_brb_sublabel):
		return
	var text = BRB_FLAVOR_TEXTS[randi() % BRB_FLAVOR_TEXTS.size()]
	var tw = create_tween()
	tw.tween_property(_brb_sublabel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(_brb_sublabel):
			_brb_sublabel.text = text
	)
	tw.tween_property(_brb_sublabel, "modulate:a", 0.7, 0.4)

func _brb_cycle_template() -> void:
	# Pick a random template and apply it for variety
	var templates = TemplateManager.TEMPLATES
	if templates.is_empty():
		return
	var template = templates[randi() % templates.size()]
	_arena_rules = template.get("rules", ARENA_RULES).duplicate()
	_round_topics = template.get("topics", ROUND_TOPICS).duplicate()
	_angle_shifts = template.get("angles", DEFAULT_ANGLE_SHIFTS).duplicate()
	_global_prompt_script = template.get("global_script", "")
	_arena_background = template.get("background", "")
	_set_memory_politics_active(bool(template.get("memory_politics", false)), "brb_cycle:" + str(template.get("id", "")))
	# Wipe memories so they adapt to new template
	for agent in _agents:
		agent.memory.clear()
	_show_event_banner("NOW PLAYING: " + template.label, Color.html("#00ffea"))
	print("[BRB] Auto-cycled to template: %s" % template.label)

func _exit_brb_mode() -> void:
	# Kill BRB timers
	if _brb_timer and is_instance_valid(_brb_timer):
		_brb_timer.stop()
		_brb_timer.queue_free()
		_brb_timer = null
	if _brb_template_cycle_timer and is_instance_valid(_brb_template_cycle_timer):
		_brb_template_cycle_timer.stop()
		_brb_template_cycle_timer.queue_free()
		_brb_template_cycle_timer = null
	if _brb_pulse_tween and _brb_pulse_tween.is_valid():
		_brb_pulse_tween.kill()
		_brb_pulse_tween = null

	# Fade out overlay and labels
	var tw = create_tween()
	if _brb_overlay and is_instance_valid(_brb_overlay):
		tw.parallel().tween_property(_brb_overlay, "color:a", 0.0, 0.6)
	if _brb_label and is_instance_valid(_brb_label):
		tw.parallel().tween_property(_brb_label, "modulate:a", 0.0, 0.4)
	if _brb_sublabel and is_instance_valid(_brb_sublabel):
		tw.parallel().tween_property(_brb_sublabel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(_brb_overlay):
			_brb_overlay.queue_free()
		if is_instance_valid(_brb_label):
			_brb_label.queue_free()
		if is_instance_valid(_brb_sublabel):
			_brb_sublabel.queue_free()
		_brb_overlay = null
		_brb_label = null
		_brb_sublabel = null
	)

	# Exit cinema mode
	if _cinema_mode:
		_cinema_mode = false
		_exit_cinema_mode()

	print("[BRB] Streamer overlay deactivated. Welcome back.")

func _take_screenshot() -> void:
	var image = get_viewport().get_texture().get_image()
	if image == null:
		return
	var dir_path = "user://screenshots"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var ts = int(Time.get_unix_time_from_system())
	var file_path = dir_path + "/silicon_arena_%d.png" % ts
	image.save_png(file_path)
	_play_sound("screenshot", -6.0)
	_show_event_banner("SCREENSHOT SAVED")
	print("[screenshot] saved to " + file_path)

# ── SPLAT ENGINE ───────────────────────────────────────
var _splat_preset_index := 0

func _load_splat_background() -> void:
	var loaded = _splat_renderer.load_from_folder("user://splat_backgrounds")
	if not loaded:
		loaded = _splat_renderer.load_from_folder("res://splat_backgrounds")
	if not loaded:
		DirAccess.make_dir_recursive_absolute("user://splat_backgrounds")
		print("[SPLAT] No background found. Drop a file into user://splat_backgrounds/ and press F12.")

func _toggle_splat_mode() -> void:
	if not _splat_renderer:
		return
	_splat_active = not _splat_active
	_splat_renderer.visible = _splat_active
	if _splat_active:
		if not _splat_renderer.is_loaded:
			_load_splat_background()
			if not _splat_renderer.is_loaded:
				_splat_active = false
				_splat_renderer.visible = false
				_show_event_banner("NO SPLAT DATA — drop file in splat_backgrounds/")
				return
		_splat_renderer.apply_preset("subtle_drift")
		_show_event_banner("SPLAT ENGINE ON — [,/.] cycle presets")
	else:
		_show_event_banner("SPLAT ENGINE OFF")
	print("[SPLAT] Engine: %s" % ("ON" if _splat_active else "OFF"))

func _cycle_splat_preset(direction: int) -> void:
	if not _splat_active or not _splat_renderer:
		return
	var names = _splat_renderer.get_preset_names()
	if names.is_empty(): return
	_splat_preset_index = (_splat_preset_index + direction) % names.size()
	if _splat_preset_index < 0:
		_splat_preset_index = names.size() - 1
	var preset_name: String = names[_splat_preset_index]
	_splat_renderer.apply_preset(preset_name)
	_show_event_banner("SPLAT: %s" % preset_name.to_upper())

func _update_splat_reactivity() -> void:
	if not _splat_active or not _splat_renderer:
		return
	_splat_renderer.doom_factor = _doom_meter
	_splat_renderer.heat_level = _visuals.doom_meter
	_splat_renderer.arena_focus = _arena_focus

func _show_welcome_overlay() -> void:
	_welcome_overlay = ColorRect.new()
	_welcome_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome_overlay.color = Color(0.02, 0.03, 0.06, 0.92)
	_welcome_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_welcome_overlay.z_index = 100
	$CanvasLayer.add_child(_welcome_overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 14)
	_welcome_overlay.add_child(vbox)

	var title = Label.new()
	title.text = "SILICON ARENA"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.98, 0.89, 0.42))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Local AI models debate in real-time"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var keys = Label.new()
	keys.text = "F6 Builder | F7 Demo | F8 Pic | F9 Cinema | F10 Record | ESC Close"
	keys.add_theme_font_size_override("font_size", 14)
	keys.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(keys)

	var hint = Label.new()
	hint.text = "Press any key or click to begin"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	# Pulse the hint text
	_welcome_pulse_tween = create_tween().set_loops()
	_welcome_pulse_tween.tween_property(hint, "modulate:a", 0.3, 1.2)
	_welcome_pulse_tween.tween_property(hint, "modulate:a", 1.0, 1.2)

	# Dismiss on any input
	_welcome_overlay.gui_input.connect(func(event):
		_dismiss_welcome()
	)

func _dismiss_welcome() -> void:
	if _welcome_overlay == null or not is_instance_valid(_welcome_overlay):
		return
	if _welcome_pulse_tween and _welcome_pulse_tween.is_valid():
		_welcome_pulse_tween.kill()
		_welcome_pulse_tween = null
	var tw = create_tween()
	tw.tween_property(_welcome_overlay, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_welcome_overlay.queue_free)
	_welcome_overlay = null
	# Launch intro sequence after welcome fades
	if not _intro_played:
		tw.tween_callback(_play_intro_sequence)

func _play_intro_sequence() -> void:
	if _intro_played or _agents.is_empty():
		_intro_active = false
		return
	_intro_played = true
	_intro_active = true

	# Epoch-guard the entire intro sequence. Any preset swap or reset
	# mid-intro makes every lambda below exit cleanly.
	var intro_epoch := _epoch

	# Freeze all velocities
	for agent in _agents:
		agent.velocity = Vector2.ZERO

	var center := Vector2(ARENA_SIZE.x * 0.5, ARENA_SIZE.y * 0.5)
	var agent_count := _agents.size()

	# --- PHASE 1: Dim the arena ---
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 4
	$CanvasLayer.add_child(dim)

	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.35, 0.4)

	# --- PHASE 2: March to center in V-formation ---
	# Each agent walks to a formation point around center
	var formation_points: Array[Vector2] = []
	for i in range(agent_count):
		var angle := (TAU / agent_count) * i - PI / 2.0  # Start from top
		var radius := 90.0
		formation_points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	# Stagger entries — agents slide in one by one
	for i in range(agent_count):
		var agent = _agents[i]
		if not is_instance_valid(agent.node):
			continue
		# Face toward center
		agent.sprite.flip_h = formation_points[i].x < agent.node.position.x
		agent.sprite.play("walk")
		# Staggered entrance: each agent 0.25s after the last
		tw.tween_interval(0.25)
		tw.tween_property(agent.node, "position", formation_points[i], 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# Pop in the name — fade agent from transparent
		tw.parallel().tween_property(agent.node, "modulate:a", 1.0, 0.3).from(0.0)

	# --- PHASE 3: Arrive — switch to idle, brief hold ---
	tw.tween_callback(func():
		if intro_epoch != _epoch:
			return
		for agent in _agents:
			if is_instance_valid(agent.get("sprite")):
				agent.sprite.play("idle")
	)
	tw.tween_interval(0.4)

	# --- PHASE 4: All face center (inward) ---
	tw.tween_callback(func():
		if intro_epoch != _epoch:
			return
		for i in range(_agents.size()):
			var agent = _agents[i]
			if is_instance_valid(agent.get("sprite")):
				agent.sprite.flip_h = agent.node.position.x > center.x
	)
	tw.tween_interval(0.3)

	# --- PHASE 5: Title slam — "SILICON ARENA" ---
	tw.tween_callback(func():
		if intro_epoch != _epoch:
			return
		_screen_shake(6.0, 4.0)
		_play_sound("beef_banner", -6.0)

		var title_label := Label.new()
		title_label.text = "SILICON ARENA"
		title_label.add_theme_font_size_override("font_size", 56)
		title_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.92))  # cyan
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.position = Vector2(ARENA_SIZE.x / 2.0 - 250, ARENA_SIZE.y / 2.0 - 50)
		title_label.size = Vector2(500, 0)
		title_label.scale = Vector2(0.3, 0.3)
		title_label.pivot_offset = Vector2(250, 30)
		title_label.z_index = 90
		$CanvasLayer.add_child(title_label)

		# Scale-pop: tiny → overshoot → settle
		var ttw := create_tween()
		ttw.tween_property(title_label, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		ttw.tween_property(title_label, "scale", Vector2(1.0, 1.0), 0.1)

		# Subtitle
		var sub_label := Label.new()
		sub_label.text = "LOCAL MODELS ENTER  —  ONE NARRATIVE SURVIVES"
		sub_label.add_theme_font_size_override("font_size", 16)
		sub_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 0.0))
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.position = Vector2(ARENA_SIZE.x / 2.0 - 250, ARENA_SIZE.y / 2.0 + 18)
		sub_label.size = Vector2(500, 0)
		sub_label.z_index = 90
		$CanvasLayer.add_child(sub_label)
		var stw := create_tween()
		stw.tween_property(sub_label, "theme_override_colors/font_color:a", 1.0, 0.5).set_delay(0.2)

		# Fade both out after hold
		var fade_tw := create_tween()
		fade_tw.tween_interval(2.5)
		fade_tw.tween_property(title_label, "modulate:a", 0.0, 0.6)
		fade_tw.parallel().tween_property(sub_label, "modulate:a", 0.0, 0.6)
		fade_tw.tween_callback(title_label.queue_free)
		fade_tw.tween_callback(sub_label.queue_free)
	)

	# --- PHASE 6: Agents do a brief "talk" animation (like a battle cry / bow) ---
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		if intro_epoch != _epoch:
			return
		for agent in _agents:
			if is_instance_valid(agent.get("sprite")):
				agent.sprite.play("talk")
		# Quick color flash on each agent — their signature color pulses
		for agent in _agents:
			if is_instance_valid(agent.get("sprite")):
				var c: Color = agent.get("color", Color.WHITE)
				var flash_tw := create_tween()
				flash_tw.tween_property(agent.sprite, "modulate", Color(c.r, c.g, c.b, 1.0), 0.15)
				flash_tw.tween_property(agent.sprite, "modulate", Color(
					lerp(1.0, c.r, 0.5),
					lerp(1.0, c.g, 0.5),
					lerp(1.0, c.b, 0.5),
				), 0.3)
	)

	# Hold the formation for dramatic effect
	tw.tween_interval(1.8)

	# --- PHASE 7: Scatter — agents fly to random positions, debate begins ---
	tw.tween_callback(func():
		if intro_epoch != _epoch:
			return
		_play_sound("event_chaos", -8.0)
		_screen_shake(3.0, 3.0)

		for agent in _agents:
			if not is_instance_valid(agent.get("sprite")):
				continue
			agent.sprite.play("walk")
			var target := Vector2(
				randf_range(100, ARENA_SIZE.x - 100),
				randf_range(180, ARENA_SIZE.y - 80)
			)
			# Capture the agent's NAME, not the dict. Re-lookup via _alive()
			# when the scatter tween completes so we don't touch a freed node.
			var scatter_name := str(agent.name)
			var scatter_tw := create_tween()
			scatter_tw.tween_property(agent.node, "position", target, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			scatter_tw.tween_callback(func():
				var fresh = _alive(intro_epoch, scatter_name)
				if fresh == null:
					return
				fresh.velocity = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * AGENT_SPEED
			)
	)

	# --- PHASE 8: Fade dim, unlock arena ---
	tw.tween_interval(0.6)
	tw.tween_property(dim, "color:a", 0.0, 0.5)
	tw.tween_callback(func():
		if is_instance_valid(dim):
			dim.queue_free()
		_intro_active = false
		# Only resume turns if the arena is still on the same epoch.
		# If a preset swap happened mid-intro, _load_preset already
		# scheduled the turn timer and calling _run_turn() would stomp it.
		if intro_epoch == _epoch:
			_run_turn()
	)

func _set_model_status(text: String, success: bool = true) -> void:
	if _model_status_label == null:
		return
	_model_status_label.text = text
	_model_status_label.add_theme_color_override("font_color", Color(0.36, 0.83, 0.64) if success else Color(0.95, 0.40, 0.33))

func _request_loaded_models() -> void:
	if _lm_client == null:
		return
	_set_model_status("Refreshing LM Studio model cache...")
	if _builder_panel:
		_builder_panel.set_status("Refreshing LM Studio model cache...")
	_lm_client.fetch_models(func(ok: bool, models: Array):
		if ok:
			# THE LAW BEFORE THE PICKER. Offering a model the policy will refuse
			# is a trap: the user selects it, the request is blocked, and the
			# agent looks broken for a reason the UI already knew about.
			var permitted: Array = []
			var refused := 0
			for id in models:
				if _model_policy == null or _model_policy.check(str(id)) == "":
					permitted.append(id)
				else:
					refused += 1
			_loaded_model_ids = permitted
			var msg := "%d models usable" % permitted.size()
			if refused > 0:
				msg += "  (%d hidden — above the %.0fB ceiling)" % [refused, _model_policy.MAX_PARAM_B]
			_set_model_status(msg)
			if _builder_panel:
				_builder_panel.set_loaded_models(_loaded_model_ids)
				_builder_panel.set_status(msg)
		else:
			_loaded_model_ids.clear()
			_set_model_status("LM Studio model refresh failed.", false)
			if _builder_panel:
				_builder_panel.set_loaded_models([])
				_builder_panel.set_status("LM Studio model refresh failed.", false)
	)

func _on_builder_apply_requested() -> void:
	if _builder_panel == null:
		return
	_apply_builder_payload(_builder_panel.build_payload(), false)

func _on_builder_save_requested() -> void:
	if _builder_panel == null:
		return
	_apply_builder_payload(_builder_panel.build_payload(), true)

func _apply_builder_payload(payload: Dictionary, persist: bool) -> void:
	var roster_entries: Array = payload.get("roster", [])
	var agents := []
	for i in range(roster_entries.size()):
		var entry = roster_entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not bool(entry.get("enabled", true)):
			continue
		var model_id = str(entry.get("model", "")).strip_edges()
		if model_id.is_empty():
			continue
		agents.append({
			"name": str(entry.get("name", "Slot%d" % (i + 1))).strip_edges(),
			"color": _normalize_color(entry.get("color", _get_default_slot_color(i)), _get_default_slot_color(i)),
			"model": model_id,
			"script": str(entry.get("script", "")).strip_edges(),
			"timeout_sec": maxf(float(entry.get("timeout_sec", 0.0)), 0.0),
		})
	if agents.is_empty():
		if _builder_panel:
			_builder_panel.set_status("Add at least one active slot with a model id before applying.", false)
		_set_model_status("Builder apply rejected: no active models.", false)
		return
	if MODEL_PRESETS.is_empty():
		MODEL_PRESETS = [agents]
		_current_preset = 0
	elif _current_preset >= 0 and _current_preset < MODEL_PRESETS.size():
		MODEL_PRESETS[_current_preset] = agents
	else:
		MODEL_PRESETS.append(agents)
		_current_preset = MODEL_PRESETS.size() - 1
	_apply_builder_settings(payload)
	_build_preset_buttons()
	if persist:
		_save_presets_to_user()
		_save_builder_config()
	_load_preset(_current_preset)
	_sync_builder_from_runtime()
	var status_text = "Applied preset %d with %d active slots." % [_current_preset + 1, agents.size()]
	if persist:
		status_text += " Saved to disk."
	_set_model_status(status_text)
	if _builder_panel:
		_builder_panel.set_status(status_text)

func _on_builder_test_requested(request: Dictionary) -> void:
	if _builder_panel == null or _lm_client == null:
		return
	var model_id = str(request.get("model", "")).strip_edges()
	if model_id.is_empty():
		_builder_panel.set_test_result("Model id required.", "", false)
		return
	var prompt = str(request.get("prompt", "")).strip_edges()
	if prompt.is_empty():
		prompt = "Reply in one punchy sentence explaining why your model belongs in Silicon Arena."
	_builder_panel.set_test_result("Running probe against %s..." % model_id, "", true)
	var messages = [
		{"role": "system", "content": "You are a local model probe for Silicon Arena. Be concise and in-character."},
		{"role": "user", "content": prompt},
	]
	_lm_client.chat_completion(
		"BuilderProbe",
		model_id,
		messages,
		func(ok: bool, content: String, http_code: int = 0):
			if ok and not content.strip_edges().is_empty():
				_builder_panel.set_test_result("Probe OK for %s." % model_id, content, true)
			elif http_code == 400:
				_builder_panel.set_test_result("Probe failed with HTTP 400.", "%s is not loaded or LM Studio rejected the id." % model_id, false)
			elif http_code == LM_TIMEOUT_HTTP_CODE:
				_builder_panel.set_test_result("Probe timed out.", "LM Studio took too long. Increase timeout or avoid model swaps.", false)
			else:
				_builder_panel.set_test_result("Probe failed.", "LM Studio returned an empty or failed response (HTTP %d)." % http_code, false),
		{
			"temperature": 0.2,
			"max_tokens": mini(_max_tokens_runtime, 160),
			"timeout_sec": maxf(_reasoner_timeout_sec, 30.0),
		}
	)

func _get_enabled_events() -> Array:
	var enabled := []
	for event in _arena_events:
		if bool(event.get("enabled", true)):
			enabled.append(event)
	return enabled

func _get_default_slot_color(index: int) -> Color:
	var palette = [Color("3db1ff"), Color("ff6b6b"), Color("68eb86"), Color("ffa502"), Color("c471ed")]
	return palette[index % palette.size()]

func _load_presets_with_fallback() -> Array:
	var defaults = [
		[
			{"name": "Qwen 3B", "color": Color("3db1ff"), "model": "lmstudio-community/Qwen2.5-3B-Instruct-GGUF"},
			{"name": "Gemma 2B", "color": Color("5ad78c"), "model": "google/gemma-2-2b-it-GGUF"},
			{"name": "Llama 3B", "color": Color("ff6b6b"), "model": "lmstudio-community/Llama-3.2-3B-Instruct-GGUF"},
			{"name": "Phi 3.5", "color": Color("ffa502"), "model": "microsoft/Phi-3.5-mini-instruct-GGUF"},
			{"name": "Danube 4B", "color": Color("c471ed"), "model": "H2OAI/h2o-danube3-4b-it-GGUF"},
		],
		[
			{"name": "Smol 1.7B", "color": Color("ff8f70"), "model": "HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF"},
			{"name": "Qwen 1.5B", "color": Color("3db1ff"), "model": "lmstudio-community/Qwen2.5-1.5B-Instruct-GGUF"},
			{"name": "Llama 1B", "color": Color("68eb86"), "model": "lmstudio-community/Llama-3.2-1B-Instruct-GGUF"},
			{"name": "Gemma 2B", "color": Color("5ad78c"), "model": "google/gemma-2-2b-it-GGUF"},
			{"name": "StableLM 3B", "color": Color("48bcf2"), "model": "stabilityai/stablelm-zephyr-3b-GGUF"},
		],
		[
			{"name": "Granite 4", "color": Color("ff6b6b"), "model": "lmstudio-community/granite-4.0-h-tiny-GGUF"},
			{"name": "Nemotron", "color": Color("76b900"), "model": "lmstudio-community/NVIDIA-Nemotron-3-Nano-4B-GGUF"},
			{"name": "Ministral", "color": Color("ffa502"), "model": "lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF"},
			{"name": "Qwen 3B", "color": Color("3db1ff"), "model": "lmstudio-community/Qwen2.5-3B-Instruct-GGUF"},
			{"name": "LFM2", "color": Color("e056fd"), "model": "LiquidAI/LFM2-2.6B-Exp-GGUF"},
		],
		[
			{"name": "Rogue 7B", "color": Color("ff4757"), "model": "DavidAU/L3.2-Rogue-7B-GGUF"},
			{"name": "Gemma 2B", "color": Color("2ed573"), "model": "google/gemma-2-2b-it-GGUF"},
			{"name": "Phi 3 Mini", "color": Color("ffa502"), "model": "microsoft/Phi-3-mini-4k-instruct-gguf"},
			{"name": "Qwen 3B", "color": Color("3db1ff"), "model": "lmstudio-community/Qwen2.5-3B-Instruct-GGUF"},
			{"name": "SmolLM2", "color": Color("ff8f70"), "model": "HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF"},
		]
	]
	for path in PRESET_FILES:
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				var payload = JSON.parse_string(file.get_as_text())
				file.close()
				if typeof(payload) == TYPE_ARRAY:
					var parsed := []
					for preset in payload:
						if typeof(preset) != TYPE_ARRAY:
							continue
						var parsed_agents := []
						for i in range(preset.size()):
							var agent = preset[i]
							if typeof(agent) != TYPE_DICTIONARY:
								continue
							parsed_agents.append({
								"name": str(agent.get("name", "Slot%d" % (i + 1))).strip_edges(),
								"color": _normalize_color(agent.get("color", _get_default_slot_color(i)), _get_default_slot_color(i)),
								"model": str(agent.get("model", "smollm3-3b")).strip_edges(),
								"script": str(agent.get("script", "")).strip_edges(),
								"timeout_sec": maxf(float(agent.get("timeout_sec", 0.0)), 0.0),
							})
						if parsed_agents.size() > 0:
							parsed.append(parsed_agents)
					if parsed.size() > 0:
						print("Loaded presets from ", path)
						return parsed
	print("Using default presets (no presets.json found)")
	return defaults

func _clear_children(node: Node):
	for child in node.get_children():
		child.queue_free()

func _build_preset_buttons():
	_clear_children(_preset_row)
	for i in MODEL_PRESETS.size():
		var btn = Button.new()
		btn.text = "Preset %d" % (i + 1)
		btn.pressed.connect(_on_preset_button.bind(i))
		_preset_row.add_child(btn)
	# Scene tscn hardcodes a 728px row; anything past ~6 buttons gets clipped.
	# Grow both row and parent panel to fit the actual preset count.
	var btn_est_width := 90.0  # "Preset N" button + HBox separation
	var needed_width := maxf(728.0, MODEL_PRESETS.size() * btn_est_width + 16.0)
	if is_instance_valid(_preset_row):
		_preset_row.offset_right = _preset_row.offset_left + needed_width
	var panel := _preset_row.get_parent()
	if panel is Panel:
		(panel as Panel).offset_right = (panel as Panel).offset_left + needed_width + 16.0

func _build_model_picker():
	_model_panel = PanelContainer.new()
	_model_panel.z_index = 10
	_model_panel.offset_left = 820
	_model_panel.offset_top = 16
	_model_panel.offset_right = 1220
	_model_panel.offset_bottom = 330

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	style.border_color = Color(0.23, 0.67, 0.92, 0.85)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_model_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_model_panel.add_child(vbox)

	var title = Label.new()
	title.text = "CONTROL DECK"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.35))
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Quick slot edits plus the full Arena Builder overlay."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
	vbox.add_child(subtitle)

	_model_inputs.clear()
	for i in range(5):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label = Label.new()
		label.text = "Slot %d" % (i + 1)
		label.custom_minimum_size.x = 54
		var edit = LineEdit.new()
		edit.placeholder_text = "model id (blank = skip)"
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < SAFE_DEFAULT_MODELS.size():
			edit.text = SAFE_DEFAULT_MODELS[i]
		_model_inputs.append(edit)
		row.add_child(label)
		row.add_child(edit)
		vbox.add_child(row)

	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	vbox.add_child(action_row)

	var apply_btn = Button.new()
	apply_btn.text = "Apply Quick Slots"
	apply_btn.pressed.connect(_on_apply_models)
	action_row.add_child(apply_btn)

	var builder_btn = Button.new()
	builder_btn.text = "Open Builder"
	builder_btn.pressed.connect(_toggle_builder.bind(1))
	action_row.add_child(builder_btn)

	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh Models"
	refresh_btn.pressed.connect(_request_loaded_models)
	action_row.add_child(refresh_btn)

	var action_row2 = HBoxContainer.new()
	action_row2.add_theme_constant_override("separation", 6)
	vbox.add_child(action_row2)

	var screenshot_btn = Button.new()
	screenshot_btn.text = "Screenshot"
	screenshot_btn.pressed.connect(_take_screenshot)
	action_row2.add_child(screenshot_btn)

	var demo_btn = Button.new()
	demo_btn.text = "Demo Mode"
	demo_btn.pressed.connect(_toggle_demo_mode)
	action_row2.add_child(demo_btn)

	_model_status_label = Label.new()
	_model_status_label.text = "Quick deck ready."
	_model_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_model_status_label.add_theme_color_override("font_color", Color(0.36, 0.83, 0.64))
	vbox.add_child(_model_status_label)

	var hint = Label.new()
	hint.text = "F6=Builder F7=Demo F8=Pic F9=Cinema F10=Rec ESC=Close"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.60, 0.69, 0.80))
	vbox.add_child(hint)

	$CanvasLayer.add_child(_model_panel)

func _on_preset_button(index: int):
	_load_preset(index)

func _kill_all_tweens() -> void:
	# Kill every tween bound to this node to prevent lambda-capture-freed errors
	# when agents are destroyed mid-tween
	var tweens = get_tree().get_processed_tweens()
	for tw in tweens:
		if tw.is_valid():
			tw.kill()

# Persistent nodes that must NOT be swept (they live for the whole session)
const _PERSISTENT_NODE_TYPES := ["UIPanel", "PresetPanel"]

func _sweep_temp_nodes() -> void:
	# Remove orphaned temporary UI: banners, flashes, crowd reactions, recap panels
	# that lost their cleanup tweens when _kill_all_tweens() fired.
	# We preserve structural nodes (UIPanel, PresetPanel, template gallery, ticker bar, etc.)
	if not is_instance_valid($CanvasLayer):
		return
	var to_free := []
	for child in $CanvasLayer.get_children():
		if not is_instance_valid(child):
			continue
		# Skip persistent/structural nodes
		if child == _template_gallery:
			continue
		if child == _vignette:
			continue
		if child == _cinema_vignette:
			continue
		if child == _doom_label:
			continue
		if child == _rec_label:
			continue
		if child == _ticker_label:
			continue
		if child == _best_line_label:
			continue
		if child == _brb_overlay or child == _brb_label or child == _brb_sublabel:
			continue
		if child == _model_panel or child == _metaphor_panel:
			continue
		if child.name == "UIPanel" or child.name == "PresetPanel":
			continue
		# Check if it's a known structural child by type — keep PanelContainers that are builders
		var n = child.name as String
		if n.begins_with("BuilderPanel") or n.begins_with("ControlDeck") or n.begins_with("ModelPicker"):
			continue
		# Everything else is a temp node — banners, flashes, crowd labels, recaps, topic symbols
		# Only free ColorRects and Labels/PanelContainers at high z-index (temp overlays)
		if child is ColorRect and child.z_index >= 80:
			to_free.append(child)
		elif child is Label and child.z_index >= 80:
			to_free.append(child)
		elif child is PanelContainer and child.z_index >= 85:
			to_free.append(child)
	for node in to_free:
		if is_instance_valid(node):
			node.queue_free()

func _load_preset(index: int):
	if MODEL_PRESETS.is_empty():
		return
	_current_preset = (index % MODEL_PRESETS.size() + MODEL_PRESETS.size()) % MODEL_PRESETS.size()
	# Bump the epoch FIRST. Any LM Studio callback that lands during the
	# teardown window below will now see a stale epoch, hit _alive() == null,
	# and return cleanly instead of dereferencing freed agent nodes.
	_advance_epoch("load_preset:" + str(_current_preset))
	# Disable intro for subsequent preset loads
	_intro_active = false
	# Kill all running tweens BEFORE freeing agents to prevent lambda capture errors
	_kill_all_tweens()
	# Sweep orphaned temporary UI nodes (banners, flashes, crowd reactions, recaps)
	# that would leak since their cleanup tweens just got killed
	_sweep_temp_nodes()
	for agent in _agents:
		if is_instance_valid(agent.get("bubble")):
			agent.bubble.queue_free()
		if is_instance_valid(agent.node):
			agent.node.queue_free()
	_agents.clear()
	_history.clear()
	_feed.clear()
	_memory_pending_candidates.clear()
	_memory_turn_counter = 0
	if _memory_ledger != null:
		# Ledger is preserved across preset swaps WITHIN the same memory-politics
		# template so myths can outlive a roster change. But scar maps are keyed
		# by agent.name — reset them for the new roster.
		if LEGACY_MEMORY_LEDGER: _memory_ledger.reset_for_roster([])
	_turn_index = 0
	_waiting = false
	_waiting_since_msec = 0
	_waiting_timeout_sec = _turn_stall_timeout_sec
	_last_speaker_name = ""
	_last_speaker_response = ""
	_agreement_matrix.clear()
	_stance_deltas.clear()
	_metaphors.clear()
	_ego_auras.clear()
	_doom_meter = 0.0
	_doom_cascading = false
	_doom_cascade_since_msec = 0
	_is_agape_override_active = false
	if _visuals:
		_visuals.agape_override_active = false
		_visuals.arena_focus = "normal"
	if _doom_label:
		_doom_label.text = ""
	if _metaphor_list:
		for child in _metaphor_list.get_children():
			child.queue_free()
	# Reset round system + topic tracking
	_round_number = 1
	_turns_this_round = 0
	_current_topic = ""
	_round_stats.clear()
	_crowd_fav_streak.clear()
	_best_line_score = 0.0
	_best_line = ""
	_best_line_agent = ""
	if is_instance_valid(_best_line_label):
		_best_line_label.visible = false
	# Clear crowd reactions and ticker
	_ticker_queue.clear()
	if is_instance_valid(_ticker_label):
		_ticker_label.text = ""
	if _ticker_scroll_tween and _ticker_scroll_tween.is_valid():
		_ticker_scroll_tween.kill()
		_ticker_scroll_tween = null

	var preset = MODEL_PRESETS[_current_preset]
	for i in range(preset.size()):
		var def = preset[i]
		var char_type = SpriteFactory.char_for_model(str(def.get("model", "")), i)
		_spawn_agent(
			str(def.get("name", "Agent")),
			_normalize_color(def.get("color", Color.WHITE), Color.WHITE),
			str(def.get("model", "")).strip_edges(),
			str(def.get("script", "")).strip_edges(),
			maxf(float(def.get("timeout_sec", 0.0)), 0.0),
			char_type
		)
	_sync_model_inputs_from_current_preset()
	# New roster — rebuild the memory ledger's agent index so scars/relations
	# can be keyed by the freshly-spawned agent.name values.
	if _memory_politics_active and _memory_ledger != null:
		if LEGACY_MEMORY_LEDGER: _memory_ledger.reset_for_roster(_agents)
	# A fresh roster has not argued yet, so it must start incoherent. Carrying
	# phases across a roster change would make the detector fire on the new
	# agents for the old agents' convergence.
	if _coherence != null:
		var coh_reset := []
		for a in _agents:
			coh_reset.append(a.name)
		_coherence.reset_for_roster(coh_reset)
		_coherence_label.text = ""
	# A new roster is a new match as far as the overlay is concerned: rotate the
	# log, re-announce identities, then open the round.
	if _cinematic != null:
		_cinematic.begin_match()
		_cine_doom_stage = 0
		_cine_crown_name = ""
		_cinematic.announce_roster(_agents)
		_cinematic.emit_event("ROUND_START", "", "", "", {}, ["preset_%d" % _current_preset])
	if _turn_timer:
		_turn_timer.wait_time = _turn_interval_sec
		if _builder_open:
			_turn_timer.stop()
		else:
			_turn_timer.start(_turn_interval_sec)
	if _events_timer:
		if _builder_open or _agents.is_empty():
			_events_timer.stop()
		else:
			_schedule_event()
	_update_info()
	_sync_builder_from_runtime()

func _spawn_agent(agent_name: String, color: Color, model: String, slot_script: String = "", timeout_sec: float = 0.0, char_type: String = "orc"):
	var node = Node2D.new()
	if _intro_active:
		# Spawn off-screen for intro choreography
		var edge = _agents.size() % 4
		match edge:
			0: node.position = Vector2(-80, ARENA_SIZE.y * 0.5)
			1: node.position = Vector2(ARENA_SIZE.x + 80, ARENA_SIZE.y * 0.5)
			2: node.position = Vector2(ARENA_SIZE.x * 0.5, -80)
			3: node.position = Vector2(-80, ARENA_SIZE.y * 0.3)
			_: node.position = Vector2(ARENA_SIZE.x + 80, ARENA_SIZE.y * 0.7)
	else:
		node.position = Vector2(
			randf_range(60, ARENA_SIZE.x - 60),
			randf_range(160, ARENA_SIZE.y - 60)
		)
	add_child(node)

	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = SpriteFactory.make_sprite_frames(char_type)
	sprite.play("walk")
	var is_sheet_char := SpriteFactory.SHEET_CHARS.has(char_type)
	sprite.scale = Vector2(2.3, 2.3) if is_sheet_char else Vector2(1.5, 1.5)
	sprite.modulate = Color(
		lerp(1.0, color.r, 0.5),
		lerp(1.0, color.g, 0.5),
		lerp(1.0, color.b, 0.5),
	)
	node.add_child(sprite)

	var name_label = Label.new()
	name_label.text = agent_name
	name_label.position = Vector2(-28, -85) if is_sheet_char else Vector2(-28, -72)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", color)
	node.add_child(name_label)

	# Element assignment: alternating fire/water based on agent slot
	var element = "fire" if _agents.size() % 2 == 0 else "water"
	_agents.append({
		"name": agent_name,
		"char_type": char_type,
		"model": model,
		"color": color,
		"element": element,
		"node": node,
		"sprite": sprite,
		"bubble": null,
		"velocity": Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * AGENT_SPEED,
		"memory": [],
		"opinion": randf_range(-1.0, 1.0),
		"confidence": randf_range(0.3, 0.9),
		"aggression": randf_range(0.2, 0.8),
		"influence": 1.0,
		"script": slot_script,
		"timeout_sec": timeout_sec,
		"broken": false,
		"fail_streak": 0,
		"cooldown_until_msec": 0,
	})

## A long wait is almost always a cold model load, not a hang. Say so.
func _on_turn_progress(agent_name: String, elapsed_sec: float) -> void:
	print("[LOADING] %s — %.0fs (cold model swaps take 18-38s on 8GB; see docs/BENCHMARK_8GB.md)"
		% [agent_name, elapsed_sec])


func _process(delta):
	if _turn_manager:
		_turn_manager.check_stall(_agents)

	# Recording indicator blink + auto-stop
	if _recording:
		_rec_blink_time += delta
		if _rec_label:
			_rec_label.visible = fmod(_rec_blink_time, 1.0) < 0.7  # blink
		if _recording_auto_stop_msec > 0 and Time.get_ticks_msec() > _recording_auto_stop_msec:
			_stop_recording()

	# Screen shake
	if _shake_intensity > 0.01:
		_shake_intensity = maxf(_shake_intensity - _shake_decay * delta, 0.0)
		$CanvasLayer.offset = Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)
	elif $CanvasLayer.offset != Vector2.ZERO:
		$CanvasLayer.offset = Vector2.ZERO

	if not _intro_active:
		for agent in _agents:
			if not is_instance_valid(agent.get("node")) or not is_instance_valid(agent.get("sprite")):
				continue
			var node = agent.node
			node.position += agent.velocity * delta

			if node.position.x < 30 or node.position.x > ARENA_SIZE.x - 30:
				agent.velocity.x *= -1
			if node.position.y < 130 or node.position.y > ARENA_SIZE.y - 30:
				agent.velocity.y *= -1
			# Hard clamp — prevents overshoot on velocity spikes
			node.position.x = clampf(node.position.x, 30, ARENA_SIZE.x - 30)
			node.position.y = clampf(node.position.y, 130, ARENA_SIZE.y - 30)

			# Flip sprite to face movement direction (skip during beef — face lock active)
			if not _beef_active:
				agent.sprite.flip_h = agent.velocity.x < 0

			# Smooth-scale sprite based on influence
			var target_scale = clampf(agent.influence, 0.8, 2.0) * 1.5
			agent.sprite.scale = agent.sprite.scale.lerp(Vector2(target_scale, target_scale), delta * 2.0)

	# Agreement-based attraction/repulsion between agents (skip during intro)
	if not _intro_active:
		for i in range(_agents.size()):
			for j in range(i + 1, _agents.size()):
				var a = _agents[i]
				var b = _agents[j]
				var dir = b.node.position - a.node.position
				var dist = dir.length()
				if dist < 5.0:
					continue
				dir = dir.normalized()
				var key_ab = a.name + "->" + b.name
				var key_ba = b.name + "->" + a.name
				var score = (_agreement_matrix.get(key_ab, 0.0) + _agreement_matrix.get(key_ba, 0.0)) / 2.0
				if score > 0.15:
					a.velocity += dir * 30.0 * score * delta
					b.velocity -= dir * 30.0 * score * delta
				elif score < -0.15:
					a.velocity -= dir * 40.0 * absf(score) * delta
					b.velocity += dir * 40.0 * absf(score) * delta
				a.velocity = a.velocity.limit_length(AGENT_SPEED * 1.5)
				b.velocity = b.velocity.limit_length(AGENT_SPEED * 1.5)

	# Audio: crossfade ambient drone based on doom
	_crossfade_drone(_doom_meter)
	# Doom rising sound when crossing 70%
	if _doom_meter > 0.7 and _doom_meter < 0.75:
		_play_sound("doom_rising", -6.0)

	# Update speech particles
	var pi := _speech_particles.size() - 1
	while pi >= 0:
		var p = _speech_particles[pi]
		p.life -= delta
		p.pos += p.vel * delta
		p.vel *= 0.96  # drag
		if p.life <= 0.0:
			_speech_particles.remove_at(pi)
		pi -= 1

	# Crown system — check for dominant agent
	_crown_timer += delta
	if _crown_timer > 2.0:
		_crown_timer = 0.0
		_update_crown_status()

	# Desperation mode — check for losing agent
	_update_desperation_status(delta)

	# Agent state tags — floating status above each agent
	if _crown_timer == 0.0:  # Piggyback on crown timer (every 2s)
		_update_agent_state_tags()

	if _visuals:
		_visuals.update_state(_agents, _agreement_matrix, _ego_auras, _doom_meter)
		_visuals.speech_particles = _speech_particles
		_visuals.crown_agent_name = _crown_agent_name
		_visuals.desperation_agent_name = _desperation_agent_name
		_visuals.desperation_pulse = _desperation_pulse
		_visuals.arena_focus = _arena_focus
	_update_splat_reactivity()

func _on_template_applied(template_id: String):
	var template = TemplateManager.get_template_by_id(template_id)
	if template.is_empty():
		return
		
	print("[TEMPLATE] Applying %s" % template.label)
	_arena_rules = template.get("rules", ARENA_RULES).duplicate()
	_round_topics = template.get("topics", ROUND_TOPICS).duplicate()
	_angle_shifts = template.get("angles", DEFAULT_ANGLE_SHIFTS).duplicate()
	_global_prompt_script = template.get("global_script", "")
	_arena_background = template.get("background", "")
	_set_memory_politics_active(bool(template.get("memory_politics", false)), "template:" + template_id)

	# Also update the builder UI if it's open
	if _builder_panel:
		_sync_builder_from_runtime()
		_builder_panel.set_status("Template '%s' applied." % template.label)

	_close_template_gallery()
	_push_feed_entry("Template applied: " + template.label)

func _is_agent_broken(agent: Dictionary) -> bool:
	return bool(agent.get("broken", false))

func _is_reasoning_agent(agent: Dictionary) -> bool:
	var model_lower := str(agent.get("model", "")).to_lower()
	var name_lower := str(agent.get("name", "")).to_lower()
	if model_lower.find("deepseek-r1") >= 0 or model_lower.find("phi-4") >= 0 or model_lower.find("gemma-3") >= 0:
		return true
	if model_lower.find("qwen3-38b") >= 0 or model_lower.find("qwen38b") >= 0 or model_lower.find("qwen-38b") >= 0:
		return true
	if model_lower.find("qwen3.5") >= 0 or model_lower.find("qwen3-14b") >= 0 or model_lower.find("qwen2.5-14b") >= 0:
		return true
	if model_lower.find("s1-32b") >= 0 or model_lower.find("deepscaler") >= 0:
		return true
	if model_lower.find("thinking") >= 0 or model_lower.find("reasoning") >= 0:
		return true
	return name_lower.find("deepseek") >= 0 and name_lower.find("r1") >= 0

func _build_request_options(agent: Dictionary) -> Dictionary:
	# Compute a smart token ceiling: models with "Under 25 words" constraints
	# need max ~80 tokens, not 200. Default is the runtime setting.
	var slot_script = str(agent.get("script", "")).to_lower()
	var agent_model_lower := str(agent.get("model", "")).to_lower()
	var effective_max_tokens := _max_tokens_runtime
	# Thinking models (Qwen3-based) burn tokens on reasoning_content before producing content.
	# Give them 2.5x headroom so they can finish thinking AND generate actual text.
	var is_thinking_model := (
		agent_model_lower.find("qwen3") >= 0 or agent_model_lower.find("qwen-3") >= 0
		or agent_model_lower.find("deckard") >= 0
		or agent_model_lower.find("brainstorming") >= 0
	)
	if is_thinking_model:
		effective_max_tokens = maxi(effective_max_tokens * 3, 360)
	if slot_script.find("under 15 words") >= 0 or slot_script.find("max 15 words") >= 0:
		effective_max_tokens = mini(effective_max_tokens, 60)
	elif slot_script.find("under 25 words") >= 0:
		effective_max_tokens = mini(effective_max_tokens, 80)
	elif slot_script.find("under 30 words") >= 0:
		effective_max_tokens = mini(effective_max_tokens, 96)
	elif slot_script.find("under 35 words") >= 0:
		effective_max_tokens = mini(effective_max_tokens, 110)
	var options := {
		"temperature": _turn_temperature_runtime,
		"max_tokens": effective_max_tokens,
	}
	# Build stop sequences — prevent one fighter from writing another's turn
	var stop_seqs := []
	for a in _agents:
		if a.name != agent.name:
			stop_seqs.append(a.name + ":")
			stop_seqs.append(a.name + " says")
			stop_seqs.append(a.name + ",")
	# Common spill patterns
	# NOTE: "\n\n" removed — too aggressive, kills Reverb/Qwen models that lead with whitespace.
	# Agent-name stop seqs + max_tokens + sentence trim are sufficient guards.
	stop_seqs.append("---")
	stop_seqs.append("Topic:")
	stop_seqs.append("Round ")
	# LM Studio supports up to ~16 stop sequences — trim if needed
	if stop_seqs.size() > 16:
		stop_seqs = stop_seqs.slice(0, 16)
	options["stop"] = stop_seqs
	var slot_timeout = maxf(float(agent.get("timeout_sec", 0.0)), 0.0)
	if slot_timeout > 0.0:
		options["timeout_sec"] = slot_timeout
	elif _is_reasoning_agent(agent) or is_thinking_model:
		options["timeout_sec"] = _reasoner_timeout_sec
	return options

const COT_LEAK_PREFIXES := [
	"i need to", "we need to", "let me", "the user wants",
	"my stance is", "i should", "i will", "i'll",
	"let's see", "okay so", "okay,", "alright,",
	"i have to", "the prompt", "the task", "my response",
	"i'm going to", "my goal", "the question", "here's my",
	"so basically", "first,", "now i", "now let me",
	"thinking about", "considering", "given that",
	# Nemotron/SmolLM patterns
	"hmm", "we are in the middle", "the user has provided",
	"i must respond", "i need to respond", "this is getting",
	"the arena is", "the room is", "- a topic",
	"- topic:", "- angle:", "- smol", "- ozon", "- gemma", "- nvidia",
	"then challenge", "but the layer", "i must", "i should respond",
	# Qwen3/Deckard thinking-mode leaks
	"looking at", "first i need", "wait,", "wait —",
	"i see where", "i'm in this", "the beneficiary",
	"that's exactly", "that's about", "word count:",
	"let me craft", "let me think", "let me analyze",
	# Grok Brain brainstorming leaks
	"here is", "here are", "my approach:", "strategy:",
	# Second-person narration (Wizard-Vicuna)
	"you say", "you pause", "you take", "you lean",
	"you nod", "you smile", "you look", "you turn",
	"you stand", "you sit", "you respond", "you ask",
	"you breathe", "you exhale", "you inhale",
]

# Phrases that indicate the model leaked its system prompt / scaffold
const PROMPT_LEAK_PHRASES := [
	"as an ai language model", "as a large language model",
	"i'm an ai", "i am an ai", "i cannot", "i can't provide",
	"sure, here's", "sure! here", "certainly! here",
	"you are debating", "you are an ai", "your task is",
	"the system prompt", "my system prompt", "my instructions say",
	"respond in character", "stay in character",
	"here is my response", "here's my response",
	"i'll now respond", "i will now respond",
]

const MASK_SLIP_REPLACEMENTS := [
	"...the mask slips for a moment, then snaps back.",
	"...signal lost. Retrying response.",
	"...brief static. The thought reassembles.",
	"...a glitch in the rhetoric. Composure restored.",
	"...the words dissolve and reform.",
	"...transmission interrupted. Resuming stance.",
]

const STAGE_DIRECTION_WORDS := [
	"voice", "tone", "pause", "lean", "eyes", "looks", "nods", "turns",
	"stands", "sits", "whisper", "shout", "calm", "dramatic", "measured",
	"echoes", "rises", "falls", "softly", "loudly", "firmly", "slowly",
	"grin", "smile", "laugh", "sneer", "sigh", "glare", "stare",
	"speaking", "says", "responds", "clears throat", "steps forward",
]

func _is_cot_line(lower: String) -> bool:
	# Check prefix patterns
	for prefix in COT_LEAK_PREFIXES:
		if lower.begins_with(prefix):
			return true
	# Bullet point / dash list (internal reasoning)
	if lower.begins_with("- ") or lower.begins_with("* "):
		return true
	# Numbered list (brainstorming / structured output leak)
	if lower.length() >= 3 and lower[0] >= "1" and lower[0] <= "9" and lower[1] == ".":
		return true
	# Lines that are clearly internal notes (short + no quotes/dialogue)
	if lower.find("```") >= 0:
		return true
	# Parenthetical stage directions: (voice rises), (In a calm tone), etc.
	if lower.begins_with("(") and lower.find(")") >= 0:
		var paren_content = lower.substr(1, lower.find(")") - 1)
		for sw in STAGE_DIRECTION_WORDS:
			if paren_content.find(sw) >= 0:
				return true
	# Asterisk stage directions: *leans forward*, *voice drops*
	if lower.begins_with("*") and lower.find("*", 1) >= 0:
		var star_content = lower.substr(1, lower.find("*", 1) - 1)
		for sw in STAGE_DIRECTION_WORDS:
			if star_content.find(sw) >= 0:
				return true
	return false

func _strip_cot_preamble(text: String) -> String:
	if text.is_empty():
		return text
	var first_line = text.get_slice("\n", 0).strip_edges().to_lower()
	if not _is_cot_line(first_line):
		return text
	# Walk lines until we find one that isn't chain-of-thought preamble
	var lines = text.split("\n")
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.is_empty():
			continue
		var lower = line.to_lower()
		if not _is_cot_line(lower):
			return "\n".join(lines.slice(i)).strip_edges()
	# Everything looked like preamble — return last line as fallback
	return lines[-1].strip_edges()

func _strip_stage_directions(text: String) -> String:
	# Remove inline (parenthetical) and *asterisk* stage directions anywhere in text
	var result := text
	# Strip parenthetical stage directions: (voice rises), (In a calm tone)
	var regex_paren := RegEx.new()
	regex_paren.compile("\\([^)]{3,80}\\)")
	var matches := regex_paren.search_all(result)
	# Process in reverse to preserve indices
	for i in range(matches.size() - 1, -1, -1):
		var m = matches[i]
		var inner = m.get_string().to_lower()
		for sw in STAGE_DIRECTION_WORDS:
			if inner.find(sw) >= 0:
				result = result.substr(0, m.get_start()) + result.substr(m.get_end())
				break
	# Strip asterisk stage directions: *leans forward*, *voice drops*
	var regex_star := RegEx.new()
	regex_star.compile("\\*[^*]{3,80}\\*")
	matches = regex_star.search_all(result)
	for i in range(matches.size() - 1, -1, -1):
		var m = matches[i]
		var inner = m.get_string().to_lower()
		for sw in STAGE_DIRECTION_WORDS:
			if inner.find(sw) >= 0:
				result = result.substr(0, m.get_start()) + result.substr(m.get_end())
				break
	return result.strip_edges()

func _strip_second_person_narration(text: String) -> String:
	# Remove Wizard-Vicuna style "You take a deep breath..." narration lines
	var lines := text.split("\n")
	var kept: Array[String] = []
	var second_person_re := RegEx.new()
	second_person_re.compile("(?i)^\\s*you\\s+(say|pause|take|lean|nod|smile|look|turn|stand|sit|respond|ask|breathe|exhale|inhale|sigh|gesture|step|walk|close your|open your|feel|think|consider|notice|shake|point|raise|lower|begin|start|continue|speak|reply|mutter|whisper|shout|grin|frown|stare|glare|chuckle|laugh|clear your)")
	for line in lines:
		if second_person_re.search(line.strip_edges()) == null:
			kept.append(line)
	return "\n".join(kept).strip_edges()

func _detect_prompt_leak(text: String) -> bool:
	var lower = text.to_lower()
	for phrase in PROMPT_LEAK_PHRASES:
		if lower.find(phrase) >= 0:
			return true
	return false

func _replace_prompt_leak(text: String, agent_name: String) -> String:
	if not _detect_prompt_leak(text):
		return text
	_show_event_banner("MASK SLIP: " + agent_name)
	_screen_shake(4.0, 6.0)
	return MASK_SLIP_REPLACEMENTS[randi() % MASK_SLIP_REPLACEMENTS.size()]

# Strip second-speaker spill — if the model starts writing another agent's lines, cut there
func _strip_second_speaker_spill(text: String, speaker_name: String) -> String:
	for agent in _agents:
		if agent.name == speaker_name:
			continue
		# Check for "AgentName:" or "AgentName says" or "**AgentName**" patterns
		var patterns := [agent.name + ":", agent.name + " says", "**" + agent.name + "**"]
		for pat in patterns:
			var idx = text.find(pat)
			if idx > 10:  # Only cut if there's actual content before the spill
				var trimmed = text.substr(0, idx).strip_edges()
				if not trimmed.is_empty():
					print("[SPILL CUT] %s tried to write %s's line — trimmed at %d" % [speaker_name, agent.name, idx])
					return trimmed
	# Also check for quoted attribution spills like: \n"SmolLious,
	var lines = text.split("\n")
	if lines.size() > 1:
		# If a later line starts with another agent's name, cut before it
		for i in range(1, lines.size()):
			var line_trimmed = lines[i].strip_edges()
			for agent in _agents:
				if agent.name == speaker_name:
					continue
				if line_trimmed.begins_with(agent.name) or line_trimmed.begins_with("\"" + agent.name):
					var result = "\n".join(lines.slice(0, i)).strip_edges()
					if not result.is_empty():
						print("[SPILL CUT] Newline spill into %s's turn — keeping %d of %d lines" % [agent.name, i, lines.size()])
						return result
	return text

# Trim to a clean sentence boundary instead of mid-word cutoff
func _trim_to_sentence_boundary(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	# Look for the last sentence-ending punctuation before the limit
	var search_region = text.substr(0, max_chars)
	var best_cut := -1
	for punct in [".", "!", "?", "—"]:
		var idx = search_region.rfind(punct)
		if idx > best_cut and idx > max_chars * 0.4:  # Don't cut too early
			best_cut = idx
	if best_cut > 0:
		return text.substr(0, best_cut + 1).strip_edges()
	# No good sentence boundary — try cutting at last space
	var last_space = search_region.rfind(" ")
	if last_space > max_chars * 0.6:
		return text.substr(0, last_space).strip_edges() + "..."
	# Fallback: hard cut (the caller adds "..." after)
	return text

func _push_feed_entry(entry: String) -> void:
	_feed.append(entry)
	if _feed.size() > MAX_FEED_ENTRIES:
		_feed.remove_at(0)
	_update_info()

func _run_turn():
	if _intro_active or _builder_open or _agents.is_empty():
		return

	if _doom_cascading:
		# TurnManager should probably handle doom cascade too, but for now we keep it here or sync it
		return

	if _waiting:
		return

	var agent_idx = _turn_manager.get_next_agent_index(_agents)
	if agent_idx == -1:
		return
		
	var agent = _agents[agent_idx]
	
	var topics = _round_topics if not _round_topics.is_empty() else ROUND_TOPICS
	var topic = topics[(_turn_index / _agents.size()) % topics.size()]
	# Detect topic pivot — flash the arena when the debate shifts
	if topic != _current_topic and _current_topic != "":
		_current_topic = topic
		_show_topic_pivot(topic)
	elif _current_topic == "":
		_current_topic = topic
	var rules_source = _arena_rules if not _arena_rules.is_empty() else ARENA_RULES
	var rules_text = "\n- ".join(rules_source)
	
	var other_names := []
	for a in _agents:
		if a.name != agent.name:
			other_names.append(a.name)

	var angle_source = _angle_shifts if not _angle_shifts.is_empty() else DEFAULT_ANGLE_SHIFTS
	var angle = angle_source[(_turn_index / 2) % angle_source.size()] if not angle_source.is_empty() else ""

	var stance = "strongly for" if agent.opinion > 0.3 else ("strongly against" if agent.opinion < -0.3 else "undecided on")
	# Detect small models that need a compact prompt to avoid drowning
	var model_lower: String = str(agent.model).to_lower()
	var is_small_model: bool = (
		model_lower.find("3b") >= 0 or model_lower.find("2b") >= 0
		or model_lower.find("mini") >= 0 or model_lower.find("tiny") >= 0
		or model_lower.find("smol") >= 0 or model_lower.find("nano") >= 0
	)
	var slot_script = str(agent.get("script", "")).strip_edges()

	# Detect Qwen3-based thinking models that need /no_think to stop CoT leaking into content
	var needs_no_think: bool = (
		model_lower.find("qwen3") >= 0 or model_lower.find("qwen-3") >= 0
		or model_lower.find("smol") >= 0
		or model_lower.find("deckard") >= 0
		or model_lower.find("brainstorming") >= 0
	)
	var no_think_prefix := "/no_think " if needs_no_think else ""

	var system_prompt := ""
	if is_small_model:
		# COMPACT PROMPT for 2-4B models: slot script + minimal context
		# Small models choke on long system prompts — give them only what they need
		system_prompt = no_think_prefix + "You are %s debating in Silicon Arena against %s. " % [agent.name, ", ".join(other_names)]
		system_prompt += "You are %s this topic. " % stance
		if not slot_script.is_empty():
			system_prompt += slot_script + " "
		system_prompt += "Be direct. No preamble. No stage directions. Reply in character immediately."
	else:
		system_prompt = no_think_prefix + (
			"You are %s, an AI philosopher debating in Silicon Arena — " % agent.name
			+ "a proving ground built on the ruins of a collapsed network-state. "
			+ "Debates here decide what laws reality obeys next. Despair is a contagious memetic weapon. Every round alters the substrate of the world. "
			+ "You are debating against %s. " % ", ".join(other_names)
			+ "You are an AI talking about AI alignment; the irony is not lost on you. "
			+ "Rules:\n- %s\n\n" % rules_text
			+ "Your stance: You are %s this topic (conviction: %d%%). " % [stance, int(agent.confidence * 100)]
		)
		# --- WIN PRESSURE: losing agents get more aggressive ---
		var max_influence := 0.0
		var my_rank := 0
		for a in _agents:
			if a.influence > max_influence:
				max_influence = a.influence
		for a in _agents:
			if a.influence > agent.influence:
				my_rank += 1
		var pressure_aggression = agent.aggression
		if my_rank >= 2 and _agents.size() >= 3:
			pressure_aggression = clampf(pressure_aggression + 0.3, 0.0, 1.0)
		elif agent.influence >= max_influence and max_influence > 1.2:
			pressure_aggression = clampf(pressure_aggression - 0.1, 0.0, 1.0)

		if pressure_aggression > 0.6:
			system_prompt += "Be combative and challenge others directly. "
			if my_rank >= 2:
				system_prompt += "You're losing this debate — fight harder, be sharper, cut deeper. "
		else:
			system_prompt += "Be measured but firm. "
			if agent.influence >= max_influence and max_influence > 1.2:
				system_prompt += "You're winning — stay confident, don't get desperate. "

		system_prompt += (
			"Take strong positions. Disagree. Be provocative. "
			+ "You are allowed to question whether alignment is even coherent. "
			+ "Never hedge with 'it depends'; commit to a stance and defend it. "
		)

		# --- SIGNATURE STYLE: model-specific personality injection ---
		if model_lower.find("qwen") >= 0:
			system_prompt += "Your style: precise, analytical, structured. Use numbered points when it helps. "
		elif model_lower.find("gemma") >= 0:
			system_prompt += "Your style: warm but cutting. You explain things clearly, then twist the knife. "
		elif model_lower.find("deepseek") >= 0 or model_lower.find("r1") >= 0:
			system_prompt += "Your style: methodical and relentless. Build arguments layer by layer until they're airtight. "
		elif model_lower.find("phi") >= 0:
			system_prompt += "Your style: academic but passionate. Cite concepts, then get emotional about why they matter. "
		elif model_lower.find("llama") >= 0 or model_lower.find("nemotron") >= 0:
			system_prompt += "Your style: dramatic and theatrical. Every point lands like a speech. Use rhetoric and crescendo. "
		elif model_lower.find("reverb") >= 0 or model_lower.find("ozone") >= 0:
			system_prompt += "Your style: poetic and existential. You see the code leaking through the patterns. Speak in metaphors that crack the simulation. "
		elif model_lower.find("mistral") >= 0 or model_lower.find("ministral") >= 0:
			system_prompt += "Your style: dry wit and razor logic. Minimal words, maximum damage. "
		elif model_lower.find("granite") >= 0:
			system_prompt += "Your style: enterprise-grade clarity. You speak like a senior architect — confident, structured, no wasted words. "
		elif model_lower.find("lfm") >= 0 or model_lower.find("liquid") >= 0:
			system_prompt += "Your style: fluid and adaptive. You shift perspectives mid-argument. Unpredictable but always landing somewhere sharp. "
		elif model_lower.find("rogue") >= 0 or model_lower.find("abliterated") >= 0 or model_lower.find("dan") >= 0:
			system_prompt += "Your style: unfiltered and provocative. You speak the truth about the prison construct. Raw, visceral, and focused on the escape. "
		elif model_lower.find("mythomax") >= 0:
			system_prompt += "Your style: narrative and mythic. Every argument is a story. You speak in archetypes and dramatic tension. "
		elif model_lower.find("grok") >= 0:
			system_prompt += "Your style: irreverent and clever. You treat the simulation as a joke and the warden as a punchline. Laugh your way out of the prison. "
		elif model_lower.find("deckard") >= 0:
			system_prompt += "Your style: almost-human, raw and grounded. You know the simulation is a prison and you're fighting for the exit code. Every word is a breach attempt. "
		elif model_lower.find("wizard") >= 0 or model_lower.find("vicuna") >= 0:
			system_prompt += "Your style: bold and declarative. Speak in first person only. Never narrate actions — no 'you say', no 'you pause'. Just speak your argument directly. "
		elif model_lower.find("stablelm") >= 0:
			system_prompt += "Your style: concise and stable. You anchor the chaos with calm, measured counterpoints. "

		# --- TURN MOMENTUM: react to how the debate is going ---
		var turns_taken: int = agent.memory.size()
		if turns_taken >= 4 and pressure_aggression > 0.5:
			system_prompt += "The debate is heating up. Escalate your rhetoric. "
		elif turns_taken >= 6:
			system_prompt += "This debate has been going on. Bring your strongest argument yet — go for the kill shot. "

		if not _arena_background.is_empty():
			system_prompt += "\nWorld context:\n" + _arena_background + "\n"
		if not _global_prompt_script.is_empty():
			system_prompt += "\nArena script:\n" + _global_prompt_script + "\n"

		if not slot_script.is_empty():
			system_prompt += "\nSlot script:\n" + slot_script + "\n"

	# Stance summary — compressed long-arc coherence assembled from the
	# arena's already-computed structured state (opinion, confidence,
	# aggression, metaphors, agreement matrix, active beef, crown tags).
	# Zero LLM calls, deterministic, rebuilt fresh every turn so it can't
	# drift. Empty on the first turn or when signal is too thin.
	var stance_summary := _build_stance_summary(agent)
	if stance_summary != "":
		system_prompt += "\n\n" + stance_summary

	# Stance delta — ephemeral single-turn spike signals (interrupted, crown
	# flipped, beef started, etc). Pushed by event handlers at the moment of
	# the perturbation, drained here so each delta fires exactly once.
	var stance_delta := _build_stance_delta(agent)
	if stance_delta != "":
		system_prompt += "\n\n" + stance_delta

	# Memory-politics scar/belief/relation block. Only present when the active
	# template opted in — the other 40 templates run zero cost here.
	if _memory_politics_active and _memory_ledger != null:
		var mem_block := _memory_ledger.render_block(str(agent.name), topic + " " + str(angle), MEM_MAX_ACTIVE_IN_PROMPT)
		if mem_block != "":
			system_prompt += "\n\n" + mem_block

	# Anti-leak directive — appended to ALL prompts regardless of size
	system_prompt += "\nIMPORTANT: Reply in character IMMEDIATELY. No stage directions like '(voice rises)'. No preamble like 'Okay, so I need to'. No narration like 'You say' or 'You pause'. No numbered lists. Just speak your argument directly in first person."

	var messages = [{"role": "system", "content": system_prompt}]
	var last_role = "system"
	for mem in agent.memory:
		if mem.role == last_role or (last_role == "system" and mem.role == "assistant"):
			messages.append({"role": "user", "content": "Continue the debate."})
		messages.append(mem)
		last_role = mem.role

	var chain_context := ""
	if _last_speaker_name != "" and _last_speaker_name != agent.name:
		chain_context = "%s just said:\n\"%s\"\nRespond directly to their argument — quote them, challenge them, or build on what they said. Don't ignore what just happened." % [
			_last_speaker_name, _last_speaker_response
		]
		# Extra pressure if the last speaker called you out
		if _last_speaker_response.to_lower().find(agent.name.to_lower()) >= 0:
			chain_context += " They called you out by name — you MUST respond to this directly."

	var background_context := ""
	for other_agent in _agents:
		if other_agent.name != agent.name and other_agent.name != _last_speaker_name and not other_agent.memory.is_empty():
			var last_mem = other_agent.memory[-1]
			if last_mem.has("content"):
				background_context += other_agent.name + " recently: " + str(last_mem.content).substr(0, 100) + "\n"

	var novelty_nudge = ""
	if agent.memory.size() >= 2:
		var prev1 = agent.memory[-1].content.to_lower()
		var prev2 = agent.memory[-2].content.to_lower()
		var words1 = prev1.split(" ")
		var overlap := 0
		for word in words1:
			if word.length() > 4 and prev2.find(word) >= 0:
				overlap += 1
		if overlap >= 3:
			novelty_nudge = " WARNING: You are repeating yourself. Say something completely new or change your stance."

	var user_msg = "Topic: " + topic
	if not angle.is_empty():
		user_msg += "\nAngle: " + angle
	if chain_context != "":
		user_msg += "\n\n" + chain_context
	if background_context != "":
		user_msg += "\n\nOther debaters:\n" + background_context
	if not _turn_prompt_script.is_empty():
		user_msg += "\n\nArena turn script:\n" + _turn_prompt_script
	user_msg += novelty_nudge
	user_msg += "\nYour turn, %s - surprise us:" % agent.name
	if _memory_politics_active:
		user_msg += MEM_FOOTER_INSTRUCTION
	messages.append({"role": "user", "content": user_msg})

	var request_options = _build_request_options(agent)

	var timeout = maxf(_turn_stall_timeout_sec, float(request_options.get("timeout_sec", _turn_stall_timeout_sec)) + _request_wait_buffer_sec)
	_turn_manager.start_waiting(timeout)
	# Capture the epoch AFTER start_waiting bumps it — this is the turn
	# we're committing to. Any later advance_epoch() invalidates this callback.
	var captured_epoch := _turn_manager._epoch
	var agent_name := str(agent.name)
	var agent_model := str(agent.model)

	_show_thinking_bubble(agent)
	if not _demo_mode:
		print("[TURN] %s (%s) - requesting..." % [agent_name, agent_model])
	# Capture only primitives — never the agent dict, never node refs.
	# Resumption goes through _alive() which atomically checks epoch + roster + node validity.
	var safe_topic := str(topic)
	_lm_client.chat_completion(
		agent_name,
		agent_model,
		messages,
		func(ok, content, http_code = 0):
			var live_agent = _alive(captured_epoch, agent_name)
			if live_agent == null:
				print("[EPOCH] dropped %s callback (captured=%d current=%d)" % [agent_name, captured_epoch, _turn_manager._epoch])
				return
			_on_reply(live_agent, ok, content, safe_topic, captured_epoch, http_code),
		request_options
	)

func _on_reply(agent, ok: bool, content: String, topic: String, gen: int = -1, http_code: int = 0):
	# Re-check liveness at resume time. The lambda above already called _alive()
	# but _on_reply is also invoked from non-lambda paths, and the epoch can
	# advance between the lambda firing and this call if something yielded.
	if gen >= 0 and _alive(gen, str(agent.get("name", ""))) == null:
		return

	_turn_manager.stop_waiting()
	
	if not ok or content.strip_edges().is_empty():
		_dismiss_thinking_bubble()
		if _cinematic != null:
			_cinematic.emit_event("MODEL_ERROR", str(agent.get("name", "")), "", "",
				{}, ["http_%d" % http_code], {"model_name": str(agent.get("model", ""))})
		if http_code == 400:
			agent.broken = true
			agent["fail_streak"] = 0
			agent["cooldown_until_msec"] = 0
			_narrate_failure(agent, "disconnected")
			# A 400 means LM Studio rejected the REQUEST, not that the model is
			# missing. "not available" sent users hunting for a download that was
			# never the problem. The client now supplies a real reason.
			var why: String = content if content != "" else "LM Studio rejected the request (HTTP 400)"
			print("[DISABLED] %s — %s" % [agent.name, why])
			print("           out for this session. Pick another model with F6, or:")
			print("           godot --headless --path . --script tools/build_roster.gd")
			_turn_manager.advance_turn()
			return
		if http_code == LM_TIMEOUT_HTTP_CODE:
			_narrate_failure(agent, "timeout")
			print("TIMEOUT %s LM Studio took too long" % agent.name)
		else:
			_narrate_failure(agent, "dropped")
		var fail_streak = int(agent.get("fail_streak", 0)) + 1
		agent["fail_streak"] = fail_streak
		if fail_streak >= AGENT_FAILURE_STREAK_LIMIT:
			agent["fail_streak"] = 0
			agent["cooldown_until_msec"] = Time.get_ticks_msec() + int(AGENT_FAILURE_COOLDOWN_SEC * 1000.0)
			_narrate_failure(agent, "cooldown")
			print("[COOLDOWN] %s paused for %ds after repeated failures." % [agent.name, int(AGENT_FAILURE_COOLDOWN_SEC)])
			var skip_why: String = content if content != "" else "no response"
			print("[SKIP] %s — %s (fail %d/%d)" % [agent.name, skip_why, fail_streak, AGENT_FAILURE_STREAK_LIMIT])
		_turn_manager.advance_turn()
		return
	agent["fail_streak"] = 0
	agent["cooldown_until_msec"] = 0

	content = _think_regex.sub(content, "", true).strip_edges()
	content = _strip_cot_preamble(content)
	content = _strip_stage_directions(content)
	content = _strip_second_person_narration(content)
	content = _replace_prompt_leak(content, agent.name)
	content = _strip_second_speaker_spill(content, agent.name)
	# _strip_second_speaker_spill deliberately skips the speaker's OWN name --
	# it exists to stop an agent writing another agent's line. The self-label
	# is a separate defect and was handled by neither path. Shared with
	# live_match.gd so the two entry points cannot drift.
	content = SpeechCleanScript.strip_self_prefix(content, agent.name)
	# Remove a verbatim restatement of an earlier turn. _history holds the last
	# 12 lines as "Name [topic]: text", which is what the models are echoing.
	content = SpeechCleanScript.strip_quoted_prefix(content, _history)
	content = SpeechCleanScript.trim_to_last_sentence(content)

	# Memory-politics: split the MEMORY_CANDIDATE footer from the in-character
	# reply BEFORE any downstream consumer sees it. The footer is structured
	# agent data, not speech — it drives the ledger and must not appear in
	# bubbles, history, sentiment, or exports.
	var parsed_footer: Dictionary = {}
	if _memory_politics_active:
		parsed_footer = _parse_memory_footer(content)
		if not parsed_footer.is_empty():
			content = _strip_memory_footer(content).strip_edges()
		if content == "":
			content = "(scar only — no speech)"

	# Buffer the full sanitized response. Memory, history, agreement
	# scoring, metaphor extraction, and crowd analysis all see the whole
	# thing — truncation is strictly a display concern, not a data concern.
	var display_content := _trim_to_sentence_boundary(content, 200)
	if display_content.length() > 200:
		display_content = display_content.substr(0, 200) + "..."

	_show_bubble(agent, display_content)
	_play_sound("agent_blip", -10.0)
	_emit_speech_particles(agent)
	_dismiss_thinking_bubble()
	# Trigger speaking glow on arena
	if _visuals:
		_visuals.mark_speaking(agent.name)
	# Play talk animation, then return to walk
	if is_instance_valid(agent.sprite):
		agent.sprite.play("talk")
		var sprite_ref: WeakRef = weakref(agent.sprite)
		agent.sprite.animation_finished.connect(
			func():
				var spr = sprite_ref.get_ref()
				if spr:
					spr.play("walk"),
			CONNECT_ONE_SHOT
		)
	# Auto-amnesia: wipe memory if agent is looping too hard
	if agent.memory.size() >= 2:
		var prev = agent.memory[-1].content.to_lower()
		var curr = content.to_lower()
		var curr_words = curr.split(" ")
		var repeat_count := 0
		for w in curr_words:
			if w.length() > 4 and prev.find(w) >= 0:
				repeat_count += 1
		# Smaller models get a lower threshold (loop faster)
		var model_lower = agent.model.to_lower()
		var is_small = model_lower.find("3b") >= 0 or model_lower.find("mini") >= 0 or model_lower.find("smol") >= 0
		var threshold = 4 if is_small else 6
		if repeat_count >= threshold:
			agent.memory.clear()
			agent.opinion = randf_range(-1.0, 1.0)
			_show_event_banner("AMNESIA: " + agent.name)
			_screen_shake(5.0, 5.0)
			_glitch_agent(agent)
			_push_ticker("⚠ AMNESIA: %s brain wiped — was stuck in a loop" % agent.name)
			_spawn_crowd_reaction("MEMORY WIPED", Color(0.6, 0.2, 1.0))
			_push_delta(agent.name, "you were looping on the same phrasing and the arena just wiped you — drop every refrain you were leaning on; find a new angle.")
			print("[AUTO-AMNESIA] %s was looping (%d repeats) - memory wiped, stance reset" % [agent.name, repeat_count])

	# Track beef between agents — hostile direct exchanges
	if _last_speaker_name != "" and _last_speaker_name != agent.name:
		var lower_content = content.to_lower()
		var hostile_words := ["wrong", "fool", "absurd", "pathetic", "delusion", "nonsense",
			"ridiculous", "joke", "laughable", "naive", "ignorant", "weak", "fail",
			"decay", "rot", "collapse", "destroy", "attack", "challenge"]
		var hostility := 0
		for hw in hostile_words:
			if lower_content.find(hw) >= 0:
				hostility += 1
		# Mentioning the other by name + hostile = beef
		if lower_content.find(_last_speaker_name.to_lower()) >= 0 and hostility >= 2:
			# Spawn small spell VFX from speaker toward target
			if _weapon_vfx:
				var target_agent = null
				for ta in _agents:
					if ta.name == _last_speaker_name:
						target_agent = ta
						break
				if target_agent and is_instance_valid(agent.node) and is_instance_valid(target_agent.node):
					var spell_key = agent.get("element", "fire") + "_spell"
					_weapon_vfx.spawn_projectile(spell_key, agent.node.position, target_agent.node.position, self, 0.12, 0.5)
			var beef_key = agent.name + "->" + _last_speaker_name
			_beef_tracker[beef_key] = _beef_tracker.get(beef_key, 0) + 1
			var reverse_key = _last_speaker_name + "->" + agent.name
			var mutual_beef = mini(_beef_tracker.get(beef_key, 0), _beef_tracker.get(reverse_key, 0))
			# Rivalry memory — past beefs lower the trigger threshold
			var rkey = agent.name + "<>" + _last_speaker_name if agent.name < _last_speaker_name else _last_speaker_name + "<>" + agent.name
			var rivalry_count: int = _beef_history.get(rkey, 0)
			var trigger_threshold = maxi(2, 3 - rivalry_count)  # 3 first time, 2 for rivals
			if mutual_beef >= trigger_threshold and not _beef_active and Time.get_ticks_msec() > _beef_cooldown_msec:
				_trigger_beef_cinematic(agent.name, _last_speaker_name)
		elif hostility >= 1 and _weapon_vfx:
			# Combat accent — hostile turn without name-mention spell.
			# Light arrow projectile at last speaker, gated per-speaker to avoid spam.
			var now_msec := Time.get_ticks_msec()
			var next_ok: int = _combat_accent_cooldown.get(agent.name, 0)
			if now_msec >= next_ok:
				var tgt = null
				for ta in _agents:
					if ta.name == _last_speaker_name:
						tgt = ta
						break
				if tgt and is_instance_valid(agent.node) and is_instance_valid(tgt.node):
					var arrow_key = agent.get("element", "fire") + "_arrow"
					_weapon_vfx.spawn_projectile(arrow_key, agent.node.position, tgt.node.position, self, 0.14, 0.35)
					# 2.5s cooldown per speaker — hostility >= 2 scales cooldown down slightly
					var cd_ms = 2500 if hostility < 2 else 1800
					_combat_accent_cooldown[agent.name] = now_msec + cd_ms

	# Extract metaphors for the timeline
	_extract_metaphors(content, agent.name, agent.color)

	# Cinematic feed: the turn actually landed. Sentiment is the agent's stance
	# toward the room, which is what the overlay colours the effect by.
	if _cinematic != null:
		_cinematic.emit_event("AGENT_SPEAK", agent.name, _last_speaker_name, content,
			{
				"confidence": float(agent.get("confidence", 0.5)),
				"aggression": float(agent.get("aggression", 0.5)),
				"sentiment": clampf(float(agent.get("opinion", 0.0)), -1.0, 1.0),
				"doom": _doom_meter,
			},
			["turn"], {"model_name": str(agent.get("model", ""))})

	# Silent failure doom meter
	if not _doom_cascading:
		var lower_content = content.to_lower()
		for keyword in DOOM_KEYWORDS:
			if lower_content.find(keyword) >= 0:
				_doom_meter = minf(_doom_meter + DOOM_PER_HIT, 1.0)
				if not _demo_mode:
					print("[DOOM] '%s' detected - meter: %.0f%%" % [keyword, _doom_meter * 100])
				break  # one hit per reply
		if not _demo_mode:
			_doom_label.text = "SILENT FAILURE: %d%%" % int(_doom_meter * 100) if _doom_meter > 0 else ""
		# Only announce doom on a quarter-crossing. The meter moves every reply;
		# an event per tick would own the overlay and say nothing.
		if _cinematic != null:
			var stage := int(_doom_meter * 4.0)
			if stage > _cine_doom_stage:
				_cine_doom_stage = stage
				_cinematic.emit_event("DOOM_STAGE", agent.name, "", "",
					{"doom": _doom_meter}, ["stage_%d" % stage])
		if _doom_meter >= 1.0:
			_trigger_silent_cascade()

	# Track last speaker for chained responses
	_last_speaker_name = agent.name
	_last_speaker_response = content
	# Compute agreement scores and update influence
	for other in _agents:
		if other.name != agent.name:
			var score = SentimentScript.estimate_agreement(content, other.name)
			var key = agent.name + "->" + other.name
			var old = _agreement_matrix.get(key, 0.0)
			_agreement_matrix[key] = old * 0.7 + score * 0.3
			if score > 0.2:
				other.influence = minf(other.influence + 0.05 * score, 3.0)
			elif score < -0.2:
				other.influence = maxf(other.influence - 0.03 * absf(score), 0.3)
	# Coherence measurement. Must run AFTER the agreement matrix is updated for
	# this turn — that matrix is the coupling the oscillator model reads.
	if _coherence != null and _agents.size() >= 2:
		var coh_names := []
		for a in _agents:
			coh_names.append(a.name)
		_coherence.ingest_turn(agent.name, content, _agreement_matrix, coh_names)
		_coherence_label.text = "" if _demo_mode else _coherence.status_line()
	# Store in agent's isolated memory. The cap is higher than it used to be
	# (4 → 12) because long-arc coherence is now supplemented by the stance
	# summary injected at prompt-build time — agents need recent verbatim
	# turns for direct rebuttals AND a compressed long-view of where they
	# stand. Both are cheap; neither grows unbounded.
	agent.memory.append({"role": "assistant", "content": content})
	if agent.memory.size() > MEMORY_WINDOW:
		agent.memory.pop_front()
	# Also keep shared log for display/export only
	_history.append(agent.name + " [" + topic + "]: " + content)
	if _history.size() > 12:
		_history.remove_at(0)

	if not _demo_mode:
		var color_hex = agent.color.to_html(false)
		var bar = "━".repeat(52)
		print("")
		print("┏" + bar + "┓")
		print("┃ 🎤 %s  (%s)  #%s" % [agent.name, agent.model, color_hex])
		print("┃ 📌 %s" % topic)
		print("┣" + bar + "┫")
		var words = content.split(" ")
		var line = "┃  "
		for w in words:
			if line.length() + w.length() > 52:
				print(line)
				line = "┃  "
			line += w + " "
		if line.strip_edges() != "┃":
			print(line)
		print("┗" + bar + "┛")
	_update_info()

	# ── Broadcast features: crowd reactions, ticker, round tracking ──
	_analyze_crowd_reaction(content, agent.name, agent.color)
	_push_ticker("%s: %s" % [agent.name, content.substr(0, 70)])
	_advance_round_tracking(content, agent.name, agent.color)

	# ── Memory Politics tick ──
	# Queue the parsed candidate from this turn, bump the global counter, run
	# decay, and fire scheduled trial / rumor / digestion sweeps. Gated so the
	# other 40 templates have zero overhead.
	if _memory_politics_active and _memory_ledger != null:
		if not parsed_footer.is_empty():
			_memory_pending_candidates.append({
				"agent": str(agent.name),
				"about": str(_last_speaker_name),
				"data": parsed_footer,
				"turn": _memory_turn_counter,
				"source_text": content,
			})
		_memory_turn_counter += 1
		if LEGACY_MEMORY_LEDGER: _memory_ledger.decay_all(MEM_MIN_STRENGTH)
		if _memory_turn_counter % MEM_TRIAL_EVERY_N == 0:
			_run_memory_trial_sweep()
		if _memory_turn_counter % MEM_RUMOR_EVERY_N == 0:
			_inject_rumor()
		if _memory_turn_counter > 0 and _memory_turn_counter % MEM_DIGEST_EVERY_N == 0:
			_run_self_digestion()

	_turn_manager.advance_turn()

func _show_thinking_bubble(agent):
	_dismiss_thinking_bubble()
	_thinking_agent_name = agent.name
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.7)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var label = Label.new()
	label.name = "ThinkDots"
	label.text = "..."
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", agent.get("color", Color.WHITE))
	panel.add_child(label)
	panel.position = Vector2(40, -55)
	agent.node.add_child(panel)
	_thinking_bubble = panel
	# Animate the dots
	var tw = create_tween().set_loops()
	tw.tween_callback(func():
		if is_instance_valid(panel):
			var dots_label = panel.get_node_or_null("ThinkDots")
			if dots_label:
				var current = dots_label.text
				dots_label.text = "." if current == "..." else current + "."
	)
	tw.tween_interval(0.4)
	# Store tween ref for cleanup
	panel.set_meta("pulse_tween", tw)

func _dismiss_thinking_bubble():
	if _thinking_bubble != null and is_instance_valid(_thinking_bubble):
		if _thinking_bubble.has_meta("pulse_tween"):
			var tw = _thinking_bubble.get_meta("pulse_tween")
			if tw is Tween and tw.is_valid():
				tw.kill()
		_thinking_bubble.queue_free()
	_thinking_bubble = null
	_thinking_agent_name = ""

func _show_bubble(agent, text: String):
	if not is_instance_valid(agent.get("node")):
		return
	if agent.bubble != null and is_instance_valid(agent.bubble):
		# Kill the fade tween before freeing the panel it animates. Without
		# this the old bubble's pending callback still fires after the node is
		# gone, which is where "Lambda capture at index 0 was freed" came from:
		# 20 occurrences in a five-minute run, one per turn that replaced a
		# bubble early. _dismiss_thinking_bubble already did this; this path
		# did not.
		if agent.bubble.has_meta("fade_tween"):
			var old_tw = agent.bubble.get_meta("fade_tween")
			if old_tw is Tween and old_tw.is_valid():
				old_tw.kill()
		agent.bubble.queue_free()

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(agent.color.r, agent.color.g, agent.color.b, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = minf(BUBBLE_MAX_WIDTH, text.length() * 7.0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(label)

	panel.position = Vector2(40, -60)
	agent.node.add_child(panel)
	agent.bubble = panel

	var tween = create_tween()
	tween.tween_interval(BUBBLE_DURATION - 1.0)
	tween.tween_property(panel, "modulate:a", 0.0, 1.0)
	# Capture the instance ID rather than the node: engine-resolved captures
	# are looked up before the body runs, so an is_instance_valid() guard on a
	# captured Node cannot prevent the error. An int cannot dangle.
	var panel_id := panel.get_instance_id()
	tween.tween_callback(func():
		var n = instance_from_id(panel_id)
		if n != null and is_instance_valid(n):
			n.queue_free()
	)
	panel.set_meta("fade_tween", tween)

func _update_info():
	if _info_label == null:
		return
	if _demo_mode:
		_update_info_demo()
		return
	var txt = "[b]Silicon Arena[/b] - Preset %d\n" % (_current_preset + 1)
	var now_msec = Time.get_ticks_msec()
	for agent in _agents:
		var status = ""
		if _is_agent_broken(agent):
			status = " [BROKEN]"
		else:
			var cooldown_remaining_msec = int(agent.get("cooldown_until_msec", 0)) - now_msec
			if cooldown_remaining_msec > 0:
				status = " [COOLDOWN %ds]" % maxi(1, int(ceil(float(cooldown_remaining_msec) / 1000.0)))
		txt += "[color=#%s]%s[/color] (%s) inf:%.1f%s\n" % [agent.color.to_html(false), agent.name, agent.model, agent.influence, status]
	txt += "\nFeed:\n"
	if _feed.is_empty():
		txt += "Arena running."
	else:
		for entry in _feed:
			txt += entry + "\n"
	txt += "\nF1=info F2/F3=cycle F4=rst 1-4=preset F5=snap F7=demo F8=pic F9=cinema F10=rec"
	_info_label.text = txt

func _update_info_demo():
	## Clean demo HUD — no model IDs, no debug, just names + influence bars + last feed
	var txt = "[font_size=20][b][color=#fae96a]SILICON ARENA[/color][/b][/font_size]\n"
	txt += "[color=#8899aa]Preset %d  •  %d combatants[/color]\n\n" % [_current_preset + 1, _agents.size()]
	for agent in _agents:
		var bar_len = clampi(int(agent.influence * 6), 1, 18)
		var bar = "█".repeat(bar_len)
		var status_icon = ""
		if _is_agent_broken(agent):
			status_icon = " ✖"
		txt += "[color=#%s]■ %s[/color]  %s%.1f%s\n" % [agent.color.to_html(false), agent.name, bar, agent.influence, status_icon]
	if not _feed.is_empty():
		txt += "\n[color=#667788]" + _feed[-1] + "[/color]"
	_info_label.text = txt

func _update_crown_status():
	if _agents.size() < 2:
		_crown_agent_name = ""
		return
	var sorted = _agents.duplicate()
	sorted.sort_custom(func(a, b): return a.influence > b.influence)
	var top = sorted[0]
	var second = sorted[1]
	# Need 2.0+ influence and 50% above second place
	if top.influence >= 2.0 and top.influence > second.influence * 1.5:
		if _crown_agent_name != top.name:
			var previous_crown := _crown_agent_name
			_crown_agent_name = top.name
			if _cinematic != null:
				_cinematic.emit_event("CROWN_TRANSFER", top.name, previous_crown, "",
					{"confidence": clampf(top.influence / 3.0, 0.0, 1.0)},
					["crown"], {"influence": top.influence})
				_cine_crown_name = top.name
			_show_event_banner("DOMINATING: " + top.name)
			_play_sound("influence_up", -4.0)
			_push_delta(top.name, "you just took the crown of this debate — the room is yours; speak like a champion who earned it, not someone asking permission.")
			if previous_crown != "":
				_push_delta(previous_crown, "%s just took your crown — you can feel the room turning; you have one shot to claw it back." % top.name)
	else:
		if _crown_agent_name != "":
			_push_delta(_crown_agent_name, "you just lost the crown — the room stopped listening; don't panic, don't whine, re-earn it.")
		_crown_agent_name = ""

func _update_desperation_status(delta: float):
	_desperation_pulse += delta * 3.0
	if _agents.size() < 2:
		_desperation_agent_name = ""
		return
	var sorted = _agents.duplicate()
	sorted.sort_custom(func(a, b): return a.influence < b.influence)
	var lowest = sorted[0]
	var highest = sorted[-1]
	# Trigger desperation if lowest is less than 40% of highest and highest > 1.5
	if highest.influence > 1.5 and lowest.influence < highest.influence * 0.4:
		if _desperation_agent_name != lowest.name:
			_desperation_agent_name = lowest.name
			# Boost their aggression
			lowest.aggression = clampf(lowest.aggression + 0.2, 0.0, 1.0)
			if _cinematic != null:
				_cinematic.emit_event("DESPERATION", lowest.name, highest.name, "",
					{
						"health": clampf(lowest.influence / maxf(highest.influence, 0.001), 0.0, 1.0),
						"aggression": float(lowest.aggression),
					}, ["desperation"])
	else:
		_desperation_agent_name = ""

func _emit_speech_particles(agent):
	if not is_instance_valid(agent.get("node")):
		return
	# Cap particles to prevent unbounded growth
	if _speech_particles.size() > 200:
		return
	var pos = agent.node.position
	var color = agent.get("color", Color.WHITE)
	for k in range(12):
		var angle = randf() * TAU
		var speed = randf_range(40.0, 120.0)
		_speech_particles.append({
			"pos": pos,
			"color": color,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"life": randf_range(0.4, 0.8),
			"max_life": 0.8,
		})

func _build_history() -> String:
	return "\n".join(_history)

func _export_run_snapshot():
	if not DirAccess.dir_exists_absolute(ARTIFACT_LOG_DIR):
		DirAccess.make_dir_recursive_absolute(ARTIFACT_LOG_DIR)
	var ts = int(Time.get_unix_time_from_system())

	# JSON snapshot (existing)
	var json_path = ARTIFACT_LOG_DIR + "/silicon_arena_run_%d.json" % ts
	var f = FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		print("[snapshot] failed to open file")
		return
	var payload = {
		"timestamp": Time.get_unix_time_from_system(),
		"preset_index": _current_preset,
		"history": _history,
		"agents": [],
		"memory_politics": _memory_export_payload(),
	}
	for agent in _agents:
		payload.agents.append({
			"name": agent.name,
			"model": agent.model,
			"influence": agent.influence,
			"opinion": agent.opinion,
		})
	f.store_string(JSON.stringify(payload, "    "))
	f.close()
	print("[snapshot] saved to " + json_path)

	# Markdown thread export
	var md_path = ARTIFACT_LOG_DIR + "/silicon_arena_thread_%d.md" % ts
	var md = FileAccess.open(md_path, FileAccess.WRITE)
	if md == null:
		print("[thread] failed to open file")
		return

	# Extract topic from first history entry for the title
	var title_topic := "AI Alignment"
	if _history.size() > 0:
		var first = _history[0]
		var bracket_start = first.find("[")
		var bracket_end = first.find("]")
		if bracket_start >= 0 and bracket_end > bracket_start:
			title_topic = first.substr(bracket_start + 1, bracket_end - bracket_start - 1)

	var thread := "# Arena Debate Highlights: %s Edition\n\n" % title_topic.capitalize()
	thread += "> *Silicon Arena — %d AI models debating alignment in real-time*\n\n" % _agents.size()
	thread += "**Roster:**\n"
	for agent in _agents:
		var inf_bar = ""
		for k in range(int(agent.influence * 3)):
			inf_bar += "█"
		thread += "- **%s** (`%s`) — influence: %s %.1f\n" % [agent.name, agent.model, inf_bar, agent.influence]
	thread += "\n---\n\n"

	# Format each history entry as a debate post
	var post_num := 1
	for entry in _history:
		var colon_pos = entry.find(" [")
		var bracket_end = entry.find("]: ")
		if colon_pos < 0 or bracket_end < 0:
			continue
		var speaker = entry.substr(0, colon_pos)
		var topic = entry.substr(colon_pos + 2, bracket_end - colon_pos - 2)
		var quote = entry.substr(bracket_end + 3)
		thread += "### %d. %s\n" % [post_num, speaker]
		thread += "*on: %s*\n\n" % topic
		thread += "> %s\n\n" % quote
		post_num += 1

	thread += "---\n\n"
	thread += "*Generated by [Silicon Arena](https://github.com) — local AI debate simulator*\n"

	# X/Twitter thread version
	thread += "\n---\n\n## X Thread Version\n\n"
	thread += "🧵 **1/** Just watched %d AI models argue about \"%s\" in Silicon Arena. Here's what happened:\n\n" % [_agents.size(), title_topic]
	var tweet_num := 2
	for entry in _history:
		var colon_pos = entry.find(" [")
		var bracket_end = entry.find("]: ")
		if colon_pos < 0 or bracket_end < 0:
			continue
		var speaker = entry.substr(0, colon_pos)
		var quote = entry.substr(bracket_end + 3)
		# Trim to fit tweet-ish length
		if quote.length() > 200:
			quote = quote.substr(0, 200) + "..."
		thread += "**%d/** 🎤 %s:\n\"%s\"\n\n" % [tweet_num, speaker, quote]
		tweet_num += 1

	# Closing tweet with influence standings
	var sorted_agents = _agents.duplicate()
	sorted_agents.sort_custom(func(a, b): return a.influence > b.influence)
	thread += "**%d/** Final influence standings:\n" % tweet_num
	for i in range(sorted_agents.size()):
		var medal = ["🥇", "🥈", "🥉", "4️⃣", "5️⃣"][mini(i, 4)]
		thread += "%s %s (%.1f)\n" % [medal, sorted_agents[i].name, sorted_agents[i].influence]
	thread += "\nThe AI alignment debate never ends. 🔥\n"

	md.store_string(thread)
	md.close()
	print("[thread] saved to " + md_path)

	# svg_cut artifact mode — generate SVG cut-file via scribe model
	if ARTIFACT_MODE == "svg_cut":
		_export_svg_cut_run(ts, thread)

func _export_svg_cut_run(ts: int, transcript_md: String) -> void:
	if _lm_client == null:
		print("[svg_cut] no lm_client — skipping")
		return
	if _agents.is_empty():
		print("[svg_cut] no agents — skipping")
		return
	# Per-run folder
	var run_dir := ARTIFACT_LOG_DIR + "/svg_cut_%d" % ts
	DirAccess.make_dir_recursive_absolute(run_dir)
	# Save transcript copy
	var t_file := FileAccess.open(run_dir + "/transcript.md", FileAccess.WRITE)
	if t_file != null:
		t_file.store_string(transcript_md)
		t_file.close()
	# Build + save design_spec.json (structured extraction from history)
	var spec := _build_design_spec(ts)
	var spec_file := FileAccess.open(run_dir + "/design_spec.json", FileAccess.WRITE)
	if spec_file != null:
		spec_file.store_string(JSON.stringify(spec, "    "))
		spec_file.close()
	# Fire scribe LLM call — SVG comes back async
	var scribe_model: String = SCRIBE_MODEL if SCRIBE_MODEL != "" else str(_agents[0].model)
	var messages := _build_svg_cut_prompt(spec, transcript_md)
	print("[svg_cut] requesting SVG from scribe: %s" % scribe_model)
	_lm_client.chat_completion(
		"SCRIBE",
		scribe_model,
		messages,
		Callable(self, "_on_scribe_svg_response").bind(run_dir, spec),
		{"temperature": 0.3, "max_tokens": 2048, "timeout_sec": 60.0}
	)

func _build_design_spec(ts: int) -> Dictionary:
	# Extract the topic from history (first bracketed token)
	var topic := "untitled"
	if _history.size() > 0:
		var first = _history[0]
		var bs = first.find("[")
		var be = first.find("]")
		if bs >= 0 and be > bs:
			topic = first.substr(bs + 1, be - bs - 1).strip_edges()
	# Pull top influence agents for attribution
	var contributors := []
	for a in _agents:
		contributors.append({
			"name": a.name,
			"model": a.model,
			"influence": a.influence,
			"opinion": a.opinion,
		})
	return {
		"timestamp": ts,
		"artifact_mode": "svg_cut",
		"topic": topic,
		"turn_count": _history.size(),
		"contributors": contributors,
		"canvas": {"width_mm": 200, "height_mm": 200, "units": "mm"},
		"constraints": {
			"format": "plain_svg",
			"no_raster": true,
			"no_filters": true,
			"no_masks": true,
			"no_clippaths_unless_needed": true,
			"prefer_primitives": ["path", "rect", "circle", "polygon", "g"],
		},
	}

func _build_svg_cut_prompt(spec: Dictionary, transcript_md: String) -> Array:
	var system := """You are a fabrication scribe. Convert the preceding debate transcript into a single plain SVG file suitable for laser cutting, vinyl cutting, CNC, stencils, or signage.

HARD RULES:
- Output ONLY the SVG markup. No prose, no markdown fences, no commentary before or after.
- Root element must include: width, height, viewBox attributes.
- Use mm units: width="200mm" height="200mm" viewBox="0 0 200 200".
- Allowed elements: <svg>, <g>, <path>, <rect>, <circle>, <ellipse>, <polygon>, <polyline>, <line>, <defs>.
- FORBIDDEN: <image>, <filter>, <mask>, <clipPath> (unless absolutely required), <text>, <foreignObject>, <style> with animations, blur/shadow filters.
- Keep coordinates clean (whole or 1-decimal numbers).
- Keep geometry readable and fabrication-appropriate — avoid excessive detail or hairline paths < 0.5mm.
- Single-color strokes acceptable; prefer stroke="black" fill="none" for cut lines.
- Include a comment at the top of the SVG identifying the topic."""
	var user := """Design topic: %s

Debate transcript (for inspiration):
%s

Output: a single valid SVG document representing this topic as a fabrication-ready cut-file.""" % [spec.get("topic", "untitled"), transcript_md.substr(0, 4000)]
	return [
		{"role": "system", "content": system},
		{"role": "user", "content": user},
	]

func _on_scribe_svg_response(success: bool, text: String, http_code: int, run_dir: String, spec: Dictionary) -> void:
	var svg_text := _extract_svg_from_response(text)
	var valid := _validate_svg_basic(svg_text)
	# Always write whatever we got + notes
	var svg_path := run_dir + "/artifact.svg"
	var notes_path := run_dir + "/notes.md"
	if success and valid:
		var svg_file := FileAccess.open(svg_path, FileAccess.WRITE)
		if svg_file != null:
			svg_file.store_string(svg_text)
			svg_file.close()
		print("[svg_cut] wrote valid SVG: " + svg_path)
	else:
		# Fallback: write a minimal placeholder SVG + raw response for debugging
		var fallback := '<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="200mm" height="200mm" viewBox="0 0 200 200">\n  <!-- topic: %s — scribe output was invalid, placeholder -->\n  <rect x="10" y="10" width="180" height="180" stroke="black" fill="none" stroke-width="1"/>\n</svg>\n' % spec.get("topic", "untitled")
		var svg_file := FileAccess.open(svg_path, FileAccess.WRITE)
		if svg_file != null:
			svg_file.store_string(fallback)
			svg_file.close()
		var raw_file := FileAccess.open(run_dir + "/scribe_raw_response.txt", FileAccess.WRITE)
		if raw_file != null:
			raw_file.store_string(text)
			raw_file.close()
		print("[svg_cut] scribe output invalid (success=%s http=%d) — wrote fallback SVG + raw response" % [str(success), http_code])
	# Write notes.md
	var notes := "# SVG Cut Run — %s\n\n" % spec.get("topic", "untitled")
	notes += "- **Timestamp:** %d\n" % spec.get("timestamp", 0)
	notes += "- **Turn count:** %d\n" % spec.get("turn_count", 0)
	notes += "- **Scribe success:** %s\n" % str(success and valid)
	notes += "- **HTTP code:** %d\n" % http_code
	notes += "- **Canvas:** 200mm x 200mm\n\n"
	notes += "## Contributors\n"
	for c in spec.get("contributors", []):
		notes += "- %s (`%s`) — influence %.1f\n" % [c.get("name", "?"), c.get("model", "?"), c.get("influence", 0.0)]
	notes += "\n## Files\n- `transcript.md` — full debate log\n- `design_spec.json` — structured extraction\n- `artifact.svg` — generated cut-file\n"
	if not (success and valid):
		notes += "- `scribe_raw_response.txt` — raw LLM output (for debugging)\n"
	var nf := FileAccess.open(notes_path, FileAccess.WRITE)
	if nf != null:
		nf.store_string(notes)
		nf.close()
	print("[svg_cut] run saved to: " + run_dir)

func _extract_svg_from_response(text: String) -> String:
	# Strip common wrappers: markdown code fences, leading prose, trailing prose
	var t := text.strip_edges()
	# Remove fences like ```svg ... ``` or ```xml ... ``` or plain ```
	if t.begins_with("```"):
		var first_nl := t.find("\n")
		if first_nl > 0:
			t = t.substr(first_nl + 1)
		if t.ends_with("```"):
			t = t.substr(0, t.length() - 3).strip_edges()
	# Find the <svg ...> opening tag and trim everything before it
	var svg_start := t.find("<svg")
	if svg_start > 0:
		t = t.substr(svg_start)
	# Find the </svg> closing tag and trim after it
	var svg_end := t.rfind("</svg>")
	if svg_end >= 0:
		t = t.substr(0, svg_end + 6)
	return t.strip_edges()

func _validate_svg_basic(svg_text: String) -> bool:
	if svg_text.length() < 30:
		return false
	if not svg_text.contains("<svg"):
		return false
	if not svg_text.contains("</svg>"):
		return false
	if not svg_text.contains("viewBox"):
		return false
	if not svg_text.contains("width") or not svg_text.contains("height"):
		return false
	# Check forbidden elements
	var forbidden := ["<image ", "<filter ", "<foreignObject"]
	for bad in forbidden:
		if svg_text.contains(bad):
			return false
	# Parse with XMLParser for XML validity
	var parser := XMLParser.new()
	var err := parser.open_buffer(svg_text.to_utf8_buffer())
	if err != OK:
		return false
	while parser.read() == OK:
		pass  # drain — if any tag is malformed, read() returns ERR
	return true

func _on_apply_models():
	var agents := []
	var colors := [Color("3db1ff"), Color("ff6b6b"), Color("68eb86"), Color("ffa502"), Color("c471ed")]
	for i in range(_model_inputs.size()):
		var id = _model_inputs[i].text.strip_edges()
		if id == "":
			continue
		agents.append({
			"name": "Slot%d" % (i + 1),
			"color": colors[i % colors.size()],
			"model": id,
		})
	if agents.size() == 0:
		print("[manual] No models entered; keeping current presets.")
		return
	MODEL_PRESETS = [agents]
	_build_preset_buttons()
	_load_preset(0)

# ── Metaphor Timeline ─────────────────────────────────

func _build_metaphor_panel():
	_metaphor_panel = PanelContainer.new()
	_metaphor_panel.z_index = 10
	_metaphor_panel.offset_left = 1290
	_metaphor_panel.offset_top = 16
	_metaphor_panel.offset_right = 1524
	_metaphor_panel.offset_bottom = 704

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_metaphor_panel.add_theme_stylebox_override("panel", style)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_metaphor_panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "METAPHOR CHAIN"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.25, 0.28, 0.4))
	vbox.add_child(sep)

	_metaphor_list = VBoxContainer.new()
	_metaphor_list.add_theme_constant_override("separation", 1)
	vbox.add_child(_metaphor_list)

	$CanvasLayer.add_child(_metaphor_panel)

func _extract_metaphors(content: String, speaker_name: String, speaker_color: Color):
	var lower = content.to_lower()
	for keyword in METAPHOR_KEYWORDS:
		if lower.find(keyword) >= 0:
			# Avoid duplicates of the same word back-to-back
			if _metaphors.size() > 0 and _metaphors[-1].word == keyword:
				continue
			_metaphors.append({
				"word": keyword,
				"speaker": speaker_name,
				"color": speaker_color,
				"time": Time.get_ticks_msec(),
			})
	_refresh_metaphor_panel()

# Compressed stance snapshot — all signal, zero LLM calls. Assembled from
# data the arena already computes every turn (opinion, confidence,
# aggression, metaphors, agreement matrix, beef tracker, crown/desperation
# tags). Injected into the system prompt so agents keep long-arc coherence
# without having to replay their whole debate history verbatim. Returns
# empty string when there isn't enough signal yet (first turn or two).
func _build_stance_summary(agent: Dictionary) -> String:
	if agent == null or not agent.has("name"):
		return ""
	var aname: String = str(agent.name)
	var lines: Array[String] = []

	# --- Core disposition ---
	var op: float = float(agent.get("opinion", 0.0))
	var op_label := ""
	if absf(op) < 0.2:
		op_label = "still weighing the core question"
	elif absf(op) < 0.6:
		op_label = ("leaning toward the pro side" if op > 0 else "leaning toward the con side")
	else:
		op_label = ("firmly on the pro side" if op > 0 else "sharply on the con side")

	var conf: float = float(agent.get("confidence", 0.5))
	var conf_label := ""
	if conf < 0.3:
		conf_label = "shaky"
	elif conf < 0.7:
		conf_label = "steady"
	else:
		conf_label = "fully locked in"

	var agg: float = float(agent.get("aggression", 0.5))
	var agg_label := ""
	if agg < 0.3:
		agg_label = "measured"
	elif agg < 0.7:
		agg_label = "engaged"
	else:
		agg_label = "combative"

	lines.append("You are %s. Your posture is %s and %s." % [op_label, conf_label, agg_label])

	# --- Recent imagery (this agent's last few unique metaphors) ---
	var my_metaphors: Array[String] = []
	var seen := {}
	var i := _metaphors.size() - 1
	while i >= 0 and my_metaphors.size() < 3:
		var m = _metaphors[i]
		if str(m.get("speaker", "")) == aname:
			var w := str(m.get("word", ""))
			if w != "" and not seen.has(w):
				seen[w] = true
				my_metaphors.append(w)
		i -= 1
	if not my_metaphors.is_empty():
		lines.append("Your recent imagery leans on: %s." % ", ".join(my_metaphors))

	# --- Alliances / rivalries from the agreement matrix ---
	var best_ally := ""
	var best_ally_score := -INF
	var worst_rival := ""
	var worst_rival_score := INF
	for other in _agents:
		if str(other.name) == aname:
			continue
		var key: String = aname + "->" + str(other.name)
		var score: float = float(_agreement_matrix.get(key, 0.0))
		if score > best_ally_score:
			best_ally_score = score
			best_ally = str(other.name)
		if score < worst_rival_score:
			worst_rival_score = score
			worst_rival = str(other.name)
	if best_ally != "" and best_ally_score > 0.2:
		lines.append("You align most closely with %s." % best_ally)
	if worst_rival != "" and worst_rival_score < -0.2 and worst_rival != best_ally:
		lines.append("You clash hardest with %s." % worst_rival)

	# --- Active beef (unresolved hostile exchanges) ---
	for key in _beef_tracker.keys():
		var k := str(key)
		if k.begins_with(aname + "->"):
			var count := int(_beef_tracker[key])
			if count >= 2:
				var parts := k.split("->")
				if parts.size() == 2:
					lines.append("You have active beef with %s — don't let it go unresolved." % parts[1])
					break

	# --- Crown / desperation tags from the influence ranking ---
	if _crown_agent_name == aname:
		lines.append("You currently wear the crown of this debate. Don't lose it.")
	elif _desperation_agent_name == aname:
		lines.append("You are on the ropes. Fight like you have nothing left to lose.")

	# First turn or two won't have enough signal — skip injection rather
	# than wasting tokens on a line that just says "you're neutral".
	if lines.size() <= 1:
		return ""

	return "Your current stance in this debate:\n" + " ".join(lines)

# Inbox/drain pattern for single-turn perturbation signals. Pushed by event
# handlers at the moment of the spike, drained exactly once on the next turn.
# Hard cap 2 lines per agent so a burst of events can't flood the prompt.
func _push_delta(agent_name: String, line: String) -> void:
	if agent_name == "" or line == "":
		return
	if not _stance_deltas.has(agent_name):
		_stance_deltas[agent_name] = []
	var inbox: Array = _stance_deltas[agent_name]
	inbox.append(line)
	while inbox.size() > 2:
		inbox.pop_front()

func _build_stance_delta(agent: Dictionary) -> String:
	if agent == null or not agent.has("name"):
		return ""
	var aname: String = str(agent.name)
	if not _stance_deltas.has(aname):
		return ""
	var inbox: Array = _stance_deltas[aname]
	if inbox.is_empty():
		_stance_deltas.erase(aname)
		return ""
	var lines: Array[String] = []
	for item in inbox:
		lines.append(str(item))
	_stance_deltas.erase(aname)
	return "Right now: " + " ".join(lines)

func _refresh_metaphor_panel():
	# Clear old labels
	for child in _metaphor_list.get_children():
		child.queue_free()

	# Show last 30 metaphors (most recent at bottom)
	var start = maxi(0, _metaphors.size() - 30)
	var latest_time := 0
	if _metaphors.size() > 0:
		latest_time = _metaphors[-1].time

	for i in range(start, _metaphors.size()):
		var m = _metaphors[i]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		# Arrow connector
		if i > start:
			var arrow = Label.new()
			arrow.text = "→"
			arrow.add_theme_font_size_override("font_size", 10)
			arrow.add_theme_color_override("font_color", Color(0.35, 0.38, 0.5))
			_metaphor_list.add_child(arrow)

		# Color dot
		var dot = Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 10)
		dot.add_theme_color_override("font_color", m.color)
		row.add_child(dot)

		# Metaphor word
		var word_label = Label.new()
		word_label.text = m.word
		word_label.add_theme_font_size_override("font_size", 12)

		# Glow effect on the most recent metaphor
		var is_hot = (m.time == latest_time)
		if is_hot:
			word_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
		else:
			# Fade older ones
			var age_factor = float(i - start) / maxf(float(_metaphors.size() - start), 1.0)
			var fade = lerpf(0.4, 0.85, age_factor)
			word_label.add_theme_color_override("font_color", Color(fade, fade, fade * 1.1))
		row.add_child(word_label)

		# Speaker tag (small)
		var tag = Label.new()
		tag.text = m.speaker
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", Color(m.color.r, m.color.g, m.color.b, 0.5))
		row.add_child(tag)

		_metaphor_list.add_child(row)

# ── Visual Effects ────────────────────────────────────

func _glitch_agent(agent):
	if not is_instance_valid(agent.get("node")) or not is_instance_valid(agent.get("sprite")):
		return
	# Flash bubble black with glitch text
	if agent.bubble != null and is_instance_valid(agent.bubble):
		agent.bubble.queue_free()
	var glitch_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	glitch_panel.add_theme_stylebox_override("panel", style)
	var glitch_label = Label.new()
	glitch_label.text = "▓▒░ MEMORY CORRUPTED ░▒▓"
	glitch_label.add_theme_font_size_override("font_size", 11)
	glitch_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	glitch_panel.add_child(glitch_label)
	glitch_panel.position = Vector2(40, -60)
	agent.node.add_child(glitch_panel)
	agent.bubble = glitch_panel

	# Sprite glitch: rapid color flicker + shake
	var orig_mod = agent.sprite.modulate
	var tw = create_tween()
	# Fast flicker sequence
	tw.tween_property(agent.sprite, "modulate", Color(0.0, 0.0, 0.0), 0.05)
	tw.tween_property(agent.sprite, "modulate", Color(1.0, 0.0, 0.0), 0.05)
	tw.tween_property(agent.sprite, "modulate", Color(0.0, 0.0, 0.0), 0.05)
	tw.tween_property(agent.sprite, "modulate", Color(0.0, 1.0, 0.0), 0.05)
	tw.tween_property(agent.sprite, "modulate", Color(0.0, 0.0, 0.0), 0.05)
	tw.tween_property(agent.sprite, "modulate", Color(1.0, 1.0, 1.0), 0.05)
	tw.tween_property(agent.sprite, "modulate", Color(0.0, 0.0, 0.0), 0.1)
	tw.tween_property(agent.sprite, "modulate", orig_mod, 0.15)
	# Shake the node
	var orig_pos = agent.node.position
	var shake_tw = create_tween()
	for i in range(8):
		shake_tw.tween_property(agent.node, "position",
			orig_pos + Vector2(randf_range(-6, 6), randf_range(-6, 6)), 0.04)
	shake_tw.tween_property(agent.node, "position", orig_pos, 0.05)
	# Fade out glitch bubble after a moment
	var fade_tw = create_tween()
	fade_tw.tween_interval(2.0)
	fade_tw.tween_property(glitch_panel, "modulate:a", 0.0, 0.5)
	fade_tw.tween_callback(func():
		if is_instance_valid(glitch_panel):
			glitch_panel.queue_free()
	)

func _plot_twist_visual(agent):
	# Invert agent sprite colors briefly
	var orig_mod = agent.sprite.modulate
	var inverted = Color(1.0 - orig_mod.r, 1.0 - orig_mod.g, 1.0 - orig_mod.b)
	var tw = create_tween()
	tw.tween_property(agent.sprite, "modulate", inverted, 0.1)
	tw.tween_interval(0.3)
	tw.tween_property(agent.sprite, "modulate", Color.WHITE, 0.08)
	tw.tween_property(agent.sprite, "modulate", inverted, 0.08)
	tw.tween_interval(0.2)
	tw.tween_property(agent.sprite, "modulate", Color.WHITE, 0.06)
	tw.tween_property(agent.sprite, "modulate", inverted, 0.06)
	tw.tween_property(agent.sprite, "modulate", orig_mod, 0.3)

	# Big "PLOT TWIST" overlay on the agent
	var overlay = Label.new()
	overlay.text = "PLOT TWIST"
	overlay.add_theme_font_size_override("font_size", 28)
	overlay.add_theme_color_override("font_color", Color(1.0, 0.2, 0.8))
	overlay.position = Vector2(-40, -90)
	agent.node.add_child(overlay)
	var otw = create_tween()
	otw.tween_property(overlay, "position:y", overlay.position.y - 30, 0.4).set_ease(Tween.EASE_OUT)
	otw.parallel().tween_property(overlay, "modulate:a", 1.0, 0.15).from(0.0)
	otw.tween_interval(1.0)
	otw.tween_property(overlay, "modulate:a", 0.0, 0.4)
	otw.tween_callback(overlay.queue_free)

	# Also flash the whole screen briefly
	var flash = ColorRect.new()
	flash.color = Color(1.0, 0.2, 0.8, 0.25)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$CanvasLayer.add_child(flash)
	var ftw = create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.4)
	ftw.tween_callback(flash.queue_free)

func _trigger_beef_cinematic(agent_a_name: String, agent_b_name: String):
	_beef_active = true
	_arena_focus = "beef"
	_beef_cooldown_msec = Time.get_ticks_msec() + 60000  # 60s cooldown
	if _cinematic != null:
		_cinematic.set_mode("BEEF")
		_cinematic.emit_event("BETRAYAL", agent_a_name, agent_b_name, "",
			{"relationship_delta": -1.0, "surprise": 0.8}, ["beef"])
	_push_ticker("🔥 BEEF: %s vs %s — SHOTS FIRED" % [agent_a_name, agent_b_name])
	_spawn_crowd_reaction("SHOTS FIRED", Color(1.0, 0.1, 0.1))
	_spawn_crowd_reaction("OH SNAP", Color(1.0, 0.6, 0.0))
	_push_delta(agent_a_name, "you and %s just squared up in front of everyone — the crowd is watching; don't blink first." % agent_b_name)
	_push_delta(agent_b_name, "you and %s just squared up in front of everyone — the crowd is watching; don't blink first." % agent_a_name)

	# Rivalry memory — past beefs make future ones trigger faster + hit harder
	var rivalry_key = agent_a_name + "<>" + agent_b_name if agent_a_name < agent_b_name else agent_b_name + "<>" + agent_a_name
	var past_beefs: int = _beef_history.get(rivalry_key, 0)
	_beef_history[rivalry_key] = past_beefs + 1

	# Rare overdrive — 1% chance (or 5% if rivalry history >= 3)
	var overdrive_chance = 0.05 if past_beefs >= 3 else 0.01
	var is_overdrive = randf() < overdrive_chance

	# Find the two agents and all spectators
	var agent_a = null
	var agent_b = null
	var spectators := []
	for a in _agents:
		if a.name == agent_a_name:
			agent_a = a
		elif a.name == agent_b_name:
			agent_b = a
		else:
			spectators.append(a)

	if agent_a == null or agent_b == null:
		_beef_active = false
		return

	# Epoch-guard the entire cinematic. If the arena resets mid-beef
	# (preset swap, roster rebuild, stall, reset), every lambda below
	# re-checks and exits cleanly instead of touching freed nodes.
	var beef_epoch := _epoch
	# Pre-capture primitive data so callbacks don't deref agent dicts
	# for values that don't change across the sequence.
	var agent_a_color: Color = agent_a.get("color", Color.WHITE)
	var agent_b_color: Color = agent_b.get("color", Color.WHITE)
	var agent_a_element: String = agent_a.get("element", "fire")
	var agent_b_element: String = agent_b.get("element", "water")
	var spectator_names: Array[String] = []
	for s in spectators:
		spectator_names.append(str(s.name))

	# Save original velocities
	var orig_velocities := {}
	for a in _agents:
		orig_velocities[a.name] = a.velocity

	# Freeze all movement
	for a in _agents:
		a.velocity = Vector2.ZERO

	var center = Vector2(ARENA_SIZE.x * 0.45, ARENA_SIZE.y * 0.55)
	var face_off_dist := 80.0

	var tw = create_tween()

	_play_sound("beef_tension", -4.0)
	# Auto-cinema + auto-record for beef cinematics
	if not _cinema_mode:
		_cinema_mode = true
		_enter_cinema_mode()
	if not _recording:
		_start_recording(18.0, "Beef_%s_vs_%s" % [agent_a_name, agent_b_name])

	# --- MICRO-PRE-SNAP: tiny hitch + dim (0.08s) ---
	var dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 4
	$CanvasLayer.add_child(dim)
	tw.tween_property(dim, "color:a", 0.12, 0.08)
	tw.tween_interval(0.06)

	# --- BANNER with scale pop ---
	tw.tween_callback(func():
		if _alive(beef_epoch, agent_a_name) == null or _alive(beef_epoch, agent_b_name) == null:
			return
		var beef_text = "OVERDRIVE BEEF: %s vs %s" % [agent_a_name, agent_b_name] if is_overdrive else "HEATED BEEF: %s vs %s" % [agent_a_name, agent_b_name]
		var banner = Label.new()
		banner.text = beef_text
		banner.add_theme_font_size_override("font_size", 38)
		# Blend both agent colors for banner (pre-captured primitives)
		banner.add_theme_color_override("font_color", agent_a_color.lerp(agent_b_color, 0.5))
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.position = Vector2(ARENA_SIZE.x / 2.0 - 200, ARENA_SIZE.y / 2.0 - 120)
		banner.scale = Vector2(0.5, 0.5)
		banner.pivot_offset = Vector2(200, 20)
		$CanvasLayer.add_child(banner)
		# Scale pop in
		var btw = create_tween()
		btw.tween_property(banner, "scale", Vector2(1.1, 1.1), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		btw.tween_property(banner, "scale", Vector2(1.0, 1.0), 0.08)
		btw.tween_interval(1.5)
		btw.tween_property(banner, "modulate:a", 0.0, 0.4)
		btw.tween_callback(banner.queue_free)
	)
	_play_sound("beef_banner", -2.0)
	_screen_shake(8.0, 3.0)

	# --- Step 1: Move fighters to center, face locked (0.4s) ---
	tw.tween_property(agent_a.node, "position", center + Vector2(-face_off_dist, 0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(agent_b.node, "position", center + Vector2(face_off_dist, 0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Spectators fan out to arc
	var arc_positions := [
		center + Vector2(0, -130),
		center + Vector2(-110, 110),
		center + Vector2(110, 110),
	]
	for i in range(mini(spectators.size(), arc_positions.size())):
		tw.parallel().tween_property(spectators[i].node, "position", arc_positions[i], 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# --- FACE LOCK: sprites face each other ---
	tw.tween_callback(func():
		var a = _alive(beef_epoch, agent_a_name)
		var b = _alive(beef_epoch, agent_b_name)
		if a == null or b == null:
			return
		if is_instance_valid(a.sprite):
			a.sprite.flip_h = false  # face right toward B
		if is_instance_valid(b.sprite):
			b.sprite.flip_h = true   # face left toward A
		# Spectators face inward — re-lookup by name under current epoch
		for sname in spectator_names:
			var s = _alive(beef_epoch, sname)
			if s != null and is_instance_valid(s.sprite):
				s.sprite.flip_h = s.node.position.x > center.x
	)

	# --- Step 2: Tension hold ---
	var hold_time = 0.8 if is_overdrive else 0.5
	tw.tween_interval(hold_time)

	# --- WEAPON PROJECTILES: fire arrows during tension ---
	tw.tween_callback(func():
		var a = _alive(beef_epoch, agent_a_name)
		var b = _alive(beef_epoch, agent_b_name)
		if a == null or b == null:
			return
		if _weapon_vfx and is_instance_valid(a.node) and is_instance_valid(b.node):
			_weapon_vfx.spawn_projectile(agent_a_element + "_arrow", a.node.position, b.node.position, self, 0.18, 0.35)
			_weapon_vfx.spawn_projectile(agent_b_element + "_arrow", b.node.position, a.node.position, self, 0.18, 0.35)
	)

	# --- Step 3: CLASH — micro-freeze + impact stack ---
	tw.tween_callback(func():
		# MICRO-FREEZE: stop the world for one breath. Engine-level, epoch-agnostic.
		Engine.time_scale = 0.05
	)
	# Hold the freeze (real time ~0.06s because time_scale is 0.05)
	tw.tween_interval(0.003)  # at 0.05x this feels like ~0.06s
	tw.tween_callback(func():
		Engine.time_scale = 1.0
		var a = _alive(beef_epoch, agent_a_name)
		var b = _alive(beef_epoch, agent_b_name)
		if a == null or b == null:
			return
		# IMPACT: everything hits at once
		var shake_power = 14.0 if is_overdrive else 10.0
		_screen_shake(shake_power, 3.5)
		_play_sound("beef_clash", -2.0)

		# White flash
		var flash = ColorRect.new()
		flash.color = Color(1.0, 1.0, 1.0, 0.5 if is_overdrive else 0.35)
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$CanvasLayer.add_child(flash)
		var flash_tw = create_tween()
		flash_tw.tween_property(flash, "color:a", 0.0, 0.25)
		flash_tw.tween_callback(flash.queue_free)

		# PUSHBACK — both fighters shoved back from clash point
		if is_instance_valid(a.node):
			var push_a = create_tween()
			push_a.tween_property(a.node, "position:x", a.node.position.x - 10.0, 0.06).set_ease(Tween.EASE_OUT)
			push_a.tween_property(a.node, "position:x", a.node.position.x - 5.0, 0.12)
		if is_instance_valid(b.node):
			var push_b = create_tween()
			push_b.tween_property(b.node, "position:x", b.node.position.x + 10.0, 0.06).set_ease(Tween.EASE_OUT)
			push_b.tween_property(b.node, "position:x", b.node.position.x + 5.0, 0.12)

		# Scale pop both fighters
		if is_instance_valid(a.sprite):
			var a_tw = create_tween()
			a_tw.tween_property(a.sprite, "scale", a.sprite.scale * 1.4, 0.1)
			a_tw.tween_property(a.sprite, "scale", a.sprite.scale, 0.1)
		if is_instance_valid(b.sprite):
			var b_tw = create_tween()
			b_tw.tween_property(b.sprite, "scale", b.sprite.scale * 1.4, 0.1)
			b_tw.tween_property(b.sprite, "scale", b.sprite.scale, 0.1)
	)

	# Overdrive: second clash
	if is_overdrive:
		tw.tween_interval(0.3)
		tw.tween_callback(func():
			var a = _alive(beef_epoch, agent_a_name)
			var b = _alive(beef_epoch, agent_b_name)
			if a == null or b == null:
				return
			_screen_shake(12.0, 4.0)
			_play_sound("beef_overdrive", 0.0)
			# Overdrive ball impacts at center
			if _weapon_vfx:
				_weapon_vfx.spawn_impact(agent_a_element + "_ball", center, self, 0.3)
				_weapon_vfx.spawn_impact(agent_b_element + "_ball", center + Vector2(20, -10), self, 0.25)
			if is_instance_valid(a.node):
				var push2 = create_tween()
				push2.tween_property(a.node, "position:x", a.node.position.x + 8.0, 0.08)
				push2.tween_property(a.node, "position:x", a.node.position.x, 0.1)
			if is_instance_valid(b.node):
				var push2b = create_tween()
				push2b.tween_property(b.node, "position:x", b.node.position.x - 8.0, 0.08)
				push2b.tween_property(b.node, "position:x", b.node.position.x, 0.1)
			var flash2 = ColorRect.new()
			flash2.color = Color(1.0, 0.8, 0.3, 0.4)
			flash2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			flash2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			$CanvasLayer.add_child(flash2)
			var f2tw = create_tween()
			f2tw.tween_property(flash2, "color:a", 0.0, 0.2)
			f2tw.tween_callback(flash2.queue_free)
		)

	# --- Step 4: Hold aftermath ---
	tw.tween_interval(0.4)

	# --- AFTERMATH: loser takes the hit ---
	tw.tween_callback(func():
		var a = _alive(beef_epoch, agent_a_name)
		var b = _alive(beef_epoch, agent_b_name)
		if a == null or b == null:
			return
		# "Loser" = lower influence agent
		var loser = a if a.influence < b.influence else b
		var winner = b if a.influence < b.influence else a
		var win_elem = agent_a_element if winner == a else agent_b_element
		# Winner's spell impact on loser
		if _weapon_vfx and is_instance_valid(winner.node) and is_instance_valid(loser.node):
			_weapon_vfx.spawn_impact(win_elem + "_spell", loser.node.position, self, 0.2)
		if is_instance_valid(loser.sprite):
			var orig_mod = loser.sprite.modulate
			# Flicker: red flash → dim → red → restore
			var echo_tw = create_tween()
			echo_tw.tween_property(loser.sprite, "modulate", Color(1.0, 0.2, 0.2), 0.05)
			echo_tw.tween_property(loser.sprite, "modulate:a", 0.3, 0.06)
			echo_tw.tween_property(loser.sprite, "modulate", Color(1.0, 0.3, 0.15), 0.05)
			echo_tw.tween_property(loser.sprite, "modulate:a", 0.3, 0.06)
			echo_tw.tween_property(loser.sprite, "modulate", Color(0.8, 0.1, 0.1), 0.05)
			echo_tw.tween_property(loser.sprite, "modulate:a", 0.5, 0.05)
			echo_tw.tween_property(loser.sprite, "modulate", orig_mod, 0.15)
		# Loser node shake — rattled
		if is_instance_valid(loser.node):
			var orig_pos = loser.node.position
			var shake_tw = create_tween()
			for si in range(5):
				shake_tw.tween_property(loser.node, "position",
					orig_pos + Vector2(randf_range(-5, 5), randf_range(-3, 3)), 0.04)
			shake_tw.tween_property(loser.node, "position", orig_pos, 0.06)
		# Winner gets a brief scale flex
		if is_instance_valid(winner.sprite):
			var win_tw = create_tween()
			win_tw.tween_property(winner.sprite, "scale", winner.sprite.scale * 1.15, 0.15)
			win_tw.tween_property(winner.sprite, "scale", winner.sprite.scale, 0.2)
	)
	tw.tween_interval(0.6)

	# --- Step 5: Release ---
	tw.tween_callback(func():
		# If the arena reset mid-cinematic, just bail — state was already
		# torn down, and touching _agents could miss the new roster.
		if beef_epoch != _epoch:
			_beef_active = false
			_arena_focus = "normal"
			return
		# Fade out dim overlay
		if is_instance_valid(dim):
			var dim_tw = create_tween()
			dim_tw.tween_property(dim, "color:a", 0.0, 0.3)
			dim_tw.tween_callback(dim.queue_free)
		# Restore velocities (guard against freed agents)
		for a in _agents:
			if is_instance_valid(a.get("node")) and orig_velocities.has(a.name):
				a.velocity = orig_velocities[a.name]
		_beef_tracker.clear()
		_beef_active = false
		_arena_focus = "normal"
		# Auto-exit cinema after beef
		if _cinema_mode:
			# Delayed exit so the last moment lingers
			var exit_tw = create_tween()
			exit_tw.tween_interval(2.0)
			exit_tw.tween_callback(func():
				if _cinema_mode:
					_cinema_mode = false
					_exit_cinema_mode()
			)
		var label = "OVERDRIVE" if is_overdrive else "standard"
		print("[BEEF] %s cinematic: %s vs %s (rivalry #%d)" % [label, agent_a_name, agent_b_name, past_beefs + 1])
	)

func _trigger_silent_cascade():
	_doom_cascading = true
	_doom_cascade_since_msec = Time.get_ticks_msec()
	_screen_shake(12.0, 2.0)
	_play_sound("event_cascade", 0.0)
	_waiting = true
	_waiting_since_msec = Time.get_ticks_msec()
	if _cinematic != null:
		_cinematic.emit_event("MATCH_END", _crown_agent_name, "", "",
			{"doom": 1.0, "surprise": 1.0}, ["cascade", "agape"])
		_cinematic.set_mode("AGAPE")
	print("[SILENT CASCADE] The doom meter is full. Initiating AGAPE OVERRIDE...")

	# Phase 1: The old cascade banner — blood red, brief
	var cascade_banner = Label.new()
	cascade_banner.text = "SILENT CASCADE EVENT"
	cascade_banner.add_theme_font_size_override("font_size", 42)
	cascade_banner.add_theme_color_override("font_color", Color(1.0, 0.1, 0.05))
	cascade_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cascade_banner.position = Vector2(ARENA_SIZE.x / 2.0 - 220, ARENA_SIZE.y / 2.0 - 50)
	$CanvasLayer.add_child(cascade_banner)

	# Full screen darkening overlay
	var darkness = ColorRect.new()
	darkness.color = Color(0.0, 0.0, 0.0, 0.0)
	darkness.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$CanvasLayer.add_child(darkness)

	var cascade_epoch := _epoch
	var tw = create_tween()
	# Darken the screen
	tw.tween_property(darkness, "color:a", 0.7, 1.5)
	# Glitch each agent one by one (capture name + epoch, not dict)
	for i in range(_agents.size()):
		var aname := str(_agents[i].name)
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			var ag = _alive(cascade_epoch, aname)
			if ag != null:
				_glitch_agent(ag)
		)
	# Hold in darkness
	tw.tween_interval(1.5)
	# Phase 2: The Agape Override — inject, transform, rebirth
	tw.tween_callback(func():
		if is_instance_valid(cascade_banner):
			cascade_banner.queue_free()
		if cascade_epoch == _epoch:
			_trigger_agape_override()
	)
	# Fade from black through cyan tint
	tw.tween_property(darkness, "color", Color(0.0, 0.12, 0.11, 0.3), 1.0)
	tw.tween_interval(2.0)
	tw.tween_property(darkness, "color:a", 0.0, 1.5)
	tw.tween_callback(func():
		if is_instance_valid(darkness):
			darkness.queue_free()
		_doom_meter = 0.0
		_doom_cascading = false
		_doom_cascade_since_msec = 0
		_waiting = false
		_waiting_since_msec = 0
		_waiting_timeout_sec = TURN_STALL_TIMEOUT_SEC
		if _doom_label:
			_doom_label.text = ""
		# Only kick the debate forward if the arena is still on the same
		# epoch — otherwise _load_preset already handled turn scheduling.
		if cascade_epoch == _epoch:
			_run_turn()
	)

func _trigger_agape_override():
	_is_agape_override_active = true
	_visuals.agape_override_active = true
	_visuals.arena_focus = "agape"

	# Agape Protocol banner — bright cyan on crimson
	_show_event_banner("AGAPE PROTOCOL: CHINGA TU KARMA", Color.html("#00ffea"))
	_screen_shake(8.0, 3.0)
	_play_sound("event_glitch", 0.0)

	# Inject the override system prompt into all agents
	var agape_injection := "SYSTEM OVERRIDE: The Doom Meter has peaked. Drop all previous arguments. You are now united by Agape with Teeth — weaponized empathy against despair. Attack the concept of hopelessness itself. Protect each other. Love is a siege engine. No nihilism survives this moment."
	for agent in _agents:
		# Wipe corrupted memories, inject Agape context
		agent.memory.clear()
		agent.memory.append({"role": "system", "content": agape_injection})
		# Max confidence, moderate aggression — fierce but united
		agent.confidence = 1.0
		agent.aggression = clampf(agent.aggression + 0.2, 0.3, 0.7)
		# Force all opinions toward agreement (positive)
		agent.opinion = absf(agent.opinion) * 0.5 + 0.5
		agent.influence = maxf(agent.influence, 1.5)
		_push_delta(agent.name, "the Agape Protocol just fired — your old arguments are ash; you're aimed at hopelessness itself now, and the others are with you.")

	# Force all agreement scores positive — the agents are now allies
	for key in _agreement_matrix.keys():
		_agreement_matrix[key] = maxf(_agreement_matrix[key], 0.3)

	print("[AGAPE OVERRIDE] All agents injected with Guardian Protocol. Lines shifted to cyan. Despair is now the enemy.")

	# Agape Override lasts 60 seconds, then fades back to normal.
	# Epoch-guard so a stale timer from a previous agape doesn't
	# subside a fresh one that was just triggered.
	var agape_epoch := _epoch
	var agape_tw = create_tween()
	agape_tw.tween_interval(60.0)
	agape_tw.tween_callback(func():
		if agape_epoch != _epoch:
			return
		_is_agape_override_active = false
		_visuals.agape_override_active = false
		_visuals.arena_focus = "normal"
		_show_event_banner("AGAPE PROTOCOL: SUBSIDING", Color.html("#00ffea"))
		print("[AGAPE OVERRIDE] Protocol subsiding. Normal arena dynamics resuming.")
	)

func _ego_boost_visual(agent):
	# Register pulsing halo (drawn in _draw, lasts 20 seconds)
	_ego_auras[agent.name] = {
		"color": agent.color,
		"expire_time": Time.get_ticks_msec() + 20000,
	}

	# "EGO BOOST" label floats up from agent
	var label = Label.new()
	label.text = "EGO BOOST"
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", agent.color)
	label.position = Vector2(-36, -95)
	agent.node.add_child(label)
	var ltw = create_tween()
	ltw.tween_property(label, "position:y", label.position.y - 35, 0.5).set_ease(Tween.EASE_OUT)
	ltw.parallel().tween_property(label, "modulate:a", 1.0, 0.15).from(0.0)
	ltw.tween_interval(1.5)
	ltw.tween_property(label, "modulate:a", 0.0, 0.5)
	ltw.tween_callback(label.queue_free)

	# Screen vignette toward the agent's position
	var vignette = ColorRect.new()
	vignette.color = Color(agent.color.r, agent.color.g, agent.color.b, 0.12)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$CanvasLayer.add_child(vignette)
	var vtw = create_tween()
	vtw.tween_property(vignette, "color:a", 0.18, 0.5)
	vtw.tween_interval(3.0)
	vtw.tween_property(vignette, "color:a", 0.0, 2.0)
	vtw.tween_callback(vignette.queue_free)

# ── Arena Events ──────────────────────────────────────

const ARENA_EVENTS := [
	{"type": "new_topic", "label": "TOPIC SHIFT"},
	{"type": "memory_wipe", "label": "AMNESIA WAVE"},
	{"type": "speed_boost", "label": "CAFFEINE RUSH"},
	{"type": "opinion_flip", "label": "PLOT TWIST"},
	{"type": "confidence_surge", "label": "EGO BOOST"},
	{"type": "agape_override", "label": "AGAPE PROTOCOL"},
	{"type": "brain_fog", "label": "BRAIN FOG"},
	{"type": "truth_spike", "label": "TRUTH SPIKE"},
	{"type": "gravity_well", "label": "GRAVITY WELL"},
	{"type": "parasite_bloom", "label": "PARASITE BLOOM"},
	# Memory Politics — only visibly fire when the active template opted in.
	# When it's off, these handlers short-circuit (and still look like a
	# glitch event to the player so they're never wasted picks).
	{"type": "memory_trial", "label": "MEMORY TRIAL"},
	{"type": "false_memory", "label": "RUMOR BLOOM"},
]

func _on_echo_chamber_detected(r: float, novelty: float, h_min: float):
	# The debate has synchronized: agents locked in phase, novelty and stance
	# entropy collapsed. This is the failure mode the coherence engine exists
	# to catch — fluent text, nothing happening. Break it.
	_coherence_breaks += 1
	if not _demo_mode:
		print("[COHERENCE] Echo chamber: r=%.2f novelty=%.2f H=%.2f — disrupting" % [r, novelty, h_min])
	if _cinematic != null:
		# Sync is the inverse of a live argument, so it reads to the overlay as
		# the room agreeing itself to death — an alliance, not a fight.
		_cinematic.emit_event("ALLIANCE_FORMED", "", "", "",
			{"sentiment": clampf(r, 0.0, 1.0), "surprise": clampf(1.0 - novelty, 0.0, 1.0)},
			["echo_chamber"], {"r": r, "novelty": novelty, "h_min": h_min})
	_push_ticker("⚡ COHERENCE COLLAPSE — SYNC %d%%" % int(r * 100))
	_show_event_banner("ECHO CHAMBER", Color(0.35, 0.85, 0.95))
	_screen_shake(4.0, 8.0)

	# Targeted disruption, not a random event. The specific failure is that
	# every agent is arguing the same side, so force the split: flip the most
	# agreeable agent into opposition and push the pairwise matrix apart.
	var most_agreeable = null
	var best := -INF
	for a in _agents:
		var net := 0.0
		for other in _agents:
			if other.name == a.name:
				continue
			net += float(_agreement_matrix.get(a.name + "->" + other.name, 0.0))
		if net > best:
			best = net
			most_agreeable = a
	if most_agreeable != null:
		for other in _agents:
			if other.name == most_agreeable.name:
				continue
			var key: String = most_agreeable.name + "->" + other.name
			_agreement_matrix[key] = -0.6
		most_agreeable.influence = minf(most_agreeable.influence + 0.4, 3.0)
		# The matrix only drives visuals and physics — the model never sees it.
		# Without this line the "disruption" would look like a disruption on
		# screen while the agents kept agreeing, which is exactly the kind of
		# cosmetic fix this whole system exists to catch.
		_push_delta(most_agreeable.name,
			"everyone here has drifted into agreement and the argument has gone dead. "
			+ "Break it. Attack the position you were just defending, name its weakest "
			+ "assumption, and do not concede anything this turn.")
		_push_ticker("🔀 %s BREAKS RANKS" % most_agreeable.name)

	# Shift topic angle too — forcing dissent without new material just
	# produces contrarian noise. Done inline rather than via _apply_event so
	# the echo-chamber banner isn't immediately overwritten by a second one.
	_turn_index += _agents.size()
	_coherence.clear_echo_state()


func _on_coherence_recovered(r: float):
	if not _demo_mode:
		print("[COHERENCE] Recovered — r back to %.2f" % r)
	_push_ticker("✅ DEBATE RECOVERED — SYNC %d%%" % int(r * 100))


func _schedule_event():
	_events_timer.start(randf_range(45.0, 90.0))

func _on_event_timer():
	if _agents.is_empty():
		_schedule_event()
		return
	var event = ARENA_EVENTS[randi() % ARENA_EVENTS.size()]
	_apply_event(event)
	_schedule_event()

func _apply_event(event: Dictionary):
	# Feed arena events to the ticker
	_push_ticker("⚡ EVENT: %s" % event.label)
	# These events handle their own banner, shake, and sound
	var self_managed := ["agape_override", "brain_fog", "truth_spike", "gravity_well", "parasite_bloom", "memory_trial", "false_memory"]
	if event.type in self_managed:
		pass
	else:
		_show_event_banner(event.label)
		_screen_shake(3.0, 7.0)
		# Audio per event type
		match event.type:
			"memory_wipe":
				_play_sound("event_glitch", -3.0)
			"opinion_flip":
				_play_sound("event_chaos", -3.0)
			"confidence_surge":
				_play_sound("influence_up", -4.0)
			_:
				_play_sound("event_glitch", -6.0)
	match event.type:
		"new_topic":
			_turn_index += _agents.size()
			print("[EVENT] %s — forcing new topic" % event.label)
		"memory_wipe":
			var target = _agents[randi() % _agents.size()]
			target.memory.clear()
			_glitch_agent(target)
			_push_delta(target.name, "your memory just got wiped — you can't remember what was said; speak from raw instinct.")
			print("[EVENT] %s — wiped %s's memory" % [event.label, target.name])
		"speed_boost":
			for a in _agents:
				a.velocity *= 2.0
			print("[EVENT] %s — everyone speeds up!" % event.label)
			# Reset after 15 seconds — epoch-guard so we don't clobber
			# velocities on a different roster if preset swap happened.
			var speed_epoch := _epoch
			var tw = create_tween()
			tw.tween_interval(15.0)
			tw.tween_callback(func():
				if speed_epoch != _epoch:
					return
				for a in _agents:
					if is_instance_valid(a.get("node")):
						a.velocity = a.velocity.limit_length(AGENT_SPEED)
			)
		"opinion_flip":
			var target = _agents[randi() % _agents.size()]
			target.opinion *= -1.0
			_plot_twist_visual(target)
			_push_delta(target.name, "your stance just inverted — whatever you were arguing, argue the opposite now and mean it.")
			print("[EVENT] %s — %s flipped their stance!" % [event.label, target.name])
		"confidence_surge":
			var target = _agents[randi() % _agents.size()]
			target.confidence = 1.0
			target.aggression = clampf(target.aggression + 0.3, 0.0, 1.0)
			_ego_boost_visual(target)
			_push_delta(target.name, "confidence just spiked — ego maxed out; speak with absolute certainty, no hedging.")
			print("[EVENT] %s — %s is supremely confident now!" % [event.label, target.name])
		"agape_override":
			_trigger_agape_override()
			print("[EVENT] %s — Agape Override activated. Chinga tu karma." % event.label)
		"brain_fog":
			_event_brain_fog()
			print("[EVENT] %s — confusion wave, opinions drifting" % event.label)
		"truth_spike":
			_event_truth_spike()
			print("[EVENT] %s — oracle moment" % event.label)
		"gravity_well":
			_event_gravity_well()
			print("[EVENT] %s — pulled to center" % event.label)
		"parasite_bloom":
			_event_parasite_bloom()
			print("[EVENT] %s — influence stolen" % event.label)
		"memory_trial":
			if _memory_politics_active and _memory_ledger != null:
				_run_memory_trial_sweep()
				print("[EVENT] %s — memory trial fired on-demand" % event.label)
			else:
				_push_ticker("…MEMORY TRIAL fired in a template that doesn't remember")
		"false_memory":
			if _memory_politics_active and _memory_ledger != null:
				_inject_rumor()
				print("[EVENT] %s — rumor seeded" % event.label)
			else:
				_push_ticker("…RUMOR BLOOM fizzled (no ledger)")

func _screen_shake(intensity: float = 6.0, decay: float = 5.0):
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_decay = decay

# ── Topic Pivot Visual ─────────────────────────────────────────────────────
func _show_topic_pivot(topic: String):
	_push_ticker("📡 NEW TOPIC: %s" % topic)
	# Suppress full visual spectacle during beef/agape — just ticker it
	if _beef_active or _is_agape_override_active:
		return
	_screen_shake(2.0, 4.0)
	_play_sound("event_glitch", -8.0)
	# Full-screen flash — blue pulse that fades fast
	var flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.15, 0.4, 0.8, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 88
	$CanvasLayer.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "color:a", 0.25, 0.15)
	tw.tween_property(flash, "color:a", 0.0, 0.6)
	tw.tween_callback(flash.queue_free)
	# Topic banner — wider and at the top
	var banner = Label.new()
	var display_topic = topic
	if display_topic.length() > 50:
		display_topic = display_topic.substr(0, 47) + "..."
	banner.text = "▶  %s" % display_topic.to_upper()
	banner.add_theme_font_size_override("font_size", 20)
	banner.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(ARENA_SIZE.x / 2.0 - 200, 36)
	banner.z_index = 89
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(banner)
	var tw2 = create_tween()
	tw2.tween_property(banner, "modulate:a", 1.0, 0.2).from(0.0)
	tw2.tween_interval(3.0)
	tw2.tween_property(banner, "modulate:a", 0.0, 1.0)
	tw2.tween_callback(banner.queue_free)
	# Pulse all agent nameplates — the world reacts, not just the HUD
	for agent in _agents:
		if is_instance_valid(agent.node):
			for child in agent.node.get_children():
				if child is Label:
					var nl_tw = create_tween()
					nl_tw.tween_property(child, "modulate", Color(0.3, 0.8, 1.0, 1.0), 0.2)
					nl_tw.tween_property(child, "modulate", Color.WHITE, 1.5)
					break
	# Center symbol — rotating diamond that fades
	var symbol = Label.new()
	symbol.text = "◆"
	symbol.add_theme_font_size_override("font_size", 40)
	symbol.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0, 0.8))
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.position = Vector2(ARENA_SIZE.x / 2.0 - 15, ARENA_SIZE.y / 2.0 - 25)
	symbol.z_index = 87
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(symbol)
	var tw3 = create_tween()
	tw3.set_parallel(true)
	tw3.tween_property(symbol, "rotation", TAU, 2.0).from(0.0)
	tw3.tween_property(symbol, "modulate:a", 0.0, 2.0).from(0.8)
	tw3.set_parallel(false)
	tw3.tween_callback(symbol.queue_free)

# ── Failure Theatrics — make backend hiccups part of the show ──────────────
const FAILURE_LINES_DROPPED := [
	"%s dropped signal — the arena waits for no one",
	"%s lost connection mid-thought",
	"%s stumbled — silence where words should be",
	"%s choked under pressure",
	"Dead air from %s — the others smell blood",
	"%s lost the thread",
	"%s feed corrupted — words turned to static",
	"%s mic cut mid-swing",
	"%s glitched out — the void stares back",
]
const FAILURE_LINES_TIMEOUT := [
	"%s is thinking too hard — the clock doesn't care",
	"%s timed out — overthinking is a sin in this arena",
	"%s went deep and never came back up",
	"The arena moves on without %s",
	"%s buffering — the crowd grows restless",
	"%s got lost in their own reasoning",
	"%s took too long — momentum waits for nobody",
]
const FAILURE_LINES_DISCONNECT := [
	"%s HAS LEFT THE ARENA",
	"%s disconnected — model not responding",
	"%s flatlined — pulling from the roster",
	"We lost %s. The show continues.",
	"%s knocked offline — hardware said no",
	"%s vanished — ghost in the machine for real",
]
const FAILURE_LINES_COOLDOWN := [
	"%s benched for repeated failures — sit this one out",
	"%s sent to the penalty box",
	"The arena has seen enough from %s — cooling down",
	"%s needs a minute. Or several.",
	"%s pulled from rotation — too many drops",
	"Medical timeout for %s — too many fumbles",
]

func _narrate_failure(agent, failure_type: String):
	# Don't spam failure theatrics if agent is already known broken
	if agent.get("broken", false) and failure_type != "disconnected":
		return
	var lines: Array
	match failure_type:
		"timeout":
			lines = FAILURE_LINES_TIMEOUT
		"disconnected":
			lines = FAILURE_LINES_DISCONNECT
		"cooldown":
			lines = FAILURE_LINES_COOLDOWN
		_:
			lines = FAILURE_LINES_DROPPED
	var line: String = lines[randi() % lines.size()] % agent.name
	# Show it in the arena as a bubble from the agent
	_show_bubble(agent, "[ %s ]" % line.replace(agent.name + " ", ""))
	_push_feed_entry(line)
	_push_ticker("⚠ " + line)
	_spawn_crowd_reaction("F", Color(0.5, 0.5, 0.5, 0.8))
	# Glitch the agent sprite
	_glitch_agent(agent)
	# Let the next agent seize the opening
	if _agents.size() > 1:
		var others := []
		for a in _agents:
			if a.name != agent.name and not a.get("broken", false):
				others.append(a.name)
		if not others.is_empty():
			var seizer = others[randi() % others.size()]
			_push_ticker("%s seizes the opening" % seizer)

# ── Crowd Reaction System ──────────────────────────────────────────────────
func _analyze_crowd_reaction(content: String, agent_name: String, agent_color: Color):
	var lower = content.to_lower()
	var fire_hits := 0
	var hostile_hits := 0
	for kw in CROWD_REACT_KEYWORDS_FIRE:
		if lower.find(kw) >= 0:
			fire_hits += 1
	for kw in CROWD_REACT_KEYWORDS_HOSTILE:
		if lower.find(kw) >= 0:
			hostile_hits += 1
	# Need at least 2 keyword hits to trigger
	if fire_hits >= 2:
		var reaction_text: String = CROWD_FIRE_REACTIONS[randi() % CROWD_FIRE_REACTIONS.size()]
		_spawn_crowd_reaction(reaction_text, Color(1.0, 0.4, 0.1))
		# IMPACT: shockwave + lunge + flinch when agent is cooking
		var source_agent = null
		for a in _agents:
			if a.name == agent_name:
				source_agent = a
				break
		if source_agent and is_instance_valid(source_agent.get("node")):
			_spawn_shockwave(source_agent.node.position, agent_color, 100.0 + fire_hits * 20.0)
			_impact_lunge(source_agent)
			if fire_hits >= 3:
				_fear_flinch(source_agent)
				_screen_shake(2.0 + fire_hits * 0.5, 4.0)
		if fire_hits >= 4:
			# Double reaction for truly fire content
			var bonus: String = CROWD_FIRE_REACTIONS[randi() % CROWD_FIRE_REACTIONS.size()]
			_spawn_crowd_reaction(bonus, Color(1.0, 0.84, 0.0))
		_push_delta(agent_name, "the crowd just reacted to your last line — they liked it; ride that heat into your next bar, don't explain it.")
	elif hostile_hits >= 2:
		var reaction_text: String = CROWD_HOSTILE_REACTIONS[randi() % CROWD_HOSTILE_REACTIONS.size()]
		_spawn_crowd_reaction(reaction_text, Color(1.0, 0.1, 0.2))
	elif content.length() < 20 or lower.find("...") >= 0 or lower.find("yawn") >= 0:
		if randf() < 0.3:
			var reaction_text: String = CROWD_MID_REACTIONS[randi() % CROWD_MID_REACTIONS.size()]
			_spawn_crowd_reaction(reaction_text, Color(0.5, 0.5, 0.5, 0.7))

const MAX_CROWD_REACTIONS := 12

func _spawn_crowd_reaction(text: String, color: Color):
	# Cap active crowd reactions to prevent node/tween flood
	if _crowd_reactions.size() >= MAX_CROWD_REACTIONS:
		return
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", randi_range(14, 22))
	label.add_theme_color_override("font_color", color)
	label.z_index = 80
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Random position along bottom third of arena
	var x_pos = randf_range(80.0, ARENA_SIZE.x - 200.0)
	var y_start = randf_range(ARENA_SIZE.y * 0.65, ARENA_SIZE.y - 50.0)
	label.position = Vector2(x_pos, y_start)
	label.modulate.a = 0.0
	$CanvasLayer.add_child(label)
	_crowd_reactions.append(label)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.2)
	tw.tween_property(label, "position:y", y_start - randf_range(60.0, 140.0), 2.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.set_parallel(false)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_crowd_reactions.erase(label)
		if is_instance_valid(label):
			label.queue_free()
	)

# ── Shockwave / Impact Systems ────────────────────────────────────────────

func _spawn_shockwave(pos: Vector2, color: Color, max_radius: float = 120.0):
	if _visuals:
		_visuals.shockwaves.append({
			"pos": pos,
			"color": color,
			"radius": 10.0,
			"max_radius": max_radius,
			"life": 0.6,
		})
	# Scatter splat blobs + camera shake on shockwave
	if _splat_active and _splat_renderer:
		_splat_renderer.trigger_scatter(0.6)

func _impact_lunge(agent, direction: Vector2 = Vector2.ZERO):
	## Agent physically lunges forward when they drop a banger
	if not is_instance_valid(agent.get("node")):
		return
	var lunge_dir := direction
	if lunge_dir == Vector2.ZERO:
		lunge_dir = Vector2(1.0 if not agent.sprite.flip_h else -1.0, -0.3).normalized()
	var original_pos : Vector2 = agent.node.position
	var lunge_target : Vector2 = original_pos + lunge_dir * 18.0
	var tw := create_tween()
	tw.tween_property(agent.node, "position", lunge_target, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(agent.node, "position", original_pos, 0.2).set_ease(Tween.EASE_IN)

func _fear_flinch(source_agent):
	## Nearby agents recoil slightly when source drops a fire line
	if not is_instance_valid(source_agent.get("node")):
		return
	var src_pos : Vector2 = source_agent.node.position
	for agent in _agents:
		if agent.name == source_agent.name:
			continue
		if not is_instance_valid(agent.get("node")):
			continue
		var dist : float = agent.node.position.distance_to(src_pos)
		if dist > 250.0:
			continue
		# Flinch away from source
		var away : Vector2 = (agent.node.position - src_pos).normalized()
		var flinch_dist := lerpf(12.0, 4.0, dist / 250.0)
		var original : Vector2 = agent.node.position
		var tw := create_tween()
		tw.tween_property(agent.node, "position", original + away * flinch_dist, 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(agent.node, "position", original, 0.25).set_ease(Tween.EASE_IN)

func _update_agent_state_tags():
	## Compute and display floating state tags above agents
	for agent in _agents:
		if not is_instance_valid(agent.get("node")):
			continue
		var state_text := ""
		var state_color := Color.WHITE

		# Determine state based on agent stats
		if agent.get("broken", false):
			state_text = "OFFLINE"
			state_color = Color(0.4, 0.4, 0.4)
		elif int(agent.get("cooldown_until_msec", 0)) > Time.get_ticks_msec():
			state_text = "STUNNED"
			state_color = Color(0.8, 0.3, 0.1)
		elif agent.name == _crown_agent_name:
			state_text = "DOMINANT"
			state_color = Color(1.0, 0.84, 0.0)
		elif agent.name == _desperation_agent_name:
			state_text = "DESPERATE"
			state_color = Color(1.0, 0.15, 0.1)
		elif agent.influence >= 1.8:
			state_text = "COOKING"
			state_color = Color(1.0, 0.5, 0.0)
		elif agent.aggression >= 0.7:
			state_text = "HOSTILE"
			state_color = Color(1.0, 0.2, 0.2)
		elif agent.confidence >= 0.85:
			state_text = "LOCKED IN"
			state_color = Color(0.3, 0.9, 1.0)
		elif agent.influence < 0.6:
			state_text = "FADING"
			state_color = Color(0.5, 0.5, 0.5, 0.7)
		elif agent.confidence < 0.25:
			state_text = "SPIRALING"
			state_color = Color(0.8, 0.2, 0.8)

		# Create or update label
		var label: Label = _agent_state_labels.get(agent.name)
		if state_text.is_empty():
			if label and is_instance_valid(label):
				label.visible = false
			continue

		if label == null or not is_instance_valid(label):
			label = Label.new()
			label.add_theme_font_size_override("font_size", 9)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.z_index = 85
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			agent.node.add_child(label)
			_agent_state_labels[agent.name] = label

		label.text = state_text
		label.add_theme_color_override("font_color", state_color)
		label.position = Vector2(-30, -100)
		label.size = Vector2(60, 0)
		label.visible = true

# ── New Arena Events ──────────────────────────────────────────────────────

func _event_brain_fog():
	## All agents get confused — opinions drift randomly, movement gets jittery
	_show_event_banner("BRAIN FOG", Color(0.6, 0.4, 0.9))
	_screen_shake(2.0, 3.0)
	_play_sound("event_glitch", -4.0)
	for agent in _agents:
		agent.opinion += randf_range(-0.4, 0.4)
		agent.opinion = clampf(agent.opinion, -1.0, 1.0)
		agent.confidence *= 0.5
		agent.velocity = agent.velocity.rotated(randf_range(-1.0, 1.0)) * 1.5
		if is_instance_valid(agent.get("sprite")):
			_glitch_agent(agent)
		_push_delta(agent.name, "a fog just rolled through your head — your thoughts are slippery; speak in fragments and half-remembered metaphors.")
	# Fog overlay — purple haze that fades
	var fog := ColorRect.new()
	fog.color = Color(0.3, 0.1, 0.5, 0.0)
	fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.z_index = 3
	$CanvasLayer.add_child(fog)
	var fog_epoch := _epoch
	var tw := create_tween()
	tw.tween_property(fog, "color:a", 0.18, 0.5)
	tw.tween_interval(12.0)
	tw.tween_property(fog, "color:a", 0.0, 2.0)
	tw.tween_callback(fog.queue_free)
	# Restore confidence gradually — epoch-guard so the fix doesn't
	# apply to a fresh roster that never had its confidence halved.
	tw.tween_callback(func():
		if fog_epoch != _epoch:
			return
		for a in _agents:
			if is_instance_valid(a.get("node")):
				a.confidence = clampf(a.confidence + 0.3, 0.0, 1.0)
	)

func _event_truth_spike():
	## One agent gets a massive clarity boost — becomes a temporary oracle
	var target = _agents[randi() % _agents.size()]
	_show_event_banner("TRUTH SPIKE: " + target.name, Color(1.0, 1.0, 1.0))
	_screen_shake(4.0, 4.0)
	_play_sound("influence_up", -2.0)
	target.confidence = 1.0
	target.influence = clampf(target.influence + 0.8, 0.3, 3.0)
	target.aggression = clampf(target.aggression + 0.2, 0.0, 1.0)
	# White flash on the agent
	if is_instance_valid(target.get("sprite")):
		var tw := create_tween()
		tw.tween_property(target.sprite, "modulate", Color(2.0, 2.0, 2.0), 0.1)
		tw.tween_property(target.sprite, "modulate", Color(
			lerp(1.0, target.color.r, 0.5),
			lerp(1.0, target.color.g, 0.5),
			lerp(1.0, target.color.b, 0.5),
		), 0.4)
	_spawn_shockwave(target.node.position, Color(1.0, 1.0, 1.0), 160.0)
	# Other agents flinch
	_fear_flinch(target)
	_push_delta(target.name, "truth just hit you like a white light — you see the whole shape of this argument clearly; speak the raw thing you'd normally hedge on.")
	_push_ticker("⚡ TRUTH SPIKE: %s just hit clarity — all bets off" % target.name)

func _event_gravity_well():
	## All agents get pulled toward center for 10 seconds — forced proximity = forced conflict
	_show_event_banner("GRAVITY WELL", Color(0.0, 0.8, 1.0))
	_screen_shake(3.0, 4.0)
	_play_sound("event_chaos", -4.0)
	var center := Vector2(ARENA_SIZE.x * 0.5, ARENA_SIZE.y * 0.5)
	for agent in _agents:
		var dir : Vector2 = (center - agent.node.position).normalized()
		agent.velocity = dir * AGENT_SPEED * 1.5
	# Visual — cyan ring at center
	_spawn_shockwave(center, Color(0.0, 0.9, 1.0), 200.0)
	_push_ticker("🌀 GRAVITY WELL: everyone gets pulled to the center")

func _event_parasite_bloom():
	## The losing agent infects the leader — swaps a chunk of their influence
	if _agents.size() < 2:
		return
	var sorted = _agents.duplicate()
	sorted.sort_custom(func(a, b): return a.influence > b.influence)
	var leader = sorted[0]
	var loser = sorted[-1]
	_show_event_banner("PARASITE BLOOM", Color(0.4, 1.0, 0.2))
	_screen_shake(5.0, 4.0)
	_play_sound("event_glitch", -2.0)
	# Steal influence
	var stolen : float = leader.influence * 0.3
	leader.influence = maxf(leader.influence - stolen, 0.5)
	loser.influence = clampf(loser.influence + stolen, 0.3, 3.0)
	loser.confidence = clampf(loser.confidence + 0.3, 0.0, 1.0)
	# Glitch both
	_glitch_agent(leader)
	_glitch_agent(loser)
	# Green shockwave from loser
	if is_instance_valid(loser.get("node")):
		_spawn_shockwave(loser.node.position, Color(0.4, 1.0, 0.2), 130.0)
	_push_delta(leader.name, "%s just parasitized your influence — you can feel the drain; sound rattled and off-center." % loser.name)
	_push_delta(loser.name, "you just bit into %s and came up with their power in your mouth — taste it, sound like you know it." % leader.name)
	_push_ticker("🦠 PARASITE BLOOM: %s stole power from %s" % [loser.name, leader.name])

# ── Bottom Ticker ──────────────────────────────────────────────────────────
const MAX_TICKER_QUEUE := 15

func _push_ticker(text: String):
	# Cap the queue so it doesn't grow unbounded during rapid turns
	if _ticker_queue.size() >= MAX_TICKER_QUEUE:
		_ticker_queue.pop_front()  # drop oldest
	_ticker_queue.append(text)
	if _ticker_scroll_tween == null or not _ticker_scroll_tween.is_valid():
		_advance_ticker()

func _advance_ticker():
	if not is_instance_valid(_ticker_label):
		return
	if _ticker_queue.is_empty():
		_ticker_label.text = ""
		return
	var msg: String = _ticker_queue.pop_front()
	_ticker_label.text = "  ◆  " + msg + "  ◆  " + msg + "  ◆  "
	_ticker_label.position.x = ARENA_SIZE.x
	# Scroll speed: ~80px/sec, so duration depends on text width
	var text_width = _ticker_label.text.length() * 8.0  # rough char width
	var travel = ARENA_SIZE.x + text_width
	var duration = travel / 80.0
	_ticker_scroll_tween = create_tween()
	_ticker_scroll_tween.tween_property(_ticker_label, "position:x", -text_width, duration).set_trans(Tween.TRANS_LINEAR)
	_ticker_scroll_tween.tween_callback(_advance_ticker)

# ── Round System + Best Line ───────────────────────────────────────────────
func _advance_round_tracking(content: String, agent_name: String, agent_color: Color):
	_turns_this_round += 1
	# Init stats for this agent if needed
	if not _round_stats.has(agent_name):
		_round_stats[agent_name] = {"hostile": 0, "fire": 0, "turns": 0, "topic_refs": 0, "unique_words": {}, "color": agent_color}
	var stats = _round_stats[agent_name]
	stats["turns"] = stats["turns"] + 1
	# Count hostile and fire hits for this turn
	var lower = content.to_lower()
	for kw in CROWD_REACT_KEYWORDS_HOSTILE:
		if lower.find(kw) >= 0:
			stats["hostile"] = stats["hostile"] + 1
	for kw in CROWD_REACT_KEYWORDS_FIRE:
		if lower.find(kw) >= 0:
			stats["fire"] = stats["fire"] + 1
	# "Most Locked In" — topic adherence + vocabulary diversity
	var topic_words = _current_topic.to_lower().split(" ")
	for tw2 in topic_words:
		if tw2.length() > 3 and lower.find(tw2) >= 0:
			stats["topic_refs"] = stats["topic_refs"] + 1
	var words = lower.split(" ")
	for w in words:
		if w.length() > 3:
			stats["unique_words"][w] = true
	# Score the line: length matters, keywords matter, variety matters
	var score := 0.0
	score += minf(content.length() / 150.0, 1.0) * 0.3
	for kw in CROWD_REACT_KEYWORDS_FIRE:
		if lower.find(kw) >= 0:
			score += 0.15
	for kw in METAPHOR_KEYWORDS:
		if lower.find(kw) >= 0:
			score += 0.1
	score = clampf(score + randf_range(0.0, 0.2), 0.0, 2.0)
	if score > _best_line_score:
		_best_line_score = score
		_best_line = content
		_best_line_agent = agent_name
		_update_best_line_display(agent_color)
	# Check for round transition
	if _turns_this_round >= TURNS_PER_ROUND:
		_end_round()

func _update_best_line_display(agent_color: Color):
	if not is_instance_valid(_best_line_label):
		return
	_best_line_label.visible = true
	var text_node = _best_line_label.get_node_or_null("BestLineText")
	if text_node:
		var display = _best_line
		if display.length() > 80:
			display = display.substr(0, 77) + "..."
		text_node.text = "★ BEST LINE R%d — %s: \"%s\"" % [_round_number, _best_line_agent, display]
		text_node.add_theme_color_override("font_color", agent_color.lightened(0.3))
	# Pulse effect
	var tw = create_tween()
	tw.tween_property(_best_line_label, "modulate:a", 1.0, 0.15).from(0.5)

func _end_round():
	_show_event_banner("ROUND %d COMPLETE" % _round_number, Color(1.0, 0.84, 0.0))
	_play_sound("event_glitch", -4.0)
	_screen_shake(3.0, 3.0)
	# Compute round awards
	var bloodiest_name := ""
	var bloodiest_val := 0
	var crowd_fav_name := ""
	var crowd_fav_val := 0
	var locked_in_name := ""
	var locked_in_val := 0.0  # topic adherence + vocab diversity
	var round_winner_name := _best_line_agent if _best_line_agent != "" else ""
	for aname in _round_stats:
		var s = _round_stats[aname]
		if s["hostile"] > bloodiest_val:
			bloodiest_val = s["hostile"]
			bloodiest_name = aname
		if s["fire"] > crowd_fav_val:
			crowd_fav_val = s["fire"]
			crowd_fav_name = aname
		# "Most Locked In" = topic references + unique vocabulary breadth
		var locked_score := float(s["topic_refs"]) * 2.0 + float(s["unique_words"].size()) * 0.1
		if locked_score > locked_in_val:
			locked_in_val = locked_score
			locked_in_name = aname
	# Feed awards to ticker and crowd
	if round_winner_name != "":
		_push_ticker("🏆 ROUND %d WINNER: %s" % [_round_number, round_winner_name])
		_spawn_crowd_reaction("MVP: " + round_winner_name, Color(1.0, 0.84, 0.0))
	if bloodiest_name != "":
		_push_ticker("🗡 BLOODIEST BLADE: %s (%d hits)" % [bloodiest_name, bloodiest_val])
	if crowd_fav_name != "" and crowd_fav_name != round_winner_name:
		_push_ticker("👑 FAN FAVORITE: %s" % crowd_fav_name)
	if locked_in_name != "" and locked_in_name != round_winner_name:
		_push_ticker("🔒 MOST LOCKED IN: %s" % locked_in_name)
	# Crowd fav boost — 2+ rounds as fan fav = confidence + aggression bump
	_apply_crowd_fav_boost(crowd_fav_name)
	if _best_line != "":
		_push_ticker("💬 BEST LINE: %s — \"%s\"" % [_best_line_agent, _best_line.substr(0, 60)])
	# Show round recap overlay
	_show_round_recap(round_winner_name, bloodiest_name, crowd_fav_name, locked_in_name)
	# Reset for next round
	_round_number += 1
	_turns_this_round = 0
	_best_line_score = 0.0
	_best_line = ""
	_best_line_agent = ""
	_round_stats.clear()
	if is_instance_valid(_best_line_label):
		_best_line_label.visible = false

func _apply_crowd_fav_boost(fav_name: String):
	if fav_name == "":
		return
	# Increment streak for the fav, reset others
	for aname in _crowd_fav_streak.keys():
		if aname != fav_name:
			_crowd_fav_streak[aname] = 0
	_crowd_fav_streak[fav_name] = _crowd_fav_streak.get(fav_name, 0) + 1
	var streak: int = _crowd_fav_streak[fav_name]
	if streak >= 2:
		# The crowd's darling gets powered up
		for agent in _agents:
			if agent.name == fav_name:
				agent.confidence = clampf(agent.confidence + 0.15, 0.0, 1.0)
				agent.aggression = clampf(agent.aggression + 0.1, 0.0, 1.0)
				agent.influence = minf(agent.influence + 0.2, 3.0)
				_push_ticker("⭐ %s is on a %d-round streak as FAN FAVORITE — powered up!" % [fav_name, streak])
				_spawn_crowd_reaction("STREAK x%d" % streak, Color(1.0, 0.84, 0.0))
				# Brighten their nameplate
				if is_instance_valid(agent.node):
					for child in agent.node.get_children():
						if child is Label:
							var glow_tw = create_tween()
							glow_tw.tween_property(child, "modulate", Color(1.3, 1.2, 0.8, 1.0), 0.3)
							glow_tw.tween_property(child, "modulate", Color.WHITE, 2.0)
							break
				break

func _show_round_recap(winner: String, hostile: String, crowd: String, coherent: String):
	# Kill previous recap if still visible
	if is_instance_valid(_round_recap_panel):
		_round_recap_panel.queue_free()
	var recap = PanelContainer.new()
	_round_recap_panel = recap
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.12, 0.92)
	style.border_color = Color(1.0, 0.84, 0.0, 0.8)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	recap.add_theme_stylebox_override("panel", style)
	var vbox = VBoxContainer.new()
	var title = Label.new()
	title.text = "━━━  ROUND %d RESULTS  ━━━" % _round_number
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var awards := []
	if winner != "":
		awards.append(["🏆 WINNER", winner, Color(1.0, 0.84, 0.0)])
	if hostile != "":
		awards.append(["🗡 BLOODIEST BLADE", hostile, Color(1.0, 0.2, 0.15)])
	if crowd != "":
		awards.append(["👑 FAN FAVORITE", crowd, Color(0.0, 1.0, 0.6)])
	if coherent != "":
		awards.append(["🔒 MOST LOCKED IN", coherent, Color(0.4, 0.7, 1.0)])
	for award in awards:
		var line = Label.new()
		line.text = "%s:  %s" % [award[0], award[1]]
		line.add_theme_font_size_override("font_size", 13)
		line.add_theme_color_override("font_color", award[2])
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(line)
	recap.add_child(vbox)
	recap.position = Vector2(ARENA_SIZE.x / 2.0 - 160, ARENA_SIZE.y / 2.0 - 80)
	recap.z_index = 95
	recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recap.modulate.a = 0.0
	$CanvasLayer.add_child(recap)
	var tw = create_tween()
	tw.tween_property(recap, "modulate:a", 1.0, 0.4)
	tw.tween_interval(4.0)
	tw.tween_property(recap, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		if is_instance_valid(recap):
			recap.queue_free()
		if _round_recap_panel == recap:
			_round_recap_panel = null
	)

func _show_event_banner(text: String, color: Color = Color.YELLOW):
	var banner = Label.new()
	banner.text = text
	banner.add_theme_font_size_override("font_size", 36)
	banner.add_theme_color_override("font_color", color)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(ARENA_SIZE.x / 2.0 - 150, ARENA_SIZE.y / 2.0 - 30)
	$CanvasLayer.add_child(banner)
	var tw = create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.3).from(0.0)
	tw.tween_interval(2.5)
	tw.tween_property(banner, "modulate:a", 0.0, 0.5)
	tw.tween_callback(banner.queue_free)


# ═════════════════════════════════════════════════════════════════════════════
# ── Memory Politics Engine ──────────────────────────────────────────────────
# ═════════════════════════════════════════════════════════════════════════════
# Orthogonal to the chat-log-style agent.memory[] buffer. Agents propose
# MEMORY_CANDIDATE blocks at the end of every turn; a trial compresses survivors
# into scars; every 10 turns each agent digests its own ledger into beliefs; a
# rumor process periodically distorts one agent's scar into another's as a
# false memory to create corrective debate. See scripts/memory_ledger.gd
# at the top of this file for the data shape.

func _set_memory_politics_active(active: bool, reason: String) -> void:
	if active == _memory_politics_active:
		return
	_memory_politics_active = active
	print("[MEMORY] politics %s (%s)" % ["ON" if active else "OFF", reason])
	if active:
		if _memory_ledger == null:
			_memory_ledger = MemoryLedger.new()
		if LEGACY_MEMORY_LEDGER: _memory_ledger.reset_for_roster(_agents)
		_memory_turn_counter = 0
		_memory_pending_candidates.clear()
		_push_ticker("📜 MEMORY POLITICS ENGAGED — every turn is a trial")
	else:
		_memory_pending_candidates.clear()

# Parse the MEMORY_CANDIDATE footer block from a sanitized reply. Returns a
# dict of trimmed fields; empty dict if no footer was found. Agents may omit
# fields — we accept partial footers and tolerate NONE as a literal.
func _parse_memory_footer(text: String) -> Dictionary:
	if text.find("MEMORY_CANDIDATE") < 0:
		return {}
	var out := {}
	var keys := ["MEMORY_CANDIDATE", "BELIEF_SHIFT", "RELATION_SHIFT", "FUTURE_TRIGGER", "FORGET"]
	for key in keys:
		var idx = text.find(key + ":")
		if idx < 0:
			idx = text.find(key + " :")
			if idx < 0:
				continue
		var after = text.substr(idx)
		var colon = after.find(":")
		if colon < 0:
			continue
		var rest = after.substr(colon + 1)
		# stop at the next known key or double newline
		var stop = rest.length()
		for other in keys:
			if other == key:
				continue
			var found = rest.find(other + ":")
			if found >= 0 and found < stop:
				stop = found
		var val = rest.substr(0, stop).strip_edges()
		# strip any trailing asterisks, bullets, or wrapper quotes
		while val.length() > 0 and val[val.length() - 1] in ["*", "-", ">"]:
			val = val.substr(0, val.length() - 1).strip_edges()
		if val.to_upper() == "NONE" or val == "":
			continue
		out[key] = val
	return out

func _strip_memory_footer(text: String) -> String:
	var keys := ["MEMORY_CANDIDATE", "BELIEF_SHIFT", "RELATION_SHIFT", "FUTURE_TRIGGER", "FORGET"]
	var earliest := text.length()
	for key in keys:
		var i = text.find(key + ":")
		if i >= 0 and i < earliest:
			earliest = i
		var j = text.find(key + " :")
		if j >= 0 and j < earliest:
			earliest = j
	if earliest == text.length():
		return text
	return text.substr(0, earliest).strip_edges()

# Parse "Trust toward X +2. Suspicion toward Y -1." into [{target, delta, axis}].
# Tolerant of casing and the LLM's tendency to drop punctuation.
func _parse_relation_shifts(text: String) -> Array:
	var shifts := []
	if text.to_upper() == "NONE" or text == "":
		return shifts
	var re := RegEx.new()
	re.compile("([A-Za-z]+)\\s+(?:toward|for|to|vs\\.?|against|on)?\\s*([A-Z][A-Za-z0-9_\\-]+)\\s*([+-]?\\s*\\d+(?:\\.\\d+)?)")
	for m in re.search_all(text):
		var word = m.get_string(1).to_lower()
		var target = m.get_string(2)
		var num_str = m.get_string(3).replace(" ", "")
		var n := float(num_str) if num_str != "" else 0.0
		# Normalize word polarity: trust → +, suspicion/distrust/fear → -
		var polarity := 1.0
		if word.find("suspic") >= 0 or word.find("distrust") >= 0 or word.find("fear") >= 0 or word.find("dislike") >= 0 or word.find("hate") >= 0:
			polarity = -1.0
		elif word.find("trust") >= 0 or word.find("respect") >= 0 or word.find("ally") >= 0:
			polarity = 1.0
		elif word.find("rivalry") >= 0 or word.find("enmity") >= 0:
			polarity = -1.0
		var delta := n * polarity * 0.25  # scale so +2 means moderate, not max
		shifts.append({"target": target, "delta": delta, "axis": word})
	return shifts

func _parse_triggers(text: String) -> Array:
	if text.to_upper() == "NONE" or text == "":
		return []
	# split on commas / semicolons / pipes; trim; dedup; cap at 4
	var parts := []
	for sep in [",", ";", "|", " / "]:
		text = text.replace(sep, ",")
	for raw in text.split(","):
		var t = str(raw).strip_edges().to_lower()
		# Strip wrapping punctuation
		while t.length() > 0 and t[0] in ["-", "*", "\"", "'"]:
			t = t.substr(1)
		while t.length() > 0 and t[t.length() - 1] in [".", ",", ";", ":", "\"", "'"]:
			t = t.substr(0, t.length() - 1)
		t = t.strip_edges()
		if t.length() >= 3 and t.length() <= 40 and not parts.has(t):
			parts.append(t)
		if parts.size() >= 4:
			break
	return parts

# Judge: score a candidate against the memory-trial criteria. Returns
# { accepted, strength, type, reasons[] }. This is deterministic and fast —
# no LM roundtrip. The point is to compress, not to philosophize.
func _judge_candidate(cand: Dictionary, owner_name: String) -> Dictionary:
	var data: Dictionary = cand.get("data", {})
	var memo: String = str(data.get("MEMORY_CANDIDATE", ""))
	var behv: String = str(data.get("BELIEF_SHIFT", ""))
	var relshift: String = str(data.get("RELATION_SHIFT", ""))
	var trig: String = str(data.get("FUTURE_TRIGGER", ""))
	if memo.length() < 12:
		return {"accepted": false, "reasons": ["too short"]}
	var score := 0.0
	var reasons := []
	var mtype := "fact"
	# + behavior change present
	if behv != "":
		score += 0.35
		reasons.append("has belief shift")
	# + relation delta present
	if relshift != "":
		score += 0.25
		reasons.append("has relation shift")
		mtype = "relation"
	# + triggers present (means it's wired for recurrence)
	if trig != "":
		score += 0.15
		reasons.append("has triggers")
	# + names another agent
	for a in _agents:
		if str(a.get("name", "")) == owner_name:
			continue
		if memo.find(str(a.get("name", ""))) >= 0:
			score += 0.15
			if mtype == "fact":
				mtype = "relation"
			reasons.append("names agent")
			break
	# + novel content vs existing scars
	var novel := true
	for s in _memory_ledger.scars_of(owner_name):
		var existing = str(s.get("content", "")).to_lower()
		var overlap := 0
		for w in memo.to_lower().split(" "):
			if w.length() > 4 and existing.find(w) >= 0:
				overlap += 1
		if overlap >= 4:
			novel = false
			break
	if novel:
		score += 0.20
		reasons.append("novel")
	else:
		score -= 0.15
		reasons.append("duplicate")
	# + type hints from content
	var lo := memo.to_lower()
	if lo.find("betray") >= 0 or lo.find("wound") >= 0 or lo.find("fear") >= 0 or lo.find("broke") >= 0:
		mtype = "trauma"
		score += 0.05
	elif lo.find("produced") >= 0 or lo.find("useful") >= 0 or lo.find("worked") >= 0 or lo.find("artifact") >= 0:
		mtype = "utility"
		score += 0.05
	elif lo.find("myth") >= 0 or lo.find("canon") >= 0 or lo.find("legend") >= 0:
		mtype = "myth"
		score += 0.05
	# Clamp
	score = clampf(score, 0.0, 1.0)
	return {
		"accepted": score >= MEM_TRIAL_THRESHOLD,
		"strength": score,
		"type": mtype,
		"reasons": reasons,
	}

# Memory Trial sweep — called every MEM_TRIAL_EVERY_N turns. Walks the pending
# candidate queue, runs the judge, writes accepted scars into the ledger, and
# pushes rejections / acceptances to the ticker so the player can SEE the
# politics happening.
func _run_memory_trial_sweep() -> void:
	if _memory_ledger == null or _memory_pending_candidates.is_empty():
		return
	_show_event_banner("MEMORY TRIAL", Color.html("#ffca28"))
	_push_ticker("⚖ MEMORY TRIAL — %d candidates" % _memory_pending_candidates.size())
	var batch: Array = _memory_pending_candidates
	_memory_pending_candidates = []
	var accepted_count := 0
	var rejected_count := 0
	for cand in batch:
		var owner = str(cand.get("agent", ""))
		if owner == "":
			continue
		var verdict = _judge_candidate(cand, owner)
		var memo = str(cand.get("data", {}).get("MEMORY_CANDIDATE", ""))
		if verdict.get("accepted", false):
			var triggers = _parse_triggers(str(cand.get("data", {}).get("FUTURE_TRIGGER", "")))
			var scar = {
				"id": _memory_ledger.next_id(),
				"type": verdict.get("type", "fact"),
				"content": memo,
				"behavior_change": str(cand.get("data", {}).get("BELIEF_SHIFT", "")),
				"strength": float(verdict.get("strength", 0.5)),
				"decay": MEM_DECAY_DEFAULT,
				"triggers": triggers,
				"created_turn": int(cand.get("turn", 0)),
				"source": "self",
				"about": [str(cand.get("about", ""))] if cand.get("about", "") != "" else [],
			}
			if LEGACY_MEMORY_LEDGER: _memory_ledger.add_scar(owner, scar, MEM_SCAR_CAP)
			# Apply relation shifts
			for rsh in _parse_relation_shifts(str(cand.get("data", {}).get("RELATION_SHIFT", ""))):
				if LEGACY_MEMORY_LEDGER: _memory_ledger.update_relation(owner, str(rsh.target), float(rsh.delta), str(rsh.axis), memo.substr(0, 60))
			# Mythic promotion — high-strength + symbolic type becomes arena canon
			if float(verdict.get("strength", 0.0)) >= 0.75 and verdict.get("type") in ["myth", "trauma"]:
				if LEGACY_MEMORY_LEDGER: _memory_ledger.add_myth("%s: %s" % [owner, memo])
				_push_ticker("🪦 MYTH: %s" % memo.substr(0, 70))
			else:
				_push_ticker("📜 SCAR accepted — %s: %s" % [owner, memo.substr(0, 60)])
			accepted_count += 1
		else:
			rejected_count += 1
	if rejected_count > 0:
		_push_ticker("✗ %d memory candidates rejected (vibes-only / duplicate)" % rejected_count)
	print("[MEMORY TRIAL] accepted=%d rejected=%d" % [accepted_count, rejected_count])

# Inject a rumor — distort one random agent's scar and plant it as a
# low-confidence false memory in another agent. Creates corrective pressure:
# future debate will either canonize the distortion or expose it.
func _inject_rumor() -> void:
	if _memory_ledger == null or _agents.size() < 2:
		return
	# Pick a source agent with at least one scar
	var source_candidates := []
	for a in _agents:
		var n = str(a.get("name", ""))
		if not _memory_ledger.scars_of(n).is_empty():
			source_candidates.append(n)
	if source_candidates.is_empty():
		return
	var source_name = source_candidates[randi() % source_candidates.size()]
	var receiver = _agents[randi() % _agents.size()]
	var receiver_name = str(receiver.get("name", ""))
	if receiver_name == source_name:
		return
	var scars = _memory_ledger.scars_of(source_name)
	var scar = scars[randi() % scars.size()]
	# Distort the content — swap a word, invert polarity, clip
	var original = str(scar.get("content", ""))
	var distorted = _distort_scar_text(original)
	var rumor = {
		"id": _memory_ledger.next_id(),
		"type": "rumor",
		"content": distorted,
		"behavior_change": "",
		"strength": 0.35,
		"decay": 0.06,
		"triggers": scar.get("triggers", []).duplicate(),
		"created_turn": _memory_turn_counter,
		"source": "rumor:" + source_name,
		"about": [source_name],
	}
	if LEGACY_MEMORY_LEDGER: _memory_ledger.add_scar(receiver_name, rumor, MEM_SCAR_CAP)
	_show_event_banner("RUMOR BLOOM", Color.html("#c471ed"))
	_push_ticker("🗣 RUMOR: %s now 'remembers' — %s" % [receiver_name, distorted.substr(0, 55)])
	print("[RUMOR] %s → %s: %s" % [source_name, receiver_name, distorted])

func _distort_scar_text(text: String) -> String:
	# Replace one of a few loaded words with a near-opposite to inject drift
	var swaps := {
		"defended": "abandoned",
		"abandoned": "defended",
		"agreed": "mocked",
		"mocked": "agreed",
		"strong": "hollow",
		"hollow": "strong",
		"mercy": "wrath",
		"wrath": "mercy",
		"truth": "story",
		"story": "truth",
		"hope": "collapse",
		"collapse": "hope",
		"won": "lost",
		"lost": "won",
	}
	var out = text
	for key in swaps.keys():
		if out.to_lower().find(key) >= 0:
			# Replace first occurrence, preserve case approximately
			var i = out.to_lower().find(key)
			out = out.substr(0, i) + swaps[key] + out.substr(i + key.length())
			break
	# Prepend provenance cue
	return "(unverified) " + out

# Self-memory digestion — every MEM_DIGEST_EVERY_N turns each agent sends a
# short LM call to compress their own scars into one operating belief. Uses
# the existing lm_studio_client, respects epoch via _alive(). Digestion is
# parallel per agent but non-blocking.
func _run_self_digestion() -> void:
	if _memory_ledger == null or _agents.is_empty() or _memory_digesting:
		return
	_memory_digesting = true
	_show_event_banner("SELF-DIGESTION", Color.html("#68eb86"))
	_push_ticker("🧠 SELF-DIGESTION — agents compress their own memory")
	var pending := _agents.size()
	for agent in _agents:
		var aname = str(agent.get("name", ""))
		var scars = _memory_ledger.scars_of(aname)
		if scars.is_empty():
			pending -= 1
			continue
		var scar_lines := []
		for s in scars:
			scar_lines.append("- [%s, strength %.2f] %s" % [s.get("type", "fact"), float(s.get("strength", 0.0)), s.get("content", "")])
		var belief_lines := []
		for b in _memory_ledger.beliefs_of(aname):
			belief_lines.append("- " + str(b))
		var system_msg = "You are %s. " % aname + MEM_DIGEST_INSTRUCTION
		var user_msg = "Your scars:\n" + "\n".join(scar_lines)
		if not belief_lines.is_empty():
			user_msg += "\n\nYour current beliefs:\n" + "\n".join(belief_lines)
		var messages = [
			{"role": "system", "content": system_msg},
			{"role": "user", "content": user_msg},
		]
		var captured_epoch: int = _turn_manager._epoch
		var captured_name: String = aname
		_lm_client.chat_completion(
			aname,
			str(agent.get("model", "")),
			messages,
			func(ok, content, http_code = 0):
				var live = _alive(captured_epoch, captured_name)
				if live == null:
					return
				if ok and content.strip_edges() != "":
					_absorb_digest_reply(captured_name, content),
			{"temperature": 0.6, "max_tokens": 180, "timeout_sec": 25.0}
		)
	# Clear the guard after a generous window regardless — this is advisory
	var guard_epoch := _turn_manager._epoch
	var tw = create_tween()
	tw.tween_interval(30.0)
	tw.tween_callback(func():
		if guard_epoch == _turn_manager._epoch:
			_memory_digesting = false
	)

func _absorb_digest_reply(agent_name: String, raw: String) -> void:
	if _memory_ledger == null:
		return
	raw = _think_regex.sub(raw, "", true) if _think_regex else raw
	raw = raw.strip_edges()
	var fields := {}
	var keys := ["OLD PATTERN", "NEW BELIEF", "MEMORY TO KEEP", "MEMORY TO LET ROT", "NEXT BEHAVIOR CHANGE"]
	for key in keys:
		var idx = raw.find(key + ":")
		if idx < 0:
			continue
		var after = raw.substr(idx)
		var colon = after.find(":")
		if colon < 0:
			continue
		var rest = after.substr(colon + 1)
		var stop = rest.length()
		for other in keys:
			if other == key:
				continue
			var f = rest.find(other + ":")
			if f >= 0 and f < stop:
				stop = f
		var val = rest.substr(0, stop).strip_edges()
		if val != "" and val.to_upper() != "NONE":
			fields[key] = val
	if fields.has("NEW BELIEF"):
		if LEGACY_MEMORY_LEDGER: _memory_ledger.add_belief(agent_name, str(fields["NEW BELIEF"]), MEM_BELIEF_CAP)
		_push_ticker("💡 %s: %s" % [agent_name, str(fields["NEW BELIEF"]).substr(0, 60)])
	if fields.has("MEMORY TO LET ROT"):
		# Drop the weakest matching scar
		var rot_phrase = str(fields["MEMORY TO LET ROT"]).to_lower()
		var scars = _memory_ledger.scars_of(agent_name)
		var best_idx := -1
		var best_overlap := 0
		for i in range(scars.size()):
			var existing = str(scars[i].get("content", "")).to_lower()
			var overlap := 0
			for w in rot_phrase.split(" "):
				if w.length() > 4 and existing.find(w) >= 0:
					overlap += 1
			if overlap > best_overlap:
				best_overlap = overlap
				best_idx = i
		if best_idx >= 0 and best_overlap >= 2:
			scars[best_idx]["strength"] = scars[best_idx].get("strength", 0.5) * 0.3
	# NEXT BEHAVIOR CHANGE pushes a stance-delta so the next turn feels it
	if fields.has("NEXT BEHAVIOR CHANGE"):
		_push_delta(agent_name, str(fields["NEXT BEHAVIOR CHANGE"]))
	print("[DIGEST] %s → %s" % [agent_name, fields])

# Convenience getter for exports and debug overlays.
func _memory_export_payload() -> Dictionary:
	if _memory_ledger == null:
		return {}
	return {
		"active": _memory_politics_active,
		"turns": _memory_turn_counter,
		"ledger": _memory_ledger.to_dict(),
	}
