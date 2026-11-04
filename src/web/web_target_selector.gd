class_name WebTargetSelector
extends Node3D
## Seleciona automaticamente o melhor ponto de ancoragem.
##
## ## O problema que isto resolve
##
## O detector anterior disparava **um único raio** do centro da tela e aceitava o
## que ele acertasse. Se o jogador não estivesse olhando exatamente para o
## prédio, não havia teia — medido: apontando para o céu, "nada na mira".
##
## ## Como funciona
##
## Em vez de um raio, o seletor **varre o espaço à frente** do jogador e gera
## vários candidatos. Cada candidato recebe uma pontuação que combina:
##
## - **Continuidade**: a ancoragem permite seguir na direção em que o jogador já
##   está indo? Este é o critério que mais pesa — é o que faz o balanço render
##   deslocamento em vez de parar o jogador.
## - **Altura útil**: o ponto está alto o bastante para gerar arco, mas não tão
##   alto que o jogador fique pendurado sem sair do lugar.
## - **Comprimento**: distância na faixa ideal. Longe demais dá um arco lento;
##   perto demais dá um balanço apertado que não conserva impulso.
## - **Ganho de altura**: o arco passa por baixo e sobe do outro lado?
## - **Visibilidade**: existe linha de visão livre? Sem isto, a teia atravessaria
##   o prédio para alcançar um ponto escondido.
## - **Direção da câmera**: influência **leve**, só para desempatar. A câmera não
##   é requisito: o disparo funciona olhando para o lado.
##
## A varredura é feita em um número fixo de raios, com as consultas de física
## reutilizadas, para o custo ser previsível no Android.

## Distância máxima de ancoragem, em metros.
@export var max_distance: float = 70.0
## Distância mínima: mais perto que isto o arco não rende. 4 m: encostado na
## parede ainda há pontos acima/ao lado dentro do alcance, então a teia pega.
@export var min_distance: float = 4.0
## Altura mínima do ponto acima do jogador.
@export var min_rise: float = 1.5
## Altura máxima do ponto acima do jogador. Acima disso o balanço vira pêndulo.
@export var max_rise: float = 45.0
## Faixa de comprimento considerada ideal, em metros.
@export var ideal_length_min: float = 14.0
@export var ideal_length_max: float = 42.0
## Margem de recuo para fora da superfície.
@export var surface_offset: float = 0.2
## Altura, acima da origem do jogador, de onde se mede a visão e a varredura.
@export var eye_height: float = 1.2

@export_group("Varredura")
## Quantos raios na horizontal e na vertical. 9x5 = 45 candidatos, custo fixo.
@export var scan_yaw_steps: int = 9
@export var scan_pitch_steps: int = 5
## Abertura da varredura, em graus, em torno da direção de movimento. 180° = volta
## completa, para a teia achar parede mesmo atrás ou ao lado do jogador.
@export var scan_yaw_spread: float = 180.0
@export var scan_pitch_low: float = -10.0
@export var scan_pitch_high: float = 60.0

@export_group("Banda de altitude")
## Altura-alvo da âncora acima da RUA (não do jogador), em metros. É o truque
## central do balanço encadeado: prender dentro de uma banda em vez de "no mais
## alto" faz o próximo arco DESCER e voltar ao cânion, em vez de escalar o
## skyline para sempre.
@export var band_base: float = 30.0
@export var band_per_speed: float = 0.25
@export var band_min: float = 30.0
@export var band_max: float = 42.0
## A partir desta folga acima da banda, o jogador é considerado "alto" e a banda
## é afrouxada (o arco pode ser mais raso).
@export var high_margin: float = 4.0

@export_group("Anti-raspão")
## Distância mínima à frente da face: se o jogador estiver a menos disto da
## parede em que a âncora está, a face é rejeitada. Evita o balanço que raspa na
## própria parede em que o jogador está colado.
@export var face_min_front: float = 1.5
## Folga mínima dos pés acima do piso no fundo do arco, em metros.
@export var arc_clearance: float = 2.6

@export_group("Pontuação")
## Peso da CONTINUIDADE: a âncora está à frente do movimento? É o critério que
## faz o balanço render deslocamento em vez de puxar o jogador para trás.
@export var continuity_weight: float = 1.5
## Âncora à frente e longe.
@export var ahead_weight: float = 1.0
## Peso da distância à banda de altitude. Alto: é o critério que organiza o
## balanço em cadeia.
@export var band_weight: float = 2.0
## Ganho de altura: o arco passa por baixo e sobe do outro lado?
@export var gain_weight: float = 0.5
## Faixa de comprimento ideal.
@export var length_weight: float = 0.5
## Peso da proximidade. Baixo: só desempata.
@export var proximity_weight: float = 0.2
## Peso da câmera. Baixo de propósito: só desempata.
@export var camera_weight: float = 0.12

var _ray_query: PhysicsRayQueryParameters3D
var _sight_query: PhysicsRayQueryParameters3D
var _world: World3D
## Candidatos reaproveitados entre disparos, para não alocar por quadro.
var _candidates: Array[Dictionary] = []


func _ready() -> void:
	_world = get_world_3d()
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	_sight_query = PhysicsRayQueryParameters3D.new()
	_sight_query.collide_with_areas = false
	_sight_query.collide_with_bodies = true


func select_target(player_position: Vector3, velocity: Vector3,
		move_direction: Vector3, camera: Camera3D, exclude: Array[RID],
		floor_height: float = 0.0) -> Dictionary:
	var forward := _resolve_forward(velocity, move_direction, camera)
	var eye := player_position + Vector3(0.0, eye_height, 0.0)
	var camera_forward := Vector3.ZERO
	if camera != null:
		camera_forward = -camera.global_transform.basis.z

	_candidates.clear()
	_scan(player_position, eye, forward, exclude, floor_height)

	if _candidates.is_empty():
		return _invalid("sem candidatos")

	# Prefere ancoras A FRENTE do movimento: prender atras puxa o jogador para
	# tras e mata o impulso. Se nao houver nenhuma a frente (encostado na parede),
	# considera todas para o disparo nunca falhar.
	var ahead_only: Array[Dictionary] = []
	for candidate: Dictionary in _candidates:
		if candidate["ahead"]:
			ahead_only.append(candidate)
	var pool: Array[Dictionary] = ahead_only if not ahead_only.is_empty() else _candidates

	# Pontua e escolhe a melhor. A pontuacao premia ficar DENTRO da banda de
	# altitude acima da rua: e o que faz o balanco encadear em vez de subir.
	var best: Dictionary = {}
	var best_score := -INF
	for candidate: Dictionary in pool:
		var score := _score(candidate, player_position, velocity, forward, camera_forward, floor_height)
		candidate["score"] = score
		if score > best_score:
			best_score = score
			best = candidate
	if best.is_empty():
		return _invalid("nenhum candidato valido")

	return {
		"valid": true,
		"position": best["position"],
		"normal": best["normal"],
		"score": best_score,
		"reason": "",
		"candidates": _candidates.duplicate(),
	}


## Direcao de referencia da varredura. Prioriza o movimento; se o jogador esta
## parado, usa a direcao em que ele olha (ou a da camera).
func _resolve_forward(velocity: Vector3, move_direction: Vector3,
		camera: Camera3D) -> Vector3:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 1.0:
		return flat.normalized()
	if move_direction.length() > 0.01:
		return Vector3(move_direction.x, 0.0, move_direction.z).normalized()
	if camera != null:
		var cam_flat := -camera.global_transform.basis.z
		cam_flat.y = 0.0
		if cam_flat.length() > 0.01:
			return cam_flat.normalized()
	return Vector3.FORWARD


## Varre um leque de direcoes e guarda os pontos validos.
func _scan(player_position: Vector3, eye: Vector3, forward: Vector3,
		exclude: Array[RID], floor_height: float) -> void:
	var base_yaw := atan2(forward.x, forward.z)
	for yaw_step in scan_yaw_steps:
		var yaw_t := 0.5 if scan_yaw_steps <= 1 else float(yaw_step) / float(scan_yaw_steps - 1)
		var yaw := base_yaw + deg_to_rad(lerpf(-scan_yaw_spread, scan_yaw_spread, yaw_t))
		for pitch_step in scan_pitch_steps:
			var pitch_t := 0.5 if scan_pitch_steps <= 1 else float(pitch_step) / float(scan_pitch_steps - 1)
			var pitch := deg_to_rad(lerpf(scan_pitch_low, scan_pitch_high, pitch_t))
			var dir := _direction_from(yaw, pitch)
			var candidate := _probe(player_position, eye, dir, exclude, forward, floor_height)
			if not candidate.is_empty():
				_candidates.append(candidate)


func _direction_from(yaw: float, pitch: float) -> Vector3:
	var horizontal := Vector3(sin(yaw), 0.0, cos(yaw))
	return (horizontal * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## Lanca um raio e valida o que ele encontrar.
func _probe(player_position: Vector3, eye: Vector3, direction: Vector3,
		exclude: Array[RID], forward: Vector3, floor_height: float) -> Dictionary:
	_ray_query.from = eye
	_ray_query.to = eye + direction * max_distance
	_ray_query.exclude = exclude
	var hit := _world.direct_space_state.intersect_ray(_ray_query)
	if hit.is_empty():
		return {}

	if not (hit.get("collider") is StaticBody3D):
		return {}

	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var point: Vector3 = hit["position"] + normal * surface_offset
	var rise := point.y - player_position.y

	if rise < min_rise or rise > max_rise:
		return {}
	var distance := player_position.distance_to(point)
	if distance < min_distance or distance > max_distance:
		return {}
	if not has_line_of_sight(eye, point, exclude):
		return {}

	# ANTI-RASPAO: o jogador precisa estar bem A FRENTE da face em que a ancora
	# esta. Colado na parede, o balanco raspava nela ("bate de cara no predio").
	# `front` e a distancia COM SINAL do jogador a face: positiva = a frente dela.
	var flat_normal := Vector3(normal.x, 0.0, normal.z)
	if flat_normal.length() > 0.01:
		flat_normal = flat_normal.normalized()
		var front := player_position - point
		front.y = 0.0
		if front.dot(flat_normal) < face_min_front:
			return {}

	# FOLGA DO ARCO: se o fundo do arco (ancora.y - comprimento) ficaria abaixo do
	# piso, NAO rejeitamos: o pivo de fisica sobe para o arco caber (ver
	# `WebSwingController.fire`). Guardamos so o sinal, para a pontuacao preferir
	# ancoras que ja cabem.
	var arc_bottom := point.y - distance
	var arc_fits := arc_bottom >= floor_height + arc_clearance

	var to_anchor := point - player_position
	var flat_to_anchor := Vector3(to_anchor.x, 0.0, to_anchor.z)
	var ahead := flat_to_anchor.length() > 0.01 and forward.dot(flat_to_anchor.normalized()) > 0.0

	return {
		"position": point,
		"normal": normal,
		"distance": distance,
		"rise": rise,
		"direction": direction,
		"ahead": ahead,
		"arc_fits": arc_fits,
		"score": 0.0,
	}


## Pontua um candidato. Valores maiores sao melhores.
func _score(candidate: Dictionary, player_position: Vector3, velocity: Vector3,
		forward: Vector3, camera_forward: Vector3, floor_height: float) -> float:
	var point: Vector3 = candidate["position"]
	var distance: float = candidate["distance"]
	var to_anchor := point - player_position
	var flat_to_anchor := Vector3(to_anchor.x, 0.0, to_anchor.z)

	# Continuidade: a ancoragem esta a frente? O vetor da ancora, projetado na
	# direcao do movimento, precisa ser positivo — senao a teia puxaria o jogador
	# para tras e mataria o impulso.
	var continuity := 0.0
	if flat_to_anchor.length() > 0.01:
		continuity = forward.dot(flat_to_anchor.normalized())

	# Ancora a frente e longe.
	var ahead := 0.0
	if flat_to_anchor.length() > 0.01:
		var along := flat_to_anchor.length()
		var lateral := absf(forward.cross(flat_to_anchor.normalized()).y)
		ahead = clampf(along / maxf(ideal_length_max, 1.0), 0.0, 1.0) * (1.0 - lateral)

	# BANDA DE ALTITUDE: a ancora ideal fica ~30 a 42 m acima da RUA (nao "o mais
	# alto possivel"). Prender dentro da banda faz o proximo arco descer de volta
	# ao canion em vez de escalar o skyline para sempre.
	var speed := Vector2(velocity.x, velocity.z).length()
	var band_center := clampf(band_base + speed * band_per_speed, band_min, band_max)
	var band_target := floor_height + band_center
	var band_error := absf(point.y - band_target)
	if player_position.y - floor_height > band_center + high_margin:
		band_error = minf(band_error, absf(point.y - player_position.y - 4.0))
	var band_score := clampf(1.0 - band_error / maxf(band_center, 1.0), 0.0, 1.0)

	# Comprimento: 1.0 dentro da faixa ideal, caindo fora dela.
	var length_score := 0.0
	if distance >= ideal_length_min and distance <= ideal_length_max:
		length_score = 1.0
	elif distance < ideal_length_min:
		length_score = distance / ideal_length_min
	else:
		length_score = clampf(1.0 - (distance - ideal_length_max) / max_distance, 0.0, 1.0)

	# Ganho de altura: o arco passa por baixo e permite subir do outro lado.
	var gain := WebPhysics.potential_height_gain(
			player_position, point, maxf(distance, WebPhysics.MIN_LENGTH))
	var gain_score := clampf(gain / 12.0, 0.0, 1.0)

	# Proximidade: so desempata.
	var proximity := 1.0 - clampf(
			(distance - min_distance) / maxf(max_distance - min_distance, 0.001), 0.0, 1.0)

	# Camera: so desempata.
	var camera_score := 0.0
	if camera_forward.length() > 0.01 and to_anchor.length() > 0.01:
		camera_score = maxf(0.0, camera_forward.dot(to_anchor.normalized()))

	# Ancoras cujo arco nao caberia acima do piso perdem um pouco, mas continuam
	# validas: o pivo de fisica sobe e resolve a folga no disparo.
	var arc_penalty := 0.0 if candidate.get("arc_fits", true) else 1.5

	return continuity * continuity_weight \
			+ ahead * ahead_weight \
			+ band_score * band_weight \
			+ length_score * length_weight \
			+ gain_score * gain_weight \
			+ proximity * proximity_weight \
			+ camera_score * camera_weight \
			- arc_penalty


func has_line_of_sight(from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	_sight_query.from = from
	_sight_query.to = to
	_sight_query.exclude = exclude
	_sight_query.hit_from_inside = true
	return _world.direct_space_state.intersect_ray(_sight_query).is_empty()


func candidate_count() -> int:
	return _candidates.size()


func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "position": Vector3.ZERO, "normal": Vector3.UP,
			"score": 0.0, "reason": reason, "candidates": []}
