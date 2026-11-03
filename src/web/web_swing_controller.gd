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
@export var hand_bone_name: StringName = &"hand.r"
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
@export var swing_kick_gain: float = 0.45
## Teto do impulso, em m/s.
@export var swing_kick_max: float = 12.0

var _controller: CharacterBody3D
var _camera: Camera3D
var _camera_rig: Node3D
var _selector: WebTargetSelector
var _visual: WebVisual
var _skeleton: Skeleton3D

var _state: State = State.IDLE
var _anchors: Array[Vector3] = []
var _rope_lengths: Array[float] = []
var _anchor_count: int = 0
var _reel_input: float = 0.0
var _last_release_speed: float = 0.0
var _floor_height: float = 0.0
var _floor_query: PhysicsRayQueryParameters3D
var _last_score: float = 0.0

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
	if gain <= 0.0:
		return
	var direction := flat.normalized()
	_controller.velocity = Vector3(
		velocity.x + direction.x * gain,
		velocity.y,
		velocity.z + direction.z * gain)


## Dispara a teia para o melhor ponto disponível, sem exigir mira.
func fire() -> bool:
	if _state != State.IDLE or _controller == null or _selector == null:
		return false

	var exclude: Array[RID] = [_controller.get_rid()]
	var choice := _selector.select_target(
		_controller.global_position, _controller.velocity, _desired_direction,
		_camera, exclude)
	if not choice["valid"]:
		return false

	var anchor: Vector3 = choice["position"]
	# O comprimento nasce **igual à distância**: prender a teia não move o
	# jogador nem um milímetro. É o fim do tranco no disparo.
	var length := WebPhysics.length_without_snap(body_position(), anchor, MIN_ROPE_LENGTH)
	length = minf(length, MAX_ROPE_LENGTH)
	length = WebPhysics.safe_length(anchor, length, _floor_height + MIN_ARC_HEIGHT)

	_anchors = [anchor]
	_rope_lengths = [length]
	_anchor_count = 1
	_state = State.SWINGING
	_controller.swing_active = true
	_last_score = choice.get("score", 0.0)

	if _visual != null:
		_visual.show_strand(hand_position(), anchor)
	web_fired.emit(anchor, _last_score)
	return true


## Web Zip: puxa o jogador na direção de um alvo, com aceleração física.
func zip() -> bool:
	if _state != State.IDLE or _controller == null or _selector == null:
		return false

	var exclude: Array[RID] = [_controller.get_rid()]
	var choice := _selector.select_target(
		_controller.global_position, _controller.velocity, _desired_direction,
		_camera, exclude)
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
	return WebPhysics.arc_lowest_point(_anchors[0], _rope_lengths[0])


## Direção desejada pelo jogador, usada na seleção de alvo.
func set_desired_direction(direction: Vector3) -> void:
	_desired_direction = direction


func set_rope_length(value: float) -> void:
	if _anchor_count == 0:
		return
	var new_length := clampf(value, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)
	new_length = WebPhysics.safe_length(_anchors[0], new_length, _floor_height + MIN_ARC_HEIGHT)
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
	if _reel_input != 0.0:
		set_rope_length(_rope_lengths[0] - _reel_input * REEL_RATE * delta)

	var pivot := body_position()
	var velocity := _controller.velocity
	for index in _anchor_count:
		var result := WebPhysics.constrain_velocity(
			velocity, pivot, _anchors[index], _rope_lengths[index], ROPE_SLACK)
		velocity = result[0]

	_controller.velocity = WebPhysics.clamp_speed(velocity)
	return true


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
