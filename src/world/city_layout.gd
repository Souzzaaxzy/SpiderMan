class_name CityLayout
extends RefCounted
## Planta do distrito. Só calcula posições — não cria nenhum nó.
##
## Separar os dados da montagem permite testar a malha urbana sem instanciar
## geometria, e deixa o gerador livre para decidir como desenhar cada peça.
##
## A cidade é uma grade: quarteirões separados por ruas, com calçadas nas bordas.
## A altura dos prédios cresce em direção ao centro, como em Manhattan.

## Largura de uma rua, de guia a guia.
const STREET_WIDTH := 14.0
## Largura da calçada em volta de cada quarteirão.
const SIDEWALK_WIDTH := 3.0
## Tamanho do quarteirão (lado), sem contar as ruas.
const BLOCK_SIZE := 42.0
## Altura do meio-fio: a calçada fica acima da rua.
const CURB_HEIGHT := 0.15

## Distância entre o centro de um quarteirão e o seguinte.
const CELL_SIZE := BLOCK_SIZE + STREET_WIDTH

## Altura mínima e máxima dos prédios, em metros.
const MIN_BUILDING_HEIGHT := 12.0
const MAX_BUILDING_HEIGHT := 78.0
## Quantos prédios cabem ao longo de uma borda do quarteirão.
const LOTS_PER_SIDE := 2
## Recuo do prédio em relação à guia da calçada.
const BUILDING_SETBACK := SIDEWALK_WIDTH + 0.6


## Um lote: onde fica um prédio e o quanto ele ocupa.
class Lot extends RefCounted:
	var center: Vector3
	var size: Vector2  ## largura (x) e profundidade (z)
	var height: float
	var distance_to_center: float

	func _init(p_center: Vector3, p_size: Vector2, p_height: float, p_distance: float) -> void:
		center = p_center
		size = p_size
		height = p_height
		distance_to_center = p_distance


## Gera os lotes de um distrito de `blocks_per_side` quarteirões por lado.
##
## O distrito é centrado na origem, então quarteirões de índice iguais em x e z
## ficam à mesma distância do centro. `seed` fixa a variação de alturas para o
## resultado ser reproduzível nos testes.
static func generate_lots(blocks_per_side: int, seed_value: int = 20261103) -> Array[Lot]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var lots: Array[Lot] = []
	var half := (blocks_per_side - 1) * 0.5
	var max_index_distance := maxf(1.0, absf(half) + absf(half))

	for row in blocks_per_side:
		for column in blocks_per_side:
			var block_center := Vector3(
				(column - half) * CELL_SIZE, 0.0, (row - half) * CELL_SIZE)
			var index_distance := absf(column - half) + absf(row - half)
			var centrality := 1.0 - clampf(index_distance / max_index_distance, 0.0, 1.0)
			lots.append_array(_lots_in_block(block_center, centrality, rng))
	return lots


## Divide um quarteirão em lotes ao longo das quatro faces voltadas para a rua.
static func _lots_in_block(block_center: Vector3, centrality: float,
		rng: RandomNumberGenerator) -> Array[Lot]:
	var lots: Array[Lot] = []
	var usable := BLOCK_SIZE - BUILDING_SETBACK * 2.0
	var lot_length := usable / LOTS_PER_SIDE
	var offset := BUILDING_SETBACK
	# Profundidade do lote: o prédio ocupa a borda e deixa o miolo do quarteirão
	# livre, o que mantém a contagem de geometria baixa.
	var depth := usable / LOTS_PER_SIDE

	for side in 4:
		for slot in LOTS_PER_SIDE:
			var along := -usable * 0.5 + lot_length * (slot + 0.5)
			var position: Vector3
			var size: Vector2
			match side:
				0:  # face norte (-Z)
					position = block_center + Vector3(along, 0.0, -usable * 0.5 - offset + depth * 0.5)
					size = Vector2(lot_length, depth)
				1:  # face sul (+Z)
					position = block_center + Vector3(along, 0.0, usable * 0.5 + offset - depth * 0.5)
					size = Vector2(lot_length, depth)
				2:  # face oeste (-X)
					position = block_center + Vector3(-usable * 0.5 - offset + depth * 0.5, 0.0, along)
					size = Vector2(depth, lot_length)
				_:  # face leste (+X)
					position = block_center + Vector3(usable * 0.5 + offset - depth * 0.5, 0.0, along)
					size = Vector2(depth, lot_length)

			var height := _height_for(centrality, rng)
			var distance := Vector2(position.x, position.z).length()
			lots.append(Lot.new(Vector3(position.x, 0.0, position.z), size, height, distance))
	return lots


## Altura do prédio: quanto mais central, mais alto, com variação para a silhueta
## não ficar monótona.
static func _height_for(centrality: float, rng: RandomNumberGenerator) -> float:
	var base := lerpf(MIN_BUILDING_HEIGHT, MAX_BUILDING_HEIGHT, pow(centrality, 1.6))
	var variation := rng.randf_range(0.78, 1.22)
	return clampf(base * variation, MIN_BUILDING_HEIGHT, MAX_BUILDING_HEIGHT)


## Extensão total do distrito em metros (lado de um quadrado que o contém).
static func district_extent(blocks_per_side: int) -> float:
	return blocks_per_side * BLOCK_SIZE + (blocks_per_side + 1) * STREET_WIDTH


## Posições das ruas, nos dois eixos, para desenhar as pistas.
## Devolve pares (coordenada do centro da rua, comprimento).
static func street_lines(blocks_per_side: int) -> Array:
	var lines: Array = []
	var half := (blocks_per_side - 1) * 0.5
	var total := district_extent(blocks_per_side)
	for index in blocks_per_side + 1:
		var coordinate := (index - half - 0.5) * CELL_SIZE
		lines.append({"coordinate": coordinate, "length": total})
	return lines


## Distrito: extensão total e margem de segurança.
## A margem evita que o jogador caia no vazio ao explorar a borda da região.
const WORLD_MARGIN := 60.0
## Altura das paredes invisíveis que limitam a região.
const WORLD_WALL_HEIGHT := 400.0

## Extensão do piso, incluindo a margem além dos quarteirões.
static func ground_extent(blocks_per_side: int) -> float:
	return district_extent(blocks_per_side) + WORLD_MARGIN * 2.0


## Posição de nascimento do jogador: no meio de uma rua na borda do distrito,
## virado para o centro. Nascer na calçada daria apenas alguns metros de espaço
## antes de esbarrar em um prédio.
static func spawn_position(blocks_per_side: int) -> Vector3:
	var half := (blocks_per_side - 1) * 0.5
	# Coordenada da rua mais a oeste e mais ao norte (entre quarteirões).
	var street := (0 - half - 0.5) * CELL_SIZE
	return Vector3(street, 1.2, street)
