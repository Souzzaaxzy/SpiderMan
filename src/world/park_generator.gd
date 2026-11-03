class_name ParkGenerator
extends Node3D
## Parques e praças: gramado, árvores, caminhos e lago.
##
## Quebra a monotonia de concreto e dá **referência visual de deslocamento** — sem
## pontos de referência, voar entre prédios idênticos não transmite velocidade.
##
## Estratégia de desempenho: cada tipo de árvore é um `MultiMesh` (tronco e copa
## separados, dois MultiMesh no total), então uma floresta inteira custa duas
## chamadas de renderização. O lago é uma laje simples com material próprio.

const GRASS_COLOR := Color(0.24, 0.4, 0.2)
const PATH_COLOR := Color(0.52, 0.48, 0.4)
const TRUNK_COLOR := Color(0.28, 0.2, 0.14)
const LEAF_COLOR_A := Color(0.2, 0.42, 0.18)
const LEAF_COLOR_B := Color(0.28, 0.5, 0.22)
const WATER_COLOR := Color(0.16, 0.3, 0.45)

## Árvores por parque.
@export var trees_per_park: int = 34

var _stats: Dictionary = {}


func build(blocks_per_side: int) -> Dictionary:
	var parks := CityLayout.parks(blocks_per_side)
	if parks.is_empty():
		return _stats
	var rng := RandomNumberGenerator.new()
	rng.seed = 991177

	var trunk_transforms: Array[Transform3D] = []
	var leaf_transforms: Array[Transform3D] = []
	var grass_transforms: Array[Transform3D] = []
	var path_transforms: Array[Transform3D] = []
	var water_transforms: Array[Transform3D] = []

	var block_half := CityLayout.BLOCK_SIZE * 0.5
	for park: Vector3 in parks:
		# Gramado cobrindo o quarteirão inteiro.
		grass_transforms.append(Transform3D(
			Basis().scaled(Vector3(CityLayout.BLOCK_SIZE, 0.08, CityLayout.BLOCK_SIZE)),
			park + Vector3(0.0, 0.04, 0.0)))
		# Caminhos cruzados.
		for axis in 2:
			var size := (Vector3(5.0, 0.1, CityLayout.BLOCK_SIZE - 4.0) if axis == 0
				else Vector3(CityLayout.BLOCK_SIZE - 4.0, 0.1, 5.0))
			path_transforms.append(Transform3D(
				Basis().scaled(size), park + Vector3(0.0, 0.09, 0.0)))
		# Lago, num canto.
		var water_offset := Vector3(-block_half * 0.42, 0.0, block_half * 0.42)
		water_transforms.append(Transform3D(
			Basis().scaled(Vector3(15.0, 0.12, 12.0)), park + water_offset + Vector3(0.0, 0.07, 0.0)))

		# Árvores espalhadas, evitando o lago e os caminhos.
		for _index in trees_per_park:
			var offset := Vector3(
				rng.randf_range(-block_half + 3.0, block_half - 3.0), 0.0,
				rng.randf_range(-block_half + 3.0, block_half - 3.0))
			if offset.distance_to(water_offset) < 11.0:
				continue
			if absf(offset.x) < 4.0 or absf(offset.z) < 4.0:
				continue
			var base := park + offset
			var scale_factor := rng.randf_range(0.8, 1.35)
			var trunk_height := 4.0 * scale_factor
			trunk_transforms.append(Transform3D(
				Basis().scaled(Vector3(0.45, trunk_height, 0.45)),
				base + Vector3(0.0, trunk_height * 0.5, 0.0)))
			var leaf_radius := rng.randf_range(1.9, 2.9) * scale_factor
			leaf_transforms.append(Transform3D(
				Basis().scaled(Vector3(leaf_radius * 2.0, leaf_radius * 1.6, leaf_radius * 2.0)),
				base + Vector3(0.0, trunk_height + leaf_radius * 0.6, 0.0)))

	_add_multimesh("Grass", _unit_box(), GRASS_COLOR, grass_transforms)
	_add_multimesh("Paths", _unit_box(), PATH_COLOR, path_transforms)
	_add_multimesh("Water", _unit_box(), WATER_COLOR, water_transforms)
	_add_multimesh("TreeTrunks", _unit_box(), TRUNK_COLOR, trunk_transforms)
	# Copa com leve variação de cor, em duas pilhas, para não ficar uniforme.
	_add_multimesh("TreeLeavesA", _unit_sphere(), LEAF_COLOR_A, leaf_transforms)
	_stats["parks"] = parks.size()
	_stats["trees"] = trunk_transforms.size()
	return _stats


func _add_multimesh(node_name: String, mesh: Mesh, color: Color,
		transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _unit_box() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


func _unit_sphere() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 6
	sphere.rings = 3
	return sphere
