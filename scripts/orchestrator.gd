extends Node2D
class_name Orchestrator

var agents = []
var agent_count = 6

var arena_size = Vector2(640, 480)
var tile_size = 32

func _ready():
	# FORCE arena visible in center of screen
	position = Vector2(200, 120)

	randomize()
	spawn_agents()

func spawn_agents():
	agents.clear()

	for i in range(agent_count):
		var pos = Vector2(
			randi_range(tile_size, arena_size.x - tile_size),
			randi_range(tile_size, arena_size.y - tile_size)
		)

		var vel = Vector2(
			randf_range(-120, 120),
			randf_range(-120, 120)
		)

		var color = Color.from_hsv(randf(), 0.9, 1.0)

		agents.append({
			"position": pos,
			"velocity": vel,
			"color": color
		})

func _process(delta):
	for agent in agents:
		var pos = agent["position"]
		var vel = agent["velocity"]

		pos += vel * delta

		if pos.x < tile_size:
			pos.x = tile_size
			vel.x *= -1

		if pos.x > arena_size.x - tile_size:
			pos.x = arena_size.x - tile_size
			vel.x *= -1

		if pos.y < tile_size:
			pos.y = tile_size
			vel.y *= -1

		if pos.y > arena_size.y - tile_size:
			pos.y = arena_size.y - tile_size
			vel.y *= -1

		agent["position"] = pos
		agent["velocity"] = vel

	queue_redraw()

func _draw():
	# arena background
	draw_rect(
		Rect2(Vector2.ZERO, arena_size),
		Color(0.08, 0.1, 0.14)
	)

	# GRID
	for x in range(0, int(arena_size.x), tile_size):
		draw_line(
			Vector2(x, 0),
			Vector2(x, arena_size.y),
			Color(0.25, 0.35, 0.5),
			1
		)

	for y in range(0, int(arena_size.y), tile_size):
		draw_line(
			Vector2(0, y),
			Vector2(arena_size.x, y),
			Color(0.25, 0.35, 0.5),
			1
		)

	# agents
	for agent in agents:
		draw_rect(
			Rect2(agent["position"] - Vector2(6,6), Vector2(12,12)),
			agent["color"]
		)
