class_name CityLayout
extends RefCounted
## Planta da região urbana. Só calcula posições — não cria nenhum nó.
##
## Separar os dados da montagem permite testar a malha urbana sem instanciar
## geometria, e deixa cada gerador livre para decidir como desenhar.
##
## ## Como a cidade é organizada
##
## Uma grade de quarteirões separados por ruas. Cada quarteirão recebe um **tipo**
## que define o que ele contém:
##
## - `TOWER`: arranha-céus, no miolo da região. É onde o balanço rende mais.
## - `COMMERCIAL`: prédios médios, com lojas no térreo.
## - `RESIDENTIAL`: prédios baixos e estreitos.
## - `PARK`: área verde com árvores, lago e caminhos. Quebra a monotonia de
##   concreto e dá referência visual de deslocamento.
## - `PLAZA`: praça aberta, com poucos prédios.
## - `HOTEL`: torre hoteleira, com varandas em faixas e letreiro no topo.
##
## A distribuição é determinística (semente fixa), então o resultado é
## reproduzível nos testes.

## Largura de uma rua, de guia a guia.
const STREET_WIDTH := 16.0
## Largura da calçada em volta de cada quarteirão.
const SIDEWALK_WIDTH := 4.0
## Tamanho do quarteirão (lado), sem contar as ruas.
const BLOCK_SIZE := 52.0
## Distância entre o centro de um quarteirão e o seguinte.
const CELL_SIZE := BLOCK_SIZE + STREET_WIDTH

## Alturas por tipo de quarteirão.
const TOWER_MIN_HEIGHT := 55.0
const TOWER_MAX_HEIGHT := 130.0
const COMMERCIAL_MIN_HEIGHT := 22.0
const COMMERCIAL_MAX_HEIGHT := 50.0
const HOTEL_MIN_HEIGHT := 40.0
const HOTEL_MAX_HEIGHT := 85.0
const RESIDENTIAL_MIN_HEIGHT := 12.0
const RESIDENTIAL_MAX_HEIGHT := 28.0

## Quantos prédios cabem ao longo de uma borda do quarteirão.
const LOTS_PER_SIDE := 2
## Recuo do prédio em relação à guia da calçada.
const BUILDING_SETBACK := SIDEWALK_WIDTH + 0.8

## Altura do meio-fio. Mantida em zero porque um degrau de calçada prende o
## `CharacterBody3D`, que não sobe degraus sozinho — o piso é todo nivelado.
const CURB_HEIGHT := 0.0

## Margem de segurança em volta da região, para o jogador não cair no vazio.
const WORLD_MARGIN := 90.0
## Altura das paredes invisíveis que limitam a região.
const WORLD_WALL_HEIGHT := 500.0

enum BlockKind { TOWER, COMMERCIAL, RESIDENTIAL, PARK, PLAZA, HOTEL }


## Um lote: onde fica um prédio e o quanto ele ocupa.
class Lot extends RefCounted:
	var center: Vector3
	var size: Vector2  ## largura (x) e profundidade (z)
	var height: float
	var distance_to_center: float
	## Tipo do quarteirão de origem. O gerador de prédios usa isto para decidir
	## detalhes (varandas de hotel, por exemplo).
	var kind: int

	func _init(p_center: Vector3, p_size: Vector2, p_height: float, p_distance: float,
			p_kind: int = 0) -> void:
		center = p_center
		size = p_size
		height = p_height
		distance_to_center = p_distance
		kind = p_kind


## Um quarteirão: onde fica e o que contém.
class Block extends RefCounted:
	var center: Vector3
	var kind: int
	var row: int
	var column: int

	func _init(p_center: Vector3, p_kind: int, p_row: int, p_column: int) -> void:
		center = p_center
		kind = p_kind
		row = p_row
		column = p_column


## Descreve a grade de quarteirões, com o tipo de cada um.
##
## Os parques ficam em posições fixas (dois deles, em quadrantes opostos) e o
## miolo concentra os arranha-céus. O resto alterna entre comercial e
## residencial de forma determinística.
static func generate_blocks(blocks_per_side: int) -> Array[Block]:
	var blocks: Array[Block] = []
	var half := (blocks_per_side - 1) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242

	for row in blocks_per_side:
		for column in blocks_per_side:
			var center := Vector3(
				(column - half) * CELL_SIZE, 0.0, (row - half) * CELL_SIZE)
			blocks.append(Block.new(center, _kind_for(row, column, blocks_per_side, rng),
				row, column))
	return blocks


## Decide o tipo do quarteirão.
static func _kind_for(row: int, column: int, blocks_per_side: int,
		rng: RandomNumberGenerator) -> int:
	var half := (blocks_per_side - 1) * 0.5
	var distance := absf(row - half) + absf(column - half)
	var max_distance := maxf(1.0, half * 2.0)
	var centrality := 1.0 - distance / max_distance
	# Dois parques em cantos opostos: dão referência visual e variedade.
	var corner_a := row == 0 and column == blocks_per_side - 1
	var corner_b := row == blocks_per_side - 1 and column == 0
	if corner_a or corner_b:
		return BlockKind.PARK
	# Parque central completo (estilo cidade pequena): um quadrado 2x2 no miolo,
	# deslocado para um lado. É o pulmão da cidade e a maior referência visual.
	var mid := int(half)
	if row in [mid - 1, mid] and column in [mid - 2, mid - 1]:
		return BlockKind.PARK
	# Uma praça perto do centro.
	if centrality > 0.7 and rng.randf() < 0.25:
		return BlockKind.PLAZA
	# Hotéis: na borda do miolo, onde há movimento e vista.
	if centrality > 0.3 and centrality <= 0.55 and rng.randf() < 0.45:
		return BlockKind.HOTEL
	# Miolo: arranha-céus.
	if centrality > 0.45:
		return BlockKind.TOWER
	if centrality > 0.2:
		return BlockKind.COMMERCIAL
	return BlockKind.RESIDENTIAL


## Gera os lotes de um distrito. `seed` fixa a variação para ser reproduzível.
static func generate_lots(blocks_per_side: int, seed_value: int = 20261103) -> Array[Lot]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lots: Array[Lot] = []
	for block: Block in generate_blocks(blocks_per_side):
		lots.append_array(_lots_in_block(block, rng))
	return lots


## Divide um quarteirão em lotes. Parques e praças quase não têm prédio.
static func _lots_in_block(block: Block, rng: RandomNumberGenerator) -> Array[Lot]:
	if block.kind == BlockKind.PARK:
		return []
	var lots: Array[Lot] = []
	var usable := BLOCK_SIZE - BUILDING_SETBACK * 2.0
	var lot_length := usable / LOTS_PER_SIDE
	var offset := BUILDING_SETBACK
	var depth := usable / LOTS_PER_SIDE
	var per_side := LOTS_PER_SIDE
	if block.kind == BlockKind.PLAZA:
		per_side = 1

	for side in 4:
		for slot in per_side:
			var along := -usable * 0.5 + lot_length * (slot + 0.5)
			var position: Vector3
			var size: Vector2
			match side:
				0:
					position = block.center + Vector3(along, 0.0, -usable * 0.5 - offset + depth * 0.5)
					size = Vector2(lot_length, depth)
				1:
					position = block.center + Vector3(along, 0.0, usable * 0.5 + offset - depth * 0.5)
					size = Vector2(lot_length, depth)
				2:
					position = block.center + Vector3(-usable * 0.5 - offset + depth * 0.5, 0.0, along)
					size = Vector2(depth, lot_length)
				_:
					position = block.center + Vector3(usable * 0.5 + offset - depth * 0.5, 0.0, along)
					size = Vector2(depth, lot_length)

			var height := _height_for(block.kind, rng)
			var distance := Vector2(position.x, position.z).length()
			lots.append(Lot.new(Vector3(position.x, 0.0, position.z), size, height, distance, block.kind))
	return lots


## Altura do prédio, conforme o tipo do quarteirão.
static func _height_for(kind: int, rng: RandomNumberGenerator) -> float:
	match kind:
		BlockKind.TOWER:
			return rng.randf_range(TOWER_MIN_HEIGHT, TOWER_MAX_HEIGHT)
		BlockKind.COMMERCIAL:
			return rng.randf_range(COMMERCIAL_MIN_HEIGHT, COMMERCIAL_MAX_HEIGHT)
		_:
			return rng.randf_range(RESIDENTIAL_MIN_HEIGHT, RESIDENTIAL_MAX_HEIGHT)


## Extensão do distrito em metros (lado de um quadrado que o contém).
static func district_extent(blocks_per_side: int) -> float:
	return blocks_per_side * BLOCK_SIZE + (blocks_per_side + 1) * STREET_WIDTH


## Extensão do piso, incluindo a margem de segurança.
static func ground_extent(blocks_per_side: int) -> float:
	return district_extent(blocks_per_side) + WORLD_MARGIN * 2.0


## Posições das ruas, nos dois eixos, para desenhar as pistas.
static func street_lines(blocks_per_side: int) -> Array:
	var lines: Array = []
	var half := (blocks_per_side - 1) * 0.5
	var total := district_extent(blocks_per_side)
	for index in blocks_per_side + 1:
		var coordinate := (index - half - 0.5) * CELL_SIZE
		lines.append({"coordinate": coordinate, "length": total})
	return lines


## Posição de nascimento: no meio de uma rua na borda, virado para o centro.
static func spawn_position(blocks_per_side: int) -> Vector3:
	var half := (blocks_per_side - 1) * 0.5
	var street := (0 - half - 0.5) * CELL_SIZE
	return Vector3(street, 1.2, street)


## Centro de um parque, para o gerador colocar árvores e lago.
static func parks(blocks_per_side: int) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for block: Block in generate_blocks(blocks_per_side):
		if block.kind == BlockKind.PARK:
			centers.append(block.center)
	return centers
