class_name ArenaBuilder
extends Node3D
## Constrói o cenário de teste da MISSÃO 002.
##
## O layout é dado declarativo (constante), não um sistema de gameplay: serve
## apenas para exercitar movimentação, pulo e colisões. Os visuais saem em um
## único MultiMeshInstance3D (1 draw call) e as colisões em um StaticBody3D, o
## que já segue a estratégia de desempenho pensada para Android.

const GROUND_TOP := 0.5

## Cada bloco: id, tamanho da caixa e centro já com a base apoiada no chão.
const BLOCKS: Array[Dictionary] = [
	# Prédios
	{"id": "building_a", "size": Vector3(6, 12, 6), "pos": Vector3(-12.0, 6.5, -12.0)},
	{"id": "building_b", "size": Vector3(6, 18, 6), "pos": Vector3(12.0, 9.5, -14.0)},
	{"id": "building_c", "size": Vector3(8, 9, 6), "pos": Vector3(-14.0, 5.0, 10.0)},
	{"id": "building_d", "size": Vector3(5, 22, 5), "pos": Vector3(14.0, 11.5, 12.0)},
	{"id": "building_e", "size": Vector3(7, 14, 7), "pos": Vector3(0.0, 7.5, -16.0)},
	# Escada de plataformas (degraus de 1,1 m, dentro do alcance do pulo).
	# Fica fora do eixo central para deixar a faixa de testes livre.
	{"id": "stairs_1", "size": Vector3(4, 0.6, 4), "pos": Vector3(-8.0, 0.8, 5.0)},
	{"id": "stairs_2", "size": Vector3(4, 0.6, 4), "pos": Vector3(-8.0, 1.9, 2.5)},
	{"id": "stairs_3", "size": Vector3(4, 0.6, 4), "pos": Vector3(-8.0, 3.0, 0.0)},
	# Plataformas isoladas alcançáveis com pulo
	{"id": "platform_a", "size": Vector3(4, 0.6, 4), "pos": Vector3(8.0, 1.3, 0.0)},
	{"id": "platform_b", "size": Vector3(4, 0.6, 4), "pos": Vector3(12.0, 2.4, 3.0)},
	# Obstáculos baixos para saltar ou contornar. Ficam fora dos dois eixos
	# usados pelos testes (centro e x=-12) para não bloquear as rotas.
	{"id": "wall_a", "size": Vector3(1, 1, 8), "pos": Vector3(5.0, 1.0, 0.0)},
	{"id": "wall_b", "size": Vector3(1, 1.2, 8), "pos": Vector3(-5.0, 1.1, 0.0)},
	{"id": "wall_c", "size": Vector3(8, 1, 1), "pos": Vector3(0.0, 1.0, 12.0)},
	{"id": "wall_d", "size": Vector3(4, 1.2, 1), "pos": Vector3(-16.0, 1.1, -4.0)},
]

const PROP_COLOR := Color(0.36, 0.38, 0.44)


func _ready() -> void:
	add_child(_build_visuals())
	add_child(_build_colliders())


func block_count() -> int:
	return BLOCKS.size()


## Um único MultiMesh para todos os blocos: uma draw call no lugar de catorze.
func _build_visuals() -> MultiMeshInstance3D:
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = unit_box
	multimesh.instance_count = BLOCKS.size()
	for index: int in BLOCKS.size():
		var size: Vector3 = BLOCKS[index]["size"]
		var position: Vector3 = BLOCKS[index]["pos"]
		multimesh.set_instance_transform(index, Transform3D(Basis().scaled(size), position))

	var material := StandardMaterial3D.new()
	material.albedo_color = PROP_COLOR
	material.roughness = 0.85

	var instance := MultiMeshInstance3D.new()
	instance.name = "Blocks"
	instance.multimesh = multimesh
	instance.material_override = material
	return instance


func _build_colliders() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Colliders"
	for block: Dictionary in BLOCKS:
		var shape := BoxShape3D.new()
		shape.size = block["size"]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = block["pos"]
		body.add_child(collider)
	return body
