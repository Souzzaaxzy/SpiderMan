class_name CityGenerator
extends Node3D
## Monta o primeiro distrito de Manhattan.
##
## Coordena os geradores de ruas, prédios e mobiliário, e cria as colisões.
##
## Sobre as colisões: o detector de teias (`WebAnchorDetector`) só aceita
## superfícies `StaticBody3D`. Por isso cada prédio é um `StaticBody3D` com uma
## caixa de colisão — é isso que permite ao jogador ancorar nas fachadas e ficar
## em pé nos telhados. Detalhes puramente decorativos (postes, placas, hidrantes,
## marcas de pista) não têm colisão nenhuma, para não pesar a física.

## Quarteirões por lado. 3x3 = 9 quarteirões, 72 prédios. Escolhido para caber
## com folga na memória de um aparelho modesto antes de medir o desempenho.
@export var blocks_per_side: int = 3
## Semente da variação de alturas. Fixa para o resultado ser reproduzível.
@export var layout_seed: int = 20261103
## Liga a criação das colisões dos prédios.
@export var collision_enabled: bool = true

var _lots: Array[CityLayout.Lot] = []
var _stats: Dictionary = {}


func _ready() -> void:
	generate()


## Constrói o distrito inteiro. Pode ser chamado de novo para regerar.
func generate() -> Dictionary:
	_lots = CityLayout.generate_lots(blocks_per_side, layout_seed)

	var roads := RoadGenerator.new()
	roads.name = "Roads"
	add_child(roads)
	_stats.merge(roads.build(blocks_per_side), true)

	var buildings := BuildingGenerator.new()
	buildings.name = "Buildings"
	add_child(buildings)
	_stats.merge(buildings.build(_lots), true)

	var parks := ParkGenerator.new()
	parks.name = "Parks"
	add_child(parks)
	_stats.merge(parks.build(blocks_per_side), true)

	var furniture := StreetFurniture.new()
	furniture.name = "StreetFurniture"
	add_child(furniture)
	_stats.merge(furniture.build(blocks_per_side), true)

	if collision_enabled:
		add_child(_build_collisions())

	_stats["blocks"] = blocks_per_side * blocks_per_side
	_stats["district_extent"] = CityLayout.district_extent(blocks_per_side)
	_stats["max_building_height"] = _max_height()
	return _stats


## Colisões: uma caixa por prédio. Também são as superfícies que o sistema de
## teias enxerga, então a caixa cobre o corpo inteiro, do chão ao topo.
func _build_collisions() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "BuildingColliders"
	for lot: CityLayout.Lot in _lots:
		var shape := BoxShape3D.new()
		shape.size = Vector3(lot.size.x, lot.height, lot.size.y)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = lot.center + Vector3(0.0, lot.height * 0.5, 0.0)
		body.add_child(collider)
	return body


func _max_height() -> float:
	var highest := 0.0
	for lot: CityLayout.Lot in _lots:
		highest = maxf(highest, lot.height)
	return highest


## Estatísticas da última geração, para o teste e o relatório medirem o custo.
func statistics() -> Dictionary:
	return _stats.duplicate()


func lots() -> Array[CityLayout.Lot]:
	return _lots


## Ponto de nascimento do jogador, na calçada da borda do distrito.
func spawn_position() -> Vector3:
	return CityLayout.spawn_position(blocks_per_side)
