extends Node3D
class_name BreachArenaScene

## THE VISUAL LAYER. Dresses the world; never defines it.
##
## Topology comes from arena_layout.gd. This builds boxes, lamps and labels at
## fixed positions derived from the SAME location ids, so the thing you watch
## and the thing that is simulated cannot drift apart. If a location exists in
## the layout and not here, it is still simulated -- it is just not drawn, and
## the scene says so out loud rather than silently omitting it.
##
## PS1/early-PC industrial: concrete slabs, rust, sodium lamps, catwalks, CRT
## glow. Flat-shaded boxes are the aesthetic, not a placeholder to apologise for.

const CAMERA_DIRECTOR := "DIRECTOR"
const CAMERA_AGENT := "AGENT"
const CAMERA_GOD := "GOD"

## Fixed floor positions per location id. Radial: vault at origin, chambers out.
const LAYOUT_POS := {
	"vault_hall": Vector3(0, 0, 0),
	"vault_ring": Vector3(0, 0, 8),
	"north_catwalk": Vector3(-10, 0, 14),
	"south_catwalk": Vector3(10, 0, 14),
	"machine_floor": Vector3(0, 0, 20),
	"west_pipe": Vector3(-16, 0, 20),
	"east_pipe": Vector3(16, 0, 20),
	"spawn_vanta": Vector3(-18, 0, 8),
	"spawn_kestrel": Vector3(-10, 0, 24),
	"spawn_gemmatron": Vector3(0, 0, 30),
	"spawn_ozonious": Vector3(10, 0, 24),
	"spawn_brine": Vector3(18, 0, 8),
}

const AGENT_COLOR := {
	"VANTA": Color(0.77, 0.44, 0.93),
	"KESTREL": Color(0.24, 0.69, 1.0),
	"GEMMATRON": Color(0.0, 0.82, 1.0),
	"OZONIOUS": Color(0.35, 0.84, 0.55),
	"BRINE": Color(1.0, 0.42, 0.42),
}

var _agent_nodes: Dictionary = {}
var _camera: Camera3D
var _camera_mode: String = CAMERA_DIRECTOR
var _followed: String = ""
var _undrawn: Array = []


func build(world) -> void:
	_build_environment()
	_build_locations(world)
	_build_vault()
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 34, 46)
	_camera.look_at_from_position(Vector3(0, 34, 46), Vector3(0, 0, 14), Vector3.UP)
	add_child(_camera)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.83, 0.6)      ## sodium
	sun.light_energy = 0.7
	sun.rotation_degrees = Vector3(-62, 38, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.6, 14)
	floor_mesh.material_override = _mat(Color(0.16, 0.15, 0.14))
	add_child(floor_mesh)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _build_locations(world) -> void:
	var ids: Array = world.locations.keys()
	ids.sort()
	for id in ids:
		if not LAYOUT_POS.has(id):
			## Simulated but not drawn. Recorded, not swallowed.
			_undrawn.append(id)
			continue
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6, 0.4, 6)
		slab.mesh = box
		slab.position = LAYOUT_POS[id]
		var is_spawn := str(id).begins_with("spawn_")
		slab.material_override = _mat(Color(0.28, 0.26, 0.24) if is_spawn
			else Color(0.34, 0.31, 0.28))
		add_child(slab)

		var tag := Label3D.new()
		tag.text = str(world.locations[id]["name"])
		tag.font_size = 28
		tag.position = LAYOUT_POS[id] + Vector3(0, 2.4, 0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(tag)
	if not _undrawn.is_empty():
		push_warning("BreachArenaScene: simulated but not drawn: %s"
			% ", ".join(_undrawn))


func _build_vault() -> void:
	var core := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 5, 4)
	core.mesh = box
	core.position = LAYOUT_POS["vault_hall"] + Vector3(0, 2.5, 0)
	core.material_override = _mat(Color(0.45, 0.32, 0.18))
	add_child(core)


func spawn_agents(agents: Dictionary) -> void:
	var names: Array = agents.keys()
	names.sort()
	for n in names:
		var a = agents[n]
		var node := MeshInstance3D.new()
		var caps := CapsuleMesh.new()
		caps.radius = 0.6
		caps.height = 2.2
		node.mesh = caps
		node.material_override = _mat(AGENT_COLOR.get(n, Color(0.8, 0.8, 0.8)))
		add_child(node)
		var tag := Label3D.new()
		tag.text = n
		tag.font_size = 32
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 1.8, 0)
		node.add_child(tag)
		_agent_nodes[n] = node
	sync_agents(agents)


## Positions follow world state. Agents co-located are fanned deterministically
## by sorted name so the same state always draws the same picture.
func sync_agents(agents: Dictionary) -> void:
	var by_loc := {}
	var names: Array = agents.keys()
	names.sort()
	for n in names:
		var loc = agents[n].position
		if not by_loc.has(loc):
			by_loc[loc] = []
		(by_loc[loc] as Array).append(n)
	for loc in by_loc.keys():
		var here: Array = by_loc[loc]
		var base: Vector3 = LAYOUT_POS.get(loc, Vector3(0, 0, 14))
		for i in here.size():
			var n := str(here[i])
			if not _agent_nodes.has(n):
				continue
			var angle := TAU * float(i) / float(max(1, here.size()))
			var off := Vector3(cos(angle) * 1.6, 1.1, sin(angle) * 1.6)
			(_agent_nodes[n] as Node3D).position = base + off
	_update_camera(agents)


func set_camera_mode(mode: String, followed: String = "") -> void:
	_camera_mode = mode
	_followed = followed


func _update_camera(agents: Dictionary) -> void:
	if _camera == null:
		return
	match _camera_mode:
		CAMERA_GOD:
			_camera.position = Vector3(0, 46, 52)
			_camera.look_at(Vector3(0, 0, 14), Vector3.UP)
		CAMERA_AGENT:
			if _agent_nodes.has(_followed):
				var t: Vector3 = (_agent_nodes[_followed] as Node3D).position
				_camera.position = t + Vector3(0, 7, 11)
				_camera.look_at(t, Vector3.UP)
		_:
			## Director: frame the vault, which is where state changes converge.
			_camera.position = Vector3(0, 20, 30)
			_camera.look_at(Vector3(0, 1, 6), Vector3.UP)


func undrawn_locations() -> Array:
	return _undrawn.duplicate()
