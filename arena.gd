extends Node2D

var agents = []
var agent_count = 5
var arena_size = Vector2(1280, 720)

# ASSETS
var tex_mage = preload("res://sprites/agent_walk.png")
# Note: Projectile textures would be loaded here if we had direct paths,
# falling back to colored glow for stability if paths are ambiguous.

# WEBSOCKET
var socket = WebSocketPeer.new()
var server_url = "ws://127.0.0.1:8888"
var connected = false

# COMBAT
var projectiles = []

func _ready():
		spawn_agents()
		socket.connect_to_url(server_url)

func spawn_agents():
		agents.clear()
		for i in range(agent_count):
				var pos = Vector2(randf_range(200, arena_size.x - 200), randf_range(200, arena_size.y - 200))
				var affinity = "FIRE" if i % 2 == 0 else "WATER"
				var color = Color(1.0, 0.4, 0.2, 1.0) if affinity == "FIRE" else Color(0.2, 0.6, 1.0, 1.0)
				agents.append({
						"id": i, 
						"position": pos, 
						"color": color, 
						"affinity": affinity,
						"health": 100,
						"velocity": Vector2.ZERO,
						"facing": 1.0
				})

func _process(delta):
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
				if not connected:
						connected = true
						print("[✅] INTEL LINKED")
				
				var data = {"agents": []}
				for a in agents: 
						data["agents"].append({"id": a.id, "pos": [a.position.x, a.position.y], "hp": a.health, "type": a.affinity})
				socket.send_text(JSON.stringify(data))
				
				while socket.get_available_packet_count() > 0:
						var msg = socket.get_packet().get_string_from_utf8()
						var action = JSON.parse_string(msg)
						if action: process_action(action)
		
		update_physics(delta)
		queue_redraw()

func process_action(action):
		for a in agents:
				if action["type"] == "MOVE":
						a.velocity = Vector2(action["vector"][0], action["vector"][1]) * 350
						if a.velocity.x != 0: a.facing = sign(a.velocity.x)
				
				if action.get("attack", false):
						spawn_projectile(a)

func spawn_projectile(agent):
		projectiles.append({
				"position": agent.position + Vector2(16, 16),
				"velocity": (Vector2.RIGHT * agent.facing * 600),
				"color": agent.color,
				"affinity": agent.affinity,
				"lifetime": 1.5
		})

func update_physics(delta):
		for a in agents:
				a.position += a.velocity * delta
				a.position.x = clamp(a.position.x, 0, arena_size.x - 32)
				a.position.y = clamp(a.position.y, 0, arena_size.y - 32)
		
		var remaining = []
		for p in projectiles:
				p.position += p.velocity * delta
				p.lifetime -= delta
				if p.lifetime > 0:
						remaining.append(p)
						for a in agents:
								if p.position.distance_to(a.position + Vector2(16,16)) < 24 and p.affinity != a.affinity:
										a.health -= 8
										p.lifetime = 0
		projectiles = remaining

func _draw():
		# Dark Space
		draw_rect(Rect2(Vector2.ZERO, arena_size), Color(0.03, 0.03, 0.04))
		
		# Draw Mages
		for a in agents:
				# Tint the sprite based on affinity
				var draw_pos = a.position
				var scale = Vector2(a.facing, 1.0)
				# Drawing textures with transform for flipping
				draw_set_transform(draw_pos + Vector2(16, 16), 0, scale)
				draw_texture_rect(tex_mage, Rect2(Vector2(-16, -16), Vector2(32, 32)), false, a.color)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				
				# Health UI
				draw_rect(Rect2(a.position + Vector2(0, -8), Vector2(32, 4)), Color.DARK_SLATE_GRAY)
				draw_rect(Rect2(a.position + Vector2(0, -8), Vector2(32 * (a.health/100.0), 4)), a.color)

		# Draw Magic
		for p in projectiles:
				# Add a glow effect
				draw_circle(p.position, 8, Color(p.color.r, p.color.g, p.color.b, 0.3))
				draw_circle(p.position, 4, p.color)
