class_name WebSwingController
extends Node3D
## Sistema de teias: balanço e Web Zip.
##
## ## Controle
##
## Um botão. `press()` dispara e mantém preso; `release()` solta.
##
## ## Como o jogador é movido
##
## A corda **não reposiciona** o jogador. Ela devolve a velocidade corrigida, e
## quem move o corpo é o `move_and_slide` do controlador, como em qualquer outro
## movimento. Isso acabou com o teletransporte: antes, o ajuste de posição
## arrancava o personagem 3,36 m num único quadro.
##
## A posição só é corrigida quando o erro já passou da tolerância, e mesmo aí por
## um deslocamento limitado (`MAX_POSITION_CORRECTION`), aplicado **depois** do
## `move_and_slide`, para respeitar as colisões.
##
## ## Arquitetura
##
## As ancoragens ficam em arranjo e a física é aplicada em laço, então habilitar
## uma segunda teia é uma questão de permitir o segundo disparo — não de
## reescrever a física.

signal web_fired(anchor: Vector3, score: float)
signal web_released(speed: float)
signal zip_started(target: Vector3)
signal zip_finished()

enum State { IDLE, SWINGING, ZIPPING }

## Folga da corda: dentro do raio + folga, a corda está frouxa e só a gravidade
## age. É o que dá a queda livre no início do balanço.
const ROPE_SLACK := 1.0
## Altura mínima do ponto mais baixo do arco, acima do piso.
const MIN_ARC_HEIGHT := 1.6
## Altura minima do arco acima do piso DURANTE o balanco. Maior que a do
## disparo: o arco inteiro precisa caber acima do chao, senao o jogador e
## arrastado para o asfalto (era o defeito de "bater de cara no predio").
const SWING_CLEARANCE := 3.4
## Quanto a corda encurta por segundo para manter o arco acima do piso.
const CLEARANCE_PULL_RATE := 8.0
## Limites do comprimento ajustável.
const MIN_ROPE_LENGTH := 3.0
const MAX_ROPE_LENGTH := 60.0
## Quanto o comprimento muda por segundo ao segurar o ajuste.
const REEL_RATE := 7.0

@export_group("Web Zip")
## Velocidade máxima do impulso, em m/s.
@export var zip_max_speed: float = 26.0
## Aceleração do impulso, em m/s². É o que dá a sensação de "puxada".
@export var zip_acceleration: float = 55.0
## Distância em que o impulso termina sozinho.
@export var zip_arrival_distance: float = 3.5
## Fração da velocidade lateral preservada durante a puxada.
@export var zip_lateral_keep: float = 0.35

@export_group("Referências")
@export var controller_path: NodePath = ^".."
@export var camera_path: NodePath = ^"../CameraRig/SpringArm3D/Camera3D"
@export var camera_rig_path: NodePath = ^"../CameraRig"
@export var selector_path: NodePath = ^"WebTargetSelector"
@export var visual_path: NodePath = ^"WebVisual"
@export var hand_bone_name: StringName = &"RightHand"
@export var shoulder_height: float = 1.5

@export_group("Balanço")
## Ganho extra de impulso ao soltar. 1.0 = sem ganho.
@export var release_boost: float = 1.0

@export_group("Impulso de soltura (estilo Spider-Man 2)")
## O impulso clássico do Spider-Man 2: soltar a teia no **ponto mais baixo do
## arco** converte a queda em velocidade horizontal. O jogador sai voando para
## frente em vez de ser puxado para o prédio.
@export var swing_kick_enabled: bool = true
## Velocidade mínima para o impulso valer.
@export var swing_kick_min_speed: float = 6.0
## Quanto da velocidade é somado como impulso horizontal.
@export var swing_kick_gain: float = 0.55
## Teto do impulso horizontal, em m/s.
@export var swing_kick_max: float = 14.0
## Impulso **vertical base** ao soltar, em m/s. Dá o "salto" de soltura: mesmo
## saindo do ponto baixo do arco (onde a queda é ~0), o jogador sobe. Pedido do
## responsável: "vá mais para cima também".
@export var swing_kick_up_base: float = 4.5
## Quanto da queda vira impulso vertical extra, além da base.
@export var swing_kick_up_gain: float = 0.30
## Teto do impulso vertical, em m/s.
@export var swing_kick_up_max: float = 8.0
## Bônus de "balanço completo": quanto do arco foi percorrido desde o disparo.
## Quanto mais completo, mais empurrão para frente e para cima ao soltar — é o
## que faz um balanço bem executado ganhar altura em vez de só deslizar.
@export var full_swing_forward: float = 5.0
@export var full_swing_up: float = 5.0

@export_group("Afastamento da parede")
## A partir de que distância da parede o empurrão começa, em metros.
@export var wall_push_distance: float = 6.5
## Força do empurrão para fora da parede, em m/s². É o que mantém o personagem
## balançando **longe** da fachada em vez de raspando nela.
@export var wall_push_strength: float = 20.0
## Alcance do raio que procura a parede à frente, em metros.
@export var wall_probe_distance: float = 9.0

var _controller: CharacterBody3D
var _camera: Camera3D
var _camera_rig: Node3D
var _selector: WebTargetSelector
var _visual: WebVisual
var _skeleton: Skeleton3D

var _state: State = State.IDLE
var _anchors: Array[Vector3] = []
## Pivô de FÍSICA: o ponto em volta do qual a corda realmente gira. Pode ser
## mais alto que a âncora visual, quando o arco não caberia acima do piso.
var _pivot: Vector3 = Vector3.ZERO
var _rope_lengths: Array[float] = []
var _anchor_count: int = 0
var _reel_input: float = 0.0
var _last_release_speed: float = 0.0
var _floor_height: float = 0.0
var _floor_query: PhysicsRayQueryParameters3D
var _last_score: float = 0.0
## Tempo desde prender a teia, e ângulo do arco no momento do disparo.
var _swing_time: float = 0.0
var _swing_angle_start: float = 0.0

## Alvo do Web Zip.
var _zip_target: Vector3 = Vector3.ZERO
var _zip_requested: bool = false
## Movimento desejado pelo jogador, para a seleção de alvo.
var _desired_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as CharacterBody3D
	_camera = get_node_or_null(camera_path) as Camera3D
	_camera_rig = get_node_or_null(camera_rig_path)
	_selector = get_node_or_null(selector_path) as WebTargetSelector
	_visual = get_node_or_null(visual_path) as WebVisual
	_skeleton = _find_skeleton(_controller)

	if _controller == null:
		push_warning("WebSwingController: controlador nao encontrado em '%s'." % controller_path)
		return

	_floor_query = PhysicsRayQueryParameters3D.new()
	_floor_query.collide_with_areas = false
	_floor_query.collide_with_bodies = true

	# O controlador chama estes passos dentro do próprio _physics_process: a corda
	# corrige a velocidade antes do move_and_slide, e a posição depois.
	_controller.web_velocity_stepper = _step_swing_velocity
	_controller.web_position_stepper = _step_swing_position
	_controller.web_zip_stepper = _step_zip


func _find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	# Teclado para testes no PC. No Android a HUD chama os mesmos métodos.
	if event is InputEventKey and not event.echo:
		match event.physical_keycode:
			KEY_E:
				if event.pressed:
					press()
				else:
					release()
			KEY_R:
				set_reel_input(1.0 if event.pressed else 0.0)
			KEY_F:
				set_reel_input(-1.0 if event.pressed else 0.0)
			KEY_C:
				if event.pressed:
					zip()


func _process(_delta: float) -> void:
	if _visual == null:
		return
	if _state == State.SWINGING:
		_visual.set_points(hand_position(), _anchors[0])
		if _camera_rig != null:
			_camera_rig.align_to_swing(_controller.velocity, _delta_safe())
	elif _state == State.ZIPPING:
		_visual.set_points(hand_position(), _zip_target)
		if _camera_rig != null:
			_camera_rig.align_to_motion(_controller.velocity, _delta_safe())
	else:
		# Fora da teia, o FOV e a distância ainda reagem à velocidade (corrida),
		# mas sem alinhamento automático: o jogador mantém o controle da câmera.
		if _camera_rig != null:
			_camera_rig.align_to_motion(_controller.velocity, _delta_safe())


## --- API pública ---

## Segurar o botão: dispara se não houver teia, ou recolhe se já houver.
func press() -> void:
	if _state == State.SWINGING:
		set_reel_input(1.0)
		return
	fire()


## Solta o botão: solta a teia.
func release() -> void:
	set_reel_input(0.0)
	if _state != State.SWINGING:
		return
	_state = State.IDLE
	_anchor_count = 0
	_last_release_speed = _controller.velocity.length()

	_controller.swing_active = false
	if release_boost != 1.0:
		_controller.velocity *= release_boost
	# O impulso do Spider-Man 2: soltar no ponto baixo do arco converte a queda
	# em velocidade horizontal. Sem isto o jogador é puxado na direção da âncora
	# — que fica na face do prédio — em vez de seguir em frente.
	_apply_swing_kick()
	if _visual != null:
		_visual.hide_strand()
	if _camera_rig != null:
		_camera_rig.reset_spring_length()

	web_released.emit(_last_release_speed)


## Converte a velocidade de queda em impulso horizontal, na direção do movimento.
##
## É o mecanismo central do balanço do Spider-Man 2: o jogador ganha velocidade
## ao atravessar o ponto mais baixo do arco e solta ali, saindo em trajetória
## balística para frente. Sem isto, a única coisa que sobra é a atração da corda
## para a âncora, e o personagem parece "puxado" para o prédio.
func _apply_swing_kick() -> void:
	if not swing_kick_enabled or _controller == null:
		return
	var velocity := _controller.velocity
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < swing_kick_min_speed:
		return
	# O impulso vem da queda: quanto mais rápido vinha descendo, maior o ganho.
	var falling := maxf(0.0, -velocity.y)
	var gain := minf(falling * swing_kick_gain, swing_kick_max)
	# Impulso vertical: base fixa (o "salto" de soltura) + o que a queda acrescenta.
	var up := minf(swing_kick_up_base + falling * swing_kick_up_gain, swing_kick_up_max)
	if gain <= 0.0 and up <= 0.0:
		return
	var direction := flat.normalized()

	# Bônus de balanço completo: mede quanto do arco foi percorrido (do ângulo de
	# disparo até o ângulo mais alto alcançado). Um arco quase completo dá mais
	# empurrão para frente e para cima.
	var completion := 0.0
	var span := absf(_swing_angle_start)
	if span > 0.15:
		completion = clampf((_swing_angle() - _swing_angle_start) / (2.0 * span), 0.0, 1.0)
	var extra_forward := full_swing_forward * completion
	var extra_up := full_swing_up * completion

	_controller.velocity = Vector3(
		velocity.x + direction.x * (gain + extra_forward),
		velocity.y + up + extra_up,
		velocity.z + direction.z * (gain + extra_forward))


## Dispara a teia para o melhor ponto disponível, sem exigir mira.
func fire() -> bool:
	if _state != State.IDLE or _controller == null or _selector == null:
		return false

	var exclude: Array[RID] = [_controller.get_rid()]
	_update_floor_reference()
	var choice := _selector.select_target(
		_controller.global_position, _controller.velocity, _desired_direction,
				_camera, exclude, _floor_height)
	if not choice["valid"]:
		return false

	var anchor: Vector3 = choice["position"]
	var pivot_body := body_position()

	# --- Pivô de física ---
	# A corda gira em volta de um pivô que fica no PLANO de deslocamento (remove o
	# desvio lateral da âncora), para o arco não jogar o jogador de lado.
	var forward := Vector3(_controller.velocity.x, 0.0, _controller.velocity.z)
	if forward.length() < 1.0:
		forward = Vector3(anchor.x - pivot_body.x, 0.0, anchor.z - pivot_body.z)
	forward.y = 0.0
	if forward.length() > 0.01:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
	var dx := anchor.x - pivot_body.x
	var dz := anchor.z - pivot_body.z
	var along := dx * forward.x + dz * forward.z
	_pivot = Vector3(pivot_body.x + forward.x * along, anchor.y, pivot_body.z + forward.z * along)

	# --- Folga do arco ---
	# O fundo do arco (pivô.y - comprimento) precisa ficar `SWING_CLEARANCE` acima
	# do piso. Se a corda for longa demais para isso, o pivô SOBE (arco mais alto e
	# mais raso) em vez de a corda encurtar num tranco. É a técnica do Insomniac.
	var clearance_bottom := _floor_height + SWING_CLEARANCE
	var length := _pivot.distance_to(pivot_body)
	if _pivot.y - length < clearance_bottom:
		# Sobe o pivô o suficiente para o fundo do arco caber.
		_pivot.y = clearance_bottom + length
		length = _pivot.distance_to(pivot_body)
	length = clampf(length, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)

	_anchors = [anchor]
	_rope_lengths = [length]
	_anchor_count = 1
	_state = State.SWINGING
	_controller.swing_active = true
	_last_score = choice.get("score", 0.0)
	_swing_time = 0.0
	_swing_angle_start = _swing_angle()

	# --- Conservação de momento ao prender ---
	# A velocidade é girada para a TANGENTE do arco mantendo o módulo: a velocidade
	# do mergulho vira velocidade de balanço, sem tranco.
	var radial := (_pivot - pivot_body)
	if radial.length() > 0.01:
		radial = radial.normalized()
		var velocity := _controller.velocity
		var speed := velocity.length()
		var vr := velocity.dot(radial)
		var tangent := velocity - radial * vr
		if tangent.length() > 0.01 and speed > 0.5:
			_controller.velocity = tangent.normalized() * speed

	if _visual != null:
		_visual.show_strand(hand_position(), anchor)
	web_fired.emit(anchor, _last_score)
	return true


## Web Zip: puxa o jogador na direção de um alvo, com aceleração física.
func zip() -> bool:
	if _state != State.IDLE or _controller == null or _selector == null:
		return false

	var exclude: Array[RID] = [_controller.get_rid()]
	_update_floor_reference()
	var choice := _selector.select_target(
		_controller.global_position, _controller.velocity, _desired_direction,
				_camera, exclude, _floor_height)
	if not choice["valid"]:
		return false

	_zip_target = choice["position"]
	_state = State.ZIPPING
	_controller.swing_active = true
	if _visual != null:
		_visual.show_strand(hand_position(), _zip_target)
	zip_started.emit(_zip_target)
	return true


## Interrompe o Web Zip a qualquer momento.
func cancel_zip() -> void:
	if _state != State.ZIPPING:
		return
	_finish_zip()


func is_swinging() -> bool:
	return _state == State.SWINGING


func is_zipping() -> bool:
	return _state == State.ZIPPING


func is_busy() -> bool:
	return _state != State.IDLE


func anchor_count() -> int:
	return _anchor_count


func current_anchor() -> Vector3:
	return _anchors[0] if _anchor_count > 0 else Vector3.ZERO


func rope_length() -> float:
	return _rope_lengths[0] if _anchor_count > 0 else 0.0


func zip_target() -> Vector3:
	return _zip_target


func last_score() -> float:
	return _last_score


func arc_lowest_point() -> float:
	if _anchor_count == 0:
		return _floor_height
	return WebPhysics.arc_lowest_point(_pivot, _rope_lengths[0])


## Ângulo do corpo no arco, medido do pivô: 0 = embaixo, cresce ao subir.
func _swing_angle() -> float:
	if _anchor_count == 0:
		return 0.0
	var offset := body_position() - _pivot
	return atan2(offset.y, Vector2(offset.x, offset.z).length())


## Direção desejada pelo jogador, usada na seleção de alvo.
func set_desired_direction(direction: Vector3) -> void:
	_desired_direction = direction


func set_rope_length(value: float) -> void:
	if _anchor_count == 0:
		return
	var new_length := clampf(value, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)
	new_length = WebPhysics.safe_length(_pivot, new_length, _floor_height + SWING_CLEARANCE)
	var old_length := _rope_lengths[0]
	if is_equal_approx(old_length, new_length):
		return
	_controller.velocity = WebPhysics.apply_length_change(
		_controller.velocity, old_length, new_length)
	_rope_lengths[0] = new_length


func set_reel_input(value: float) -> void:
	_reel_input = clampf(value, -1.0, 1.0)


## Centro do corpo. A corda gira em volta dele, não dos pés.
func body_position() -> Vector3:
	if _controller == null:
		return Vector3.ZERO
	return _controller.global_position + Vector3(0.0, shoulder_height * 0.65, 0.0)


## Origem visual da teia: o osso da mão, quando há esqueleto.
func hand_position() -> Vector3:
	if _skeleton != null:
		var bone := _skeleton.find_bone(hand_bone_name)
		if bone >= 0:
			return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
	if _controller == null:
		return Vector3.ZERO
	return _controller.global_position + Vector3(0.0, shoulder_height, 0.0)


func release_speed() -> float:
	return _last_release_speed


## --- Passos de física ---

## Corrige a velocidade **antes** do move_and_slide. Não move ninguém.
func _step_swing_velocity(delta: float) -> bool:
	if _state != State.SWINGING or _anchor_count == 0:
		return false

	_update_floor_reference()
	_swing_time += delta
	if _reel_input != 0.0:
		set_rope_length(_rope_lengths[0] - _reel_input * REEL_RATE * delta)

	var pivot := body_position()
	var velocity := _controller.velocity
	# A restrição gira em volta do PIVÔ DE FÍSICA (que pode estar acima da âncora
	# visual, quando o arco precisa caber acima do piso).
	for index in _anchor_count:
		var result := WebPhysics.constrain_velocity(
			velocity, pivot, _pivot, _rope_lengths[index], ROPE_SLACK)
		velocity = result[0]

	# Desvio de fachada ANTECIPADO: um raio à frente do movimento; se achar parede,
	# gira a direção para a tangente dela antes do contato. É preventivo, não
	# reativo — o que evita o "bate de cara no prédio".
	velocity = _steer_away_from_facade(velocity, delta)

	# Empurrão para fora da parede: reforço quando já está perto.
	velocity = _push_away_from_wall(velocity, delta)

	# Assistencia de piso: se o corpo está chegando perto do chao, soma um pouco de
	# velocidade para cima. Evita o arco "raspar" o asfalto e o jogador bater de
	# cara no predio — o mesmo truque que os jogos do Aranha usam.
	var floor_limit := _floor_height + SWING_CLEARANCE * 0.5
	if _controller.global_position.y < floor_limit and velocity.y < 0.0:
		velocity.y += (floor_limit - _controller.global_position.y) * 6.0

	_controller.velocity = WebPhysics.clamp_speed(velocity)
	return true


## Desvia a direção do balanço ANTES de bater na fachada.
##
## Lança um raio à frente (na direção do movimento, até ~34 m) e, se achar parede,
## gira a velocidade para a tangente dela, com urgência proporcional à distância.
## Assim o jogador contorna o prédio em vez de se chocar com ele.
func _steer_away_from_facade(velocity: Vector3, delta: float) -> Vector3:
	if _controller == null:
		return velocity
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	if speed < 6.0:
		return velocity
	var world := _controller.get_world_3d()
	if world == null:
		return velocity
	var heading := flat / speed
	var look := clampf(speed * 0.9, 8.0, 34.0)
	var from := body_position()
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = from + heading * look
	query.exclude = [_controller.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return velocity
	var normal: Vector3 = hit["normal"]
	if absf(normal.y) > 0.5:
		return velocity
	var flat_normal := Vector3(normal.x, 0.0, normal.z)
	if flat_normal.length() < 0.01:
		return velocity
	flat_normal = flat_normal.normalized()
	var into := -(heading.x * flat_normal.x + heading.z * flat_normal.z)
	if into < 0.25:
		return velocity
	# Tangente da parede mais próxima da direção atual.
	var tangent := Vector3(-flat_normal.z, 0.0, flat_normal.x)
	if heading.dot(tangent) < 0.0:
		tangent = -tangent
	var urgency := clampf(1.0 - hit["position"].distance_to(from) / look, 0.0, 1.0)
	var target := (tangent + flat_normal * 0.3).normalized()
	var turn := heading.slerp(target, clampf((0.6 + 2.2 * urgency) * into * delta * 6.0, 0.0, 1.0))
	var new_flat := Vector3(turn.x, 0.0, turn.z).normalized() * speed
	velocity.x = new_flat.x
	velocity.z = new_flat.z
	return velocity


## Afasta o jogador da parede à frente durante o balanço.
##
## Sem isto, o arco tende a raspar a fachada do prédio em que a teia está presa —
## o jogador pediu para "ficar mais distante da parede". O raio sai do corpo na
## direção do movimento horizontal; se achar parede dentro de `wall_push_distance`,
## aplica uma aceleração na direção da normal da parede (para fora).
func _push_away_from_wall(velocity: Vector3, delta: float) -> Vector3:
	if _controller == null:
		return velocity
	var world := _controller.get_world_3d()
	if world == null:
		return velocity
	var from := body_position()
	# Duas sondagens: na direção do movimento E na direção da âncora (a fachada em
	# que a teia está presa). A segunda é o que evita o jogador "bater de cara" no
	# prédio da própria teia, que era o defeito relatado.
	var probes: Array[Vector3] = []
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.5:
		probes.append(flat.normalized())
	var to_anchor := _pivot - from
	to_anchor.y = 0.0
	if to_anchor.length() > 0.5:
		probes.append(to_anchor.normalized())
	if probes.is_empty():
		return velocity

	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [_controller.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for direction: Vector3 in probes:
		query.from = from
		query.to = from + direction * wall_probe_distance
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		# Só a componente horizontal da normal interessa: queremos afastar da
		# parede, não empurrar para cima ou para baixo.
		var flat_normal := Vector3(normal.x, 0.0, normal.z)
		if flat_normal.length() < 0.01:
			continue
		flat_normal = flat_normal.normalized()
		var distance: float = from.distance_to(hit["position"])
		var strength := wall_push_strength * clampf(
			1.0 - distance / maxf(wall_push_distance, 0.001), 0.0, 1.0)
		# Só empurra se ainda não estiver se afastando o bastante.
		var outward := velocity.dot(flat_normal)
		if outward < strength:
			velocity += flat_normal * (strength - outward) * delta * 4.0
	return velocity


## Corrige a posição **depois** do move_and_slide, de forma limitada.
##
## É aqui que mora o fim do teletransporte: por maior que seja o erro, o
## deslocamento num quadro nunca passa de `MAX_POSITION_CORRECTION`.
func _step_swing_position(delta: float) -> bool:
	if _state != State.SWINGING or _anchor_count == 0:
		return false
	var pivot := body_position()
	var correction := Vector3.ZERO
	for index in _anchor_count:
		correction += WebPhysics.position_correction(
			pivot, _anchors[index], _rope_lengths[index], ROPE_SLACK)
	if correction.is_zero_approx():
		return true
	_controller.move_and_collide(correction, false, 0.001, false)
	return true


## Impulso do Web Zip: aceleração contínua na direção do alvo.
func _step_zip(delta: float) -> bool:
	if _state != State.ZIPPING:
		return false

	var to_target := _zip_target - body_position()
	var distance := to_target.length()
	if distance < zip_arrival_distance:
		_finish_zip()
		return false

	var direction := to_target / distance
	var velocity := _controller.velocity

	# Separa a velocidade em "na direção do alvo" e "lateral". A puxada só
	# acelera a primeira; a lateral é amortecida, não zerada — é o que preserva
	# a inércia em vez de transformar o zip num trilho.
	var along := direction * velocity.dot(direction)
	var lateral := velocity - along
	lateral *= maxf(0.0, 1.0 - (1.0 - zip_lateral_keep) * delta * 4.0)

	var along_speed := along.length()
	var target_speed := minf(along_speed + zip_acceleration * delta, zip_max_speed)
	var new_velocity := direction * target_speed + lateral

	# A direção do alvo é considerada "para fora" da corda: o zip puxa, então a
	# componente de afastamento é preservada aqui (não é uma corda esticada).
	_controller.velocity = WebPhysics.clamp_speed(new_velocity)
	_controller.swing_active = true
	return true


func _finish_zip() -> void:
	_state = State.IDLE
	_controller.swing_active = false
	if _visual != null:
		_visual.hide_strand()
	if _camera_rig != null:
		_camera_rig.reset_spring_length()
	zip_finished.emit()


## Altura do piso sob o jogador, por raio para baixo. Funciona também no ar.
func _update_floor_reference() -> void:
	if _floor_query == null or _controller == null:
		return
	var world := _controller.get_world_3d()
	if world == null:
		return
	var exclude: Array[RID] = [_controller.get_rid()]
	var from := _controller.global_position + Vector3(0.0, 0.5, 0.0)
	_floor_query.from = from
	_floor_query.to = from + Vector3(0.0, -200.0, 0.0)
	_floor_query.exclude = exclude
	var hit := world.direct_space_state.intersect_ray(_floor_query)
	if not hit.is_empty():
		_floor_height = (hit["position"] as Vector3).y


func _delta_safe() -> float:
	return get_process_delta_time()
