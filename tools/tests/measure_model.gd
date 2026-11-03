extends SceneTree
## Mede a caixa delimitadora (AABB) do modelo, para posicioná-lo e escalá-lo
## corretamente no colisor do personagem. Somente leitura.
##
## Uso: godot --headless --path . --script res://tools/tests/measure_model.gd

const MODEL_PATH := "res://assets/models/player/spiderman_newlife.glb"


func _initialize() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	var root := packed.instantiate()
	get_root().add_child(root)

	var bounds := AABB()
	var first := true
	for node in _find_all(root, "MeshInstance3D"):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var local: AABB = node.transform * mesh.get_aabb()
		if first:
			bounds = local
			first = false
		else:
			bounds = bounds.merge(local)

	print("AABB global: pos=%s size=%s" % [bounds.position, bounds.size])
	print("Altura: %.3f m  Largura: %.3f m  Profundidade: %.3f m" % [bounds.size.y, bounds.size.x, bounds.size.z])
	print("Base (min y): %.3f   Topo (max y): %.3f" % [bounds.position.y, bounds.position.y + bounds.size.y])
	print("Centro XZ: (%.3f, %.3f)" % [bounds.get_center().x, bounds.get_center().z])
	quit(0)


func _find_all(node: Node, class_filter: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(class_filter):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, class_filter))
	return found
