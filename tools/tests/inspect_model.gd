extends SceneTree
## Inspeção do modelo do personagem dentro da própria Godot.
##
## Lê a cena importada e relata malhas, triângulos, esqueleto, hierarquia de
## ossos, materiais e animações. Somente leitura: não altera nada.
##
## Uso: godot --headless --path . --script res://tools/tests/inspect_model.gd

const MODEL_PATH := "res://assets/models/player/spiderman_newlife.glb"


func _initialize() -> void:
	print("=== Inspecao do modelo: %s ===" % MODEL_PATH)
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		print("ERRO: nao foi possivel carregar o modelo.")
		quit(1)
		return

	var root := packed.instantiate()
	get_root().add_child(root)
	_report_node(root, 0)
	print("")
	_report_summary(root)
	quit(0)


func _report_node(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	match true:
		_ when node is MeshInstance3D:
			var mesh: Mesh = (node as MeshInstance3D).mesh
			var tris: int = 0
			var verts: int = 0
			if mesh != null:
				for surface in mesh.get_surface_count():
					tris += mesh.surface_get_array_index_len(surface) / 3 if mesh.surface_get_array_index_len(surface) > 0 else mesh.surface_get_array_len(surface) / 3
					verts += mesh.surface_get_array_len(surface)
			print("%s[Mesh] %s  surfaces=%d  verts=%d  tris=%d" % [
				indent, node.name, mesh.get_surface_count() if mesh != null else 0, verts, int(tris)])
		_ when node is Skeleton3D:
			var skeleton := node as Skeleton3D
			print("%s[Skeleton] %s  bones=%d" % [indent, node.name, skeleton.get_bone_count()])
		_ when node is AnimationPlayer:
			var player := node as AnimationPlayer
			print("%s[AnimationPlayer] %s  animacoes=%d" % [indent, node.name, player.get_animation_list().size()])
		_ when node is BoneAttachment3D:
			print("%s[BoneAttachment] %s" % [indent, node.name])
		_:
			if depth <= 2:
				print("%s[%s] %s" % [indent, node.get_class(), node.name])

	for child in node.get_children():
		_report_node(child, depth + 1)


func _report_summary(root: Node) -> void:
	var meshes := _find_all(root, "MeshInstance3D")
	var skeletons := _find_all(root, "Skeleton3D")
	var players := _find_all(root, "AnimationPlayer")

	var total_tris := 0
	var total_verts := 0
	var materials: Array[String] = []
	for node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var index_len: int = mesh.surface_get_array_index_len(surface)
			total_tris += (index_len if index_len > 0 else mesh.surface_get_array_len(surface)) / 3
			total_verts += mesh.surface_get_array_len(surface)
			var material := mesh.surface_get_material(surface)
			var material_name := material.resource_name if material != null else "(sem material)"
			if not materials.has(material_name):
				materials.append(material_name)

	print("--- Resumo ---")
	print("Malhas: %d" % meshes.size())
	print("Vertices: %d" % total_verts)
	print("Triangulos: %d" % int(total_tris))
	print("Materiais: %d -> %s" % [materials.size(), ", ".join(materials)])
	print("Esqueletos: %d" % skeletons.size())

	for node in skeletons:
		var skeleton := node as Skeleton3D
		print("Ossos: %d" % skeleton.get_bone_count())
		print("Hierarquia de ossos:")
		for index in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(index)
			var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else "(raiz)"
			print("  %s  <- pai: %s" % [skeleton.get_bone_name(index), parent_name])

	var animation_names: Array[String] = []
	for node in players:
		var player := node as AnimationPlayer
		for animation_name in player.get_animation_list():
			animation_names.append(String(animation_name))
	print("Animacoes: %d %s" % [animation_names.size(), str(animation_names)])


func _find_all(node: Node, class_name_filter: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(class_name_filter):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, class_name_filter))
	return found
