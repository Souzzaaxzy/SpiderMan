class_name RoadGenerator
extends Node3D
## Monta ruas, calçadas, guias, faixas de pedestres e marcas de pista.
##
## Mesma estratégia dos prédios: tudo em poucos MultiMesh, com materiais
## reutilizados. As ruas são poucas caixas grandes; as marcas (faixas, travessias)
## são muitos retângulos pequenos e por isso vão em MultiMesh separado.

const ASPHALT_COLOR := Color(0.19, 0.19, 0.21)
const SIDEWALK_COLOR := Color(0.52, 0.51, 0.49)
const CURB_COLOR := Color(0.62, 0.61, 0.58)
const MARKING_COLOR := Color(0.85, 0.83, 0.55)

## Espessura das marcas de pista, em metros.
const LANE_MARK_WIDTH := 0.25
const LANE_MARK_LENGTH := 3.0
const LANE_MARK_GAP := 5.0
## Largura da faixa de pedestres.
const CROSSWALK_WIDTH := 3.2
const CROSSWALK_STRIPE := 0.7
const CROSSWALK_GAP := 0.7

var _stats: Dictionary = {}


func build(blocks_per_side: int) -> Dictionary:
	_add_ground(blocks_per_side)
	_add_world_bounds(blocks_per_side)
	_add_sidewalks(blocks_per_side)
	_add_street_markings(blocks_per_side)
	_stats["crosswalks"] = _crosswalk_count(blocks_per_side)
	return _stats


## Limites invisíveis na borda da região.
##
## Sem isto, o jogador que corre para fora do distrito cai no vazio — as ruas
## acabam e não há nada embaixo. As paredes são altas e finas, e ficam fora da
## área construída, então não interferem na exploração nem no balanço.
func _add_world_bounds(blocks_per_side: int) -> void:
	var extent := CityLayout.ground_extent(blocks_per_side)
	var half := extent * 0.5
	var thickness := 4.0
	var height := CityLayout.WORLD_WALL_HEIGHT

	var body := StaticBody3D.new()
	body.name = "WorldBounds"
	var walls := [
		Vector3(0.0, height * 0.5, -half - thickness * 0.5),
		Vector3(0.0, height * 0.5, half + thickness * 0.5),
		Vector3(-half - thickness * 0.5, height * 0.5, 0.0),
		Vector3(half + thickness * 0.5, height * 0.5, 0.0),
	]
	var sizes := [
		Vector3(extent + thickness * 2.0, height, thickness),
		Vector3(extent + thickness * 2.0, height, thickness),
		Vector3(thickness, height, extent + thickness * 2.0),
		Vector3(thickness, height, extent + thickness * 2.0),
	]
	for index in 4:
		var shape := BoxShape3D.new()
		shape.size = sizes[index]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = walls[index]
		body.add_child(collider)
	add_child(body)
	_stats["world_walls"] = 4


## Piso único cobrindo o distrito mais a margem.
##
## A caixa é **grossa de propósito** (20 m). Um piso fino de 1 m sofre
## *tunneling*: a 7 m/s o `move_and_slide` atravessa a face antes de detectar a
## colisão, e o jogador cai pelo chão. Com 20 m de espessura, mesmo um quadro
## longo não atravessa.
const GROUND_THICKNESS := 20.0

func _add_ground(blocks_per_side: int) -> void:
	var extent := CityLayout.ground_extent(blocks_per_side)
	var ground := StaticBody3D.new()
	ground.name = "RoadSurface"
	var center := Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(extent, GROUND_THICKNESS, extent)
	var material := StandardMaterial3D.new()
	material.albedo_color = ASPHALT_COLOR
	material.roughness = 0.95
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	ground.add_child(instance)

	var shape := BoxShape3D.new()
	shape.size = Vector3(extent, GROUND_THICKNESS, extent)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	ground.add_child(collider)

	add_child(ground)
	_stats["ground_extent"] = extent


## Calçadas: faixa visual em volta de cada quarteirão.
##
## São **finas e sem colisão**. A decisão é deliberada: um meio-fio com colisão
## vira um degrau de 15 cm, e o `CharacterBody3D` não sobe degraus sozinho — o
## jogador ficaria preso na guia ao atravessar a rua. Com o piso todo nivelado em
## y=0, caminhar, correr e pousar de balanço funcionam sem código de escalada.
## A diferença entre rua e calçada fica pelo material, que é o que se enxerga.
func _add_sidewalks(blocks_per_side: int) -> void:
	var half := (blocks_per_side - 1) * 0.5
	var block_half := CityLayout.BLOCK_SIZE * 0.5
	var width := CityLayout.SIDEWALK_WIDTH
	# Espessura só visual, apoiada no piso.
	var height := 0.06

	var transforms: Array[Transform3D] = []
	for row in blocks_per_side:
		for column in blocks_per_side:
			var center := Vector3(
				(column - half) * CityLayout.CELL_SIZE, 0.0,
				(row - half) * CityLayout.CELL_SIZE)
			# Duas faixas ao longo de X (norte e sul).
			for side_z: float in [-(block_half + width * 0.5), block_half + width * 0.5]:
				transforms.append(Transform3D(
					Basis().scaled(Vector3(CityLayout.BLOCK_SIZE + width * 2.0, height, width)),
					center + Vector3(0.0, height * 0.5, side_z)))
			# Duas faixas ao longo de Z (oeste e leste).
			for side_x: float in [-(block_half + width * 0.5), block_half + width * 0.5]:
				transforms.append(Transform3D(
					Basis().scaled(Vector3(width, height, CityLayout.BLOCK_SIZE)),
					center + Vector3(side_x, height * 0.5, 0.0)))

	var instance := _multimesh_instance("SidewalkMeshes", _unit_box(), SIDEWALK_COLOR, transforms)
	add_child(instance)

	_stats["sidewalk_tiles"] = transforms.size()
	_stats["sidewalk_colliders"] = 0


## Marcas de pista (linhas centrais) e faixas de pedestres nos cruzamentos.
func _add_street_markings(blocks_per_side: int) -> void:
	var extent := CityLayout.district_extent(blocks_per_side)
	var lines := CityLayout.street_lines(blocks_per_side)
	var transforms: Array[Transform3D] = []
	var marking_height := 0.012

	# Linhas centrais tracejadas ao longo de cada rua, nos dois eixos.
	for line: Dictionary in lines:
		var coordinate: float = line["coordinate"]
		var length: float = line["length"]
		var step := LANE_MARK_LENGTH + LANE_MARK_GAP
		var count := int(length / step)
		var start := -length * 0.5 + step * 0.5
		for index in count:
			var along := start + index * step
			# Rua no eixo Z (varia em Z), linha central correndo em Z.
			transforms.append(Transform3D(
				Basis().scaled(Vector3(LANE_MARK_WIDTH, 0.02, LANE_MARK_LENGTH)),
				Vector3(coordinate, marking_height, along)))
			# Rua no eixo X.
			transforms.append(Transform3D(
				Basis().scaled(Vector3(LANE_MARK_LENGTH, 0.02, LANE_MARK_WIDTH)),
				Vector3(along, marking_height, coordinate)))

	# Faixas de pedestres: barras paralelas atravessando a rua em cada cruzamento.
	var block_half := CityLayout.BLOCK_SIZE * 0.5
	var stripe_step := CROSSWALK_STRIPE + CROSSWALK_GAP
	var stripe_count := int((CityLayout.STREET_WIDTH - 2.0) / stripe_step)
	for line: Dictionary in lines:
		var coordinate: float = line["coordinate"]
		for other: Dictionary in lines:
			var cross: float = other["coordinate"]
			# Só onde as duas ruas se cruzam.
			for stripe in stripe_count:
				var offset := -(CityLayout.STREET_WIDTH - 2.0) * 0.5 + stripe_step * (stripe + 0.5)
				# Travessia no sentido Z.
				transforms.append(Transform3D(
					Basis().scaled(Vector3(CROSSWALK_STRIPE, 0.02, CROSSWALK_WIDTH)),
					Vector3(coordinate + offset, marking_height, cross
						+ (block_half + CityLayout.SIDEWALK_WIDTH * 0.5))))
				# Travessia no sentido X.
				transforms.append(Transform3D(
					Basis().scaled(Vector3(CROSSWALK_WIDTH, 0.02, CROSSWALK_STRIPE)),
					Vector3(cross + (block_half + CityLayout.SIDEWALK_WIDTH * 0.5),
						marking_height, coordinate + offset)))

	var instance := _multimesh_instance("StreetMarkings", _unit_box(), MARKING_COLOR, transforms)
	# Sem colisão: são pinturas no chão, não devem barrar o jogador.
	add_child(instance)
	_stats["marking_instances"] = transforms.size()
	_stats["district_extent"] = extent


func _crosswalk_count(blocks_per_side: int) -> int:
	var crossings := (blocks_per_side + 1) * (blocks_per_side + 1)
	var stripe_step := CROSSWALK_STRIPE + CROSSWALK_GAP
	var stripes := int((CityLayout.STREET_WIDTH - 2.0) / stripe_step)
	return crossings * stripes * 2


func _multimesh_instance(node_name: String, mesh: Mesh, color: Color,
		transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = maxi(transforms.size(), 1)
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
	return instance


func _unit_box() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box
