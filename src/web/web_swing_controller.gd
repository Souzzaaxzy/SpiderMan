class_name WebSwingController
extends Node3D
## Sistema de teias e balanço.
##
## Coordena detecção de ancoragem, física do pêndulo e representação visual, sem
## misturar essa lógica ao controlador do jogador: este nó só pede ao
## PlayerController que aplique a velocidade resultante.
##
## A arquitetura já aceita mais de uma teia. Hoje só a teia 0 é usada, mas as
## ancoragens ficam em um arranjo e a física é aplicada em laço, então habilitar a
## segunda teia é uma questão de permitir um segundo disparo — não de reescrever.

signal web_fired(anchor: Vector3)
signal web_released(speed: float)

enum State { IDLE, SWINGING }

## Comprimento inicial da teia em relação à distância do disparo. Um pouco menos
## de 1 faz o jogador ser puxado levemente para dentro do arco ao prender.
const INITIAL_LENGTH_RATIO := 0.92
## Limites do comprimento ajustável, em metros.
const MIN_ROPE_LENGTH := 2.5
const MAX_ROPE_LENGTH := 55.0
## Quanto o comprimento muda por segundo ao segurar o controle de ajuste.
const REEL_RATE := 6.0

@export_group("Referências")
@export var controller_path: NodePath = ^".."
@export var camera_path: NodePath = ^"../CameraRig/SpringArm3D/Camera3D"
## Pivô da câmera, onde ficam o alinhamento e a distância dinâmica do balanço.
@export var camera_rig_path: NodePath = ^"../CameraRig"

@export var detector_path: NodePath = ^"WebAnchorDetector"
@export var visual_path: NodePath = ^"WebVisual"
## De onde a teia sai. O esqueleto tem um osso de mão; sem ele, usa o alto do corpo.
@export var hand_bone_name: StringName = &"hand.r"
@export var hand_offset: Vector3 = Vector3(0.0, 1.45, 0.35)

@export_group("Balanço")
## Ganho extra de impulso ao soltar, para o salto render mais. 1.0 = sem ganho.
@export var release_boost: float = 1.06
## Suavidade da câmera seguindo a direção do movimento (0 = instantâneo).
@export var camera_follow_speed: float = 2.5

var _controller: CharacterBody3D
var _camera: Camera3D
var _camera_rig: Node3D
var _detector: WebAnchorDetector
var _visual: WebVisual
var _skeleton: Skeleton3D

var _state: State = State.IDLE
## Uma entrada por teia ativa. Preparado para duas.
var _anchors: Array[Vector3] = []
var _rope_lengths: Array[float] = []
var _anchor_count: int = 0
var _reel_input: float = 0.0
var _release_requested: bool = false
var _last_release_speed: float = 0.0


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
	# O controlador pede o passo do balanço; assim o sistema de teia não precisa
	# assumir o move_and_slide, que continua sendo responsabilidade dele.
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
	# Teclado apenas para testes no PC; no Android os botões da HUD chamam os
	# mesmos métodos públicos.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				fire()
			KEY_Q:
				release()
			KEY_R:
				set_reel_input(1.0)
			KEY_F:
				set_reel_input(-1.0)
	elif event is InputEventKey and not event.pressed:
		if event.physical_keycode in [KEY_R, KEY_F]:
			set_reel_input(0.0)


func _process(_delta: float) -> void:
	if _state != State.SWINGING or _visual == null:
		return
	_visual.set_points(hand_position(), _anchors[0])
	if _camera_rig != null:
		_camera_rig.align_to_swing(_controller.velocity, _delta_safe())


## --- API pública (usada pela HUD e pelos testes) ---

## Dispara a teia em direção ao que a câmera aponta. Devolve true se ancorou.
func fire() -> bool:
	if _state == State.SWINGING or _controller == null or _detector == null:
		return false

	var exclude: Array[RID] = [_controller.get_rid()]
	var hit := _detector.find_anchor(_camera, _controller.global_position, exclude)
	if not hit["valid"]:
		return false

	var anchor: Vector3 = hit["position"]
	var distance := _controller.global_position.distance_to(anchor)
	var length := clampf(distance * INITIAL_LENGTH_RATIO, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)

	_anchors = [anchor]
	_rope_lengths = [length]
	_anchor_count = 1
	_state = State.SWINGING
	_controller.swing_active = true

	if _visual != null:
		_visual.show_strand(hand_position(), anchor)
	web_fired.emit(anchor)
	return true


## Solta a teia. A velocidade não é alterada além do impulso opcional, então o
## jogador mantém o arco.
func release() -> void:
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


func is_swinging() -> bool:
	return _state == State.SWINGING


func anchor_count() -> int:
	return _anchor_count


func current_anchor() -> Vector3:
	return _anchors[0] if _anchor_count > 0 else Vector3.ZERO


func rope_length() -> float:
	return _rope_lengths[0] if _anchor_count > 0 else 0.0


## Ajusta o comprimento da teia em metros, respeitando os limites.
func set_rope_length(value: float) -> void:
	if _anchor_count == 0:
		return
	var new_length := clampf(value, MIN_ROPE_LENGTH, MAX_ROPE_LENGTH)
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


## Ponto de origem da teia, no espaço global. Usa o osso da mão quando o modelo
## tem esqueleto, senão o alto do corpo.
func hand_position() -> Vector3:
	if _skeleton != null:
		var bone := _skeleton.find_bone(hand_bone_name)
		if bone >= 0:
			return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin
	return _controller.global_transform * hand_offset


func release_speed() -> float:
	return _last_release_speed


## --- Passo da física ---

## Aplicado pelo PlayerController dentro do próprio _physics_process, logo após
## a gravidade e antes do move_and_slide. Devolve false se não há balanço.
func _step_swing(delta: float) -> bool:
	if _state != State.SWINGING or _anchor_count == 0:
		return false

	if _reel_input != 0.0:
		set_rope_length(_rope_lengths[0] - _reel_input * REEL_RATE * delta)

	var velocity := _controller.velocity
	# Cada teia restringe a posição à sua esfera. Com uma teia, é o pêndulo
	# clássico; com duas, a interseção das duas esferas.
	for index in _anchor_count:
		var result := WebPhysics.apply_rope_constraint(
			_controller.global_position, velocity, _anchors[index], _rope_lengths[index])
		_controller.global_position = result[0]
		velocity = result[1]

	_controller.velocity = WebPhysics.clamp_speed(velocity)
	return true


func _delta_safe() -> float:
	return get_process_delta_time()
