class_name BuildingGenerator
extends Node3D
## Monta os prédios do distrito.
##
## Estratégia de desempenho: o corpo de todos os prédios sai em **um único
## MultiMeshInstance3D**. As janelas vêm do shader de fachada
## (`facade.gdshader`), calculadas em espaço de mundo — então um só material
## atende prédios de todos os tamanhos, sem textura e sem variação de malha.
##
## Detalhes de telhado (caixa d'água, ar-condicionado, antena, parapeito) também
## saem em MultiMesh, um por tipo. São poucas chamadas de renderização no total,
## em vez de dezenas de milhares de nós.

## Altura do parapeito no topo dos prédios, em metros.
const PARAPET_HEIGHT := 0.9
const PARAPET_THICKNESS := 0.45

## Materiais das caixas de detalhe.
const WATER_TOWER_COLOR := Color(0.42, 0.34, 0.28)
const AC_COLOR := Color(0.5, 0.52, 0.55)
const ANTENNA_COLOR := Color(0.3, 0.32, 0.36)

var _facade_material: ShaderMaterial
var _stats: Dictionary = {}


func _ready() -> void:
	var shader := load("res://src/world/facade.gdshader") as Shader
	_facade_material = ShaderMaterial.new()
	if shader != null:
		_facade_material.shader = shader


## Constrói todos os prédios a partir dos lotes. Devolve um dicionário com as
## estatísticas de geometria, para o teste e o relatório medirem o custo real.
func build(lots: Array) -> Dictionary:
	_add_bodies(lots)
	_add_roofs(lots)
	_add_details(lots)
	_stats["buildings"] = lots.size()
	return _stats


## Corpo do prédio: uma caixa por lote, todos no mesmo MultiMesh.
func _add_bodies(lots: Array) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var instance := MultiMeshInstance3D.new()
	instance.name = "BuildingBodies"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = lots.size()
	for index in lots.size():
		var lot: CityLayout.Lot = lots[index]
		var height := lot.height
		var basis := Basis().scaled(Vector3(lot.size.x, height, lot.size.y))
		var center := lot.center + Vector3(0.0, height * 0.5, 0.0)
		multimesh.set_instance_transform(index, Transform3D(basis, center))
	instance.multimesh = multimesh
	instance.material_override = _facade_material
	# As caixas não precisam de sombra própria no Mobile: a luz direcional já
	# resolve a leitura de volume, e sombra de prédio inteiro é caro.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	_stats["body_instances"] = lots.size()
	_stats["body_draw_calls"] = 1


## Telhado: laje + parapeito. A laje dá o piso onde o jogador anda; o parapeito
## impede a queda acidental e dá a silhueta de cobertura.
func _add_roofs(lots: Array) -> void:
	var slab_box := BoxMesh.new()
	slab_box.size = Vector3.ONE
	var slab_instance := MultiMeshInstance3D.new()
	slab_instance.name = "RoofSlabs"
	var slab_mesh := MultiMesh.new()
	slab_mesh.transform_format = MultiMesh.TRANSFORM_3D
	slab_mesh.mesh = slab_box
	# Uma laje por prédio, mais quatro parapeitos por prédio.
	slab_mesh.instance_count = lots.size() * 5
	var cursor := 0
	for index in lots.size():
		var lot: CityLayout.Lot = lots[index]
		var top := lot.height
		# Laje ligeiramente maior que o corpo, para dar beiral.
		var slab_size := Vector3(lot.size.x + 0.6, 0.3, lot.size.y + 0.6)
		slab_mesh.set_instance_transform(cursor,
			Transform3D(Basis().scaled(slab_size), lot.center + Vector3(0.0, top + 0.15, 0.0)))
		cursor += 1
		# Parapeitos: um por lado, formando um anel.
		var half_x := lot.size.x * 0.5
		var half_z := lot.size.y * 0.5
		var sides := [
			Vector3(0.0, top + 0.3 + PARAPET_HEIGHT * 0.5, -half_z - PARAPET_THICKNESS * 0.5),
			Vector3(0.0, top + 0.3 + PARAPET_HEIGHT * 0.5, half_z + PARAPET_THICKNESS * 0.5),
			Vector3(-half_x - PARAPET_THICKNESS * 0.5, top + 0.3 + PARAPET_HEIGHT * 0.5, 0.0),
			Vector3(half_x + PARAPET_THICKNESS * 0.5, top + 0.3 + PARAPET_HEIGHT * 0.5, 0.0),
		]
		var sizes := [
			Vector3(lot.size.x + 1.2, PARAPET_HEIGHT, PARAPET_THICKNESS),
			Vector3(lot.size.x + 1.2, PARAPET_HEIGHT, PARAPET_THICKNESS),
			Vector3(PARAPET_THICKNESS, PARAPET_HEIGHT, lot.size.y + 1.2),
			Vector3(PARAPET_THICKNESS, PARAPET_HEIGHT, lot.size.y + 1.2),
		]
		for side_index in 4:
			var offset: Vector3 = sides[side_index]
			var size: Vector3 = sizes[side_index]
			slab_mesh.set_instance_transform(cursor,
				Transform3D(Basis().scaled(size), lot.center + offset))
			cursor += 1
	slab_instance.multimesh = slab_mesh
	var slab_material := StandardMaterial3D.new()
	slab_material.albedo_color = Color(0.4, 0.4, 0.42)
	slab_material.roughness = 0.9
	slab_instance.material_override = slab_material
	add_child(slab_instance)
	_stats["roof_instances"] = slab_mesh.instance_count


## Detalhes de cobertura: caixa d'água, ar-condicionado e antena. Cada tipo vira
## um MultiMesh, então três chamadas de renderização para toda a cidade.
func _add_details(lots: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	var water_positions: Array[Transform3D] = []
	var ac_positions: Array[Transform3D] = []
	var antenna_positions: Array[Transform3D] = []

	for lot: CityLayout.Lot in lots:
		var top := lot.height + 0.3
		var room_x := maxf(lot.size.x * 0.5 - 2.0, 0.5)
		var room_z := maxf(lot.size.y * 0.5 - 2.0, 0.5)
		var spread := Vector3(rng.randf_range(-room_x, room_x), 0.0, rng.randf_range(-room_z, room_z))

		# Caixa d'água em prédios residenciais mais altos (aproximação: os mais altos).
		if lot.height > 30.0 and rng.randf() < 0.6:
			var tank_size := Vector3(3.0, 2.6, 3.0)
			water_positions.append(Transform3D(
				Basis().scaled(tank_size), lot.center + spread + Vector3(0.0, top + 1.3, 0.0)))
		# Ar-condicionado: quase todo prédio tem.
		if rng.randf() < 0.85:
			var ac_size := Vector3(1.8, 1.0, 1.4)
			ac_positions.append(Transform3D(
				Basis().scaled(ac_size),
				lot.center + spread * 0.7 + Vector3(0.0, top + 0.5, 0.0)))
		# Antena nos mais altos.
		if lot.height > 45.0:
			var mast_size := Vector3(0.18, 6.0, 0.18)
			antenna_positions.append(Transform3D(
				Basis().scaled(mast_size), lot.center + Vector3(0.0, top + 3.0, 0.0)))

	_add_multimesh("WaterTowers", _unit_box(), WATER_TOWER_COLOR, water_positions)
	_add_multimesh("AirConditioners", _unit_box(), AC_COLOR, ac_positions)
	_add_multimesh("Antennas", _unit_box(), ANTENNA_COLOR, antenna_positions)
	_stats["water_towers"] = water_positions.size()
	_stats["air_conditioners"] = ac_positions.size()
	_stats["antennas"] = antenna_positions.size()


func _add_multimesh(node_name: String, mesh: Mesh, color: Color, transforms: Array[Transform3D]) -> void:
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
	material.roughness = 0.85
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _unit_box() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box
