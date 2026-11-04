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

@export_group("Pontuação")
## Peso da CONTINUIDADE: a âncora está à frente do movimento? É o critério que
## faz o balanço render deslocamento em vez de puxar o jogador para trás.
@export var continuity_weight: float = 1.5
## Âncora à frente e longe.
@export var ahead_weight: float = 1.0
## Peso da ALTURA: a teia sobe para o alto do prédio, não para a parede ao lado.
@export var high_weight: float = 4.0
## Ganho de altura: o arco passa por baixo e sobe do outro lado?
@export var gain_weight: float = 0.5
## Faixa de comprimento ideal.
@export var length_weight: float = 0.5
## Altura relativa na faixa.
@export var height_weight: float = 0.3
## Peso da proximidade. Baixo: a teia não deve grudar no ponto mais perto, e sim
## subir. A proximidade só desempata entre pontos igualmente altos.
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


## Procura o melhor ponto de ancoragem.
##
## `move_direction` é para onde o jogador está indo (ou quer ir). `camera` só
## influencia levemente. Devolve `{valid, position, score, reason, candidates}`.
##
func select_target(player_position: Vector3, velocity: Vector3,
		move_direction: Vector3, camera: Camera3D, exclude: Array[RID]) -> Dictionary:
	var forward := _resolve_forward(velocity, move_direction, camera)
	var eye := player_position + Vector3(0.0, eye_height, 0.0)
	var camera_forward := Vector3.ZERO
	if camera != null:
		camera_forward = -camera.global_transform.basis.z

	_candidates.clear()
	_scan(player_position, eye, forward, exclude)

	if _candidates.is_empty():
		return _invalid("sem candidatos")

	# Prefere ancoras A FRENTE do movimento: prender atras puxa o jogador para
	# tras e mata o impulso. Se nao houver nenhuma a frente (encostado na parede),
	# considera todas para o disparo nunca falhar.
	var ahead_only: Array[Dictionary] = []
	for candidate: Dictionary in _candidates:
		var to_anchor: Vector3 = candidate["position"] - player_position
		var flat := Vector3(to_anchor.x, 0.0, to_anchor.z)
		if flat.length() > 0.01 and forward.dot(flat.normalized()) > 0.0:
			ahead_only.append(candidate)
	var pool: Array[Dictionary] = ahead_only if not ahead_only.is_empty() else _candidates
	# Entre as ancoras a frente, escolhe a MAIS ALTA: a teia sobe para o alto do
	# predio, nao para o ponto baixo da parede ao lado.
	var best: Dictionary = {}
	var best_score := -INF
	for candidate: Dictionary in pool:
		var score := _score(candidate, player_position, velocity, forward, camera_forward)
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


## Direção de referência da varredura. Prioriza o movimento; se o jogador está
## parado, usa a direção em que ele olha (ou a da câmera).
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


## Varre um leque de direções e guarda os pontos válidos.
func _scan(player_position: Vector3, eye: Vector3, forward: Vector3,
		exclude: Array[RID]) -> void:
	var base_yaw := atan2(forward.x, forward.z)
	for yaw_step in scan_yaw_steps:
		var yaw_t := 0.5 if scan_yaw_steps <= 1 else float(yaw_step) / float(scan_yaw_steps - 1)
		var yaw := base_yaw + deg_to_rad(lerpf(-scan_yaw_spread, scan_yaw_spread, yaw_t))
		for pitch_step in scan_pitch_steps:
			var pitch_t := 0.5 if scan_pitch_steps <= 1 else float(pitch_step) / float(scan_pitch_steps - 1)
			var pitch := deg_to_rad(lerpf(scan_pitch_low, scan_pitch_high, pitch_t))
			var dir := _direction_from(yaw, pitch)
			var candidate := _probe(player_position, eye, dir, exclude)
			if not candidate.is_empty():
				_candidates.append(candidate)


func _direction_from(yaw: float, pitch: float) -> Vector3:
	var horizontal := Vector3(sin(yaw), 0.0, cos(yaw))
	return (horizontal * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## Lança um raio e valida o que ele encontrar.
func _probe(player_position: Vector3, eye: Vector3, direction: Vector3,
		exclude: Array[RID]) -> Dictionary:
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

	return {
		"position": point,
		"normal": normal,
		"distance": distance,
		"rise": rise,
		"direction": direction,
		"score": 0.0,
	}


## Pontua um candidato. Valores maiores são melhores.
func _score(candidate: Dictionary, player_position: Vector3, velocity: Vector3,
		forward: Vector3, camera_forward: Vector3) -> float:
	var point: Vector3 = candidate["position"]
	var distance: float = candidate["distance"]
	var rise: float = candidate["rise"]

	# Continuidade: a ancoragem está à frente? O vetor da âncora, projetado na
	# direção do movimento, precisa ser positivo — senão a teia puxaria o jogador
	# para trás e mataria o impulso.
	var to_anchor := point - player_position
	var flat_to_anchor := Vector3(to_anchor.x, 0.0, to_anchor.z)
	var continuity := 0.0
	if flat_to_anchor.length() > 0.01:
		continuity = forward.dot(flat_to_anchor.normalized())

	# Âncora à frente e alta. É o que evita o defeito de o jogador ser "puxado
	# para o prédio": prender na face próxima faz o arco levar contra a parede,
	# em vez de atravessar a rua. Preferimos o ponto que fica **além** do eixo do
	# jogador e bem acima, para o arco passar por baixo e seguir em frente.
	var ahead := 0.0
	if flat_to_anchor.length() > 0.01:
		var along := flat_to_anchor.length()
		var lateral := absf(forward.cross(flat_to_anchor.normalized()).y)
		# Quanto mais alinhado com a frente e quanto mais longe, melhor.
		ahead = clampf(along / maxf(ideal_length_max, 1.0), 0.0, 1.0) * (1.0 - lateral)
	# Altura: o ponto precisa estar claramente acima para o arco render.
	var high := clampf(rise / 25.0, 0.0, 1.0)

	# Proximidade: 1.0 no ponto mais perto, 0.0 no mais distante. É o critério que
	# faz a teia pegar sempre no lugar mais próximo do jogador.
	var proximity := 1.0 - clampf(
		(distance - min_distance) / maxf(max_distance - min_distance, 0.001), 0.0, 1.0)

	# Comprimento: 1.0 dentro da faixa ideal, caindo fora dela.
	var length_score := 0.0
	if distance >= ideal_length_min and distance <= ideal_length_max:
		length_score = 1.0
	elif distance < ideal_length_min:
		length_score = distance / ideal_length_min
	else:
		length_score = clampf(1.0 - (distance - ideal_length_max) / max_distance, 0.0, 1.0)

	# Altura: preferimos o ponto que gera arco util, nem rasteiro nem pendurado.
	var height_score := 1.0 - absf(rise - (ideal_length_min * 0.6)) / maxf(max_rise, 1.0)
	height_score = clampf(height_score, 0.0, 1.0)

	# Ganho de altura: o arco passa por baixo e permite subir do outro lado.
	var gain := WebPhysics.potential_height_gain(
		player_position, point, maxf(distance, WebPhysics.MIN_LENGTH))
	var gain_score := clampf(gain / 12.0, 0.0, 1.0)

	# Câmera: só desempata. Se o jogador está olhando para a âncora, um bônus leve.
	var camera_score := 0.0
	if camera_forward.length() > 0.01 and to_anchor.length() > 0.01:
		camera_score = maxf(0.0, camera_forward.dot(to_anchor.normalized()))

	return continuity * continuity_weight \
		+ ahead * ahead_weight \
		+ high * high_weight \
		+ proximity * proximity_weight \
		+ length_score * length_weight \
		+ height_score * height_weight \
		+ gain_score * gain_weight \
		+ camera_score * camera_weight


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
