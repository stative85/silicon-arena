extends Node

## Ticks cinematic_live_server.gd. A SceneTree script gets no _process, so the
## clock has to live on a real Node in the tree.

var owner_tree


func _process(delta: float) -> void:
	if owner_tree != null:
		owner_tree.tick(delta)
