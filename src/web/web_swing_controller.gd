class_name WebSwingController
extends Node3D
## Sistema de teias e balanço.
##
## Coordena detecção de ancoragem, física do pêndulo e representação visual, sem
## misturar essa lógica ao controlador do jogador: este nó só pede ao
## PlayerController que aplique a velocidade resultante.
##
## Controle: **um único botão**. Segurar dispara e mantém a teia presa; soltar
## libera. `press()` e `release()` são chamados pela HUD (toque) e pelo teclado.
##
## A arquitetura já aceita mais de uma teia: as ancoragens ficam em arranjo e a
## física é aplicada em laço.

signal web_fired(anchor: Vector3)
signal web_released(speed: float)

enum State { IDLE, SWINGING }

## Comprimento inicial da corda em relação à distância do disparo. Menor que 1
## faz o jogador ser puxado levemente para dentro do arco ao prender.
const INITIAL_LENGTH_RATIO := 0.92
## Folga da corda, em metros: enquanto o jogador está dentro do raio + folga, a
## corda está frouxa e não interfere. Dá a sensação de queda livre no início.
const ROPE_SLACK := 1.2
## Altura mínima do ponto mais baixo do arco, acima do piso. Sem isto o arco
## desce abaixo do chão e o jogador é arrastado por ele.
const MIN_ARC_HEIGHT := 1.6

## Limites do comprimento ajustável, em metros.
const MIN_ROPE_LENGTH := 3.0
const MAX_ROPE_LENGTH := 55.0
## Quanto o comprimento muda por segundo ao segurar o controle de ajuste.
const REEL_RATE := 7.0

@export_group("Referências")
@export var controller_path: NodePath = ^".."
@export var camera_path: NodePath = ^"../CameraRig/SpringArm3D/Camera3D"
## Pivô da câmera, onde ficam o alinhamento e a distância dinâmica do balanço.
@export var camera_rig_path: NodePath = ^"../CameraRig"

@export var detector_path: NodePath = ^"WebAnchorDetector"
@export var visual_path: NodePath = ^"WebVisual"
## De onde a teia sai: o osso da mão, quando o modelo tem esqueleto.
@export var hand_bone_name: StringName = &"hand.r"
## Altura do ombro em relação à base do jogador, usada como origem da teia
## enquanto o esqueleto não estiver disponível no primeiro quadro.
@export var shoulder_height: float = 1.5

@export_group("Balanço")
## Ganho extra de impulso ao soltar, para o salto render mais. 1.0 = sem ganho.
@export var release_boost: float = 1.05
## Suavidade do alinhamento automático da câmera durante o balanço.
@export var camera_follow_speed: float = 2.5

var _controller: CharacterBody3D
var _camera: Camera3D
var _camera_rig: Node3D
var _detector: WebAnchorDetector
var _visual: WebVisual
var _skeleton: Skeleton3D

var _state: State = State.IDLE
var _anchors: Array[Vector3] = []
var _rope_lengths: Array[float] = []
var _anchor_count: int = 0
var _reel_input: float = 0.0
var _last_release_speed: float = 0.0
## Altura mínima que o arco pode alcançar, para não atravessar o piso.
var _floor_height: float = 0.0
var _floor_query: PhysicsRayQueryParameters3D


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as CharacterBody3D
	_camera = get_node_or_null(camera_path) as Camera3D
	_camera_rig = get_node_or_null(camera_rig_path)
	_detector = get_node_or_null(detector_path) as WebAnchorDetector
	_visual = get_node_or_null(visual_path) as WebVisual
	_skeleton = _find_skeleton(_controller)

	if _controller == null:
		push_warning("WebSwingController: controlador nao encontrado em '%s'." % controller_path)
		return
	# A consulta do chão é criada uma vez e reusada: no Android, criar objetos de
	# física por quadro gera lixo.
	_floor_query = PhysicsRayQueryParameters3D.new()
	_floor_query.collide_with_areas = false
	_floor_query.collide_with_bodies = true
	# O controlador pede o passo do balanço; assim o sistema de teia não assume o
	# move_and_slide, que continua sendo responsabilidade dele.
	_controller.web_stepper = _step_swing


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
	# Teclado apenas para testes no PC; no Android o botão da HUD chama os mesmos
	# métodos públicos.
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


func _process(_delta: float) -> void:
	if _state != State.SWINGING:
		return
	if _visual != null:
		_visual.set_points(hand_position(), _anchors[0])
	if _camera_rig != null:
		_camera_rig.align_to_swing(_controller.velocity, _delta_safe())


## --- API pública (usada pela HUD e pelos testes) ---

## Segurar o botão: dispara a teia se ainda não houver, ou recolhe se já houver.
func press() -> void:
	if _state == State.SWINGING:
		set_reel_input(1.0)
		return
	fire()


## Soltar o botão: solta a teia.
func release() -> void:
	set_reel_input(0.0)
	if _state != State.SWINGING:
		return
	_state = State.IDLE
	_anchor_count = 0
	_last_release_speed = _controller.velocity.length() if _controller != null else 0.0

	if _controller != null:
		_controller.swing_active = false
		if release_boost != 1.0:
			_controller.velocity *= release_boost
	if _visual != null:
		_visual.hide_strand()
	if _camera_rig != null:
		_camera_rig.reset_spring_length()

	web_released.emit(_last_release_speed)


## Dispara a teia em direção ao que a câmera aponta. Devolve true se ancorou.
func fire() -> bool:
	if _state == State.SWINGING or _controller == null or _detector == null:
		return false

	var exclude: Array[RID] = [_controller.get_rid()]
	var hit := _detector.find_anchor(_camera, _controller.global_position, exclude)
	if not hit["valid"]:
		return false

	var anchor: Vector3 = hit["position"]
	var pivot := body_position()
	var distance := pivot.distance_to(anchor)
	var length := clampf(distance * INITIAL_LENGTH_RATIO, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)
	# Garante que o fundo do arco fique acima do piso: sem isto o jogador é
	# arrastado pelo chão em vez de balançar.
	length = WebPhysics.safe_length(anchor, length, _floor_height + MIN_ARC_HEIGHT)

	_anchors = [anchor]
	_rope_lengths = [length]
	_anchor_count = 1
	_state = State.SWINGING
	_controller.swing_active = true

	if _visual != null:
		_visual.show_strand(hand_position(), anchor)
	web_fired.emit(anchor)
	return true


func is_swinging() -> bool:
	return _state == State.SWINGING


func anchor_count() -> int:
	return _anchor_count


func current_anchor() -> Vector3:
	return _anchors[0] if _anchor_count > 0 else Vector3.ZERO


func rope_length() -> float:
	return _rope_lengths[0] if _anchor_count > 0 else 0.0


## Altura do ponto mais baixo do arco atual.
func arc_lowest_point() -> float:
	if _anchor_count == 0:
		return _floor_height
	return WebPhysics.arc_lowest_point(_anchors[0], _rope_lengths[0])


## Ajusta o comprimento da teia em metros, respeitando os limites e o piso.
func set_rope_length(value: float) -> void:
	if _anchor_count == 0:
		return
	var new_length := clampf(value, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)
	new_length = WebPhysics.safe_length(_anchors[0], new_length, _floor_height + MIN_ARC_HEIGHT)
	var old_length := _rope_lengths[0]
	if is_equal_approx(old_length, new_length):
		return
	# Preserva o momento angular: recolher a teia acelera o balanço.
	_controller.velocity = WebPhysics.apply_length_change(
		_controller.velocity, old_length, new_length)
	_rope_lengths[0] = new_length


## Entrada contínua de ajuste: -1 afrouxa, +1 recolhe, 0 mantém.
func set_reel_input(value: float) -> void:
	_reel_input = clampf(value, -1.0, 1.0)


## Centro do corpo do jogador. A corda gira em volta do corpo, não dos pés —
## pendurar pelo pé é o que fazia o personagem "se arrastar" pelo chão.
func body_position() -> Vector3:
	if _controller == null:
		return Vector3.ZERO
	return _controller.global_position + Vector3(0.0, shoulder_height * 0.65, 0.0)


## Ponto de origem da teia, no espaço de mundo. Usa o osso da mão quando o
## esqueleto existe; senão, a altura do ombro.
func hand_position() -> Vector3:
	if _skeleton != null:
		var bone := _skeleton.find_bone(hand_bone_name)
		if bone >= 0:
			# A pose do osso é relativa ao esqueleto, então precisa do transform
			# global dele para virar posição de mundo.
			return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
	if _controller == null:
		return Vector3.ZERO
	return _controller.global_position + Vector3(0.0, shoulder_height, 0.0)


func release_speed() -> float:
	return _last_release_speed


## --- Passo da física ---

## Aplicado pelo PlayerController dentro do próprio _physics_process, logo após a
## gravidade e antes do move_and_slide. Devolve false se não há balanço.
func _step_swing(delta: float) -> bool:
	if _state != State.SWINGING or _anchor_count == 0:
		return false

	_update_floor_reference()

	if _reel_input != 0.0:
		set_rope_length(_rope_lengths[0] - _reel_input * REEL_RATE * delta)

	# A restrição age sobre o corpo, então medimos a partir dele e devolvemos o
	# deslocamento para a base do jogador.
	var pivot := body_position()
	var velocity := _controller.velocity
	var correction := Vector3.ZERO
	for index in _anchor_count:
		var result := WebPhysics.apply_rope_constraint(
			pivot, velocity, _anchors[index], _rope_lengths[index], ROPE_SLACK)
		correction += (result[0] as Vector3) - pivot
		velocity = result[1]

	_controller.global_position += correction
	_controller.velocity = WebPhysics.clamp_speed(velocity)
	return true


## Descobre a altura do piso sob o jogador, para o arco não descer abaixo dele.
##
## Um raio para baixo é mais confiável que `is_on_floor`: funciona também no ar
## (por exemplo, ao disparar a teia depois de saltar de um telhado), onde
## `is_on_floor` seria falso e a altura ficaria desatualizada.
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
