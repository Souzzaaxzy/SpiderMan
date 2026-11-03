class_name PlayerController
extends CharacterBody3D
## Controlador do personagem jogável em terceira pessoa.
##
## Movimento relativo à câmera, gravidade, pulo e rotação suave. O corpo do
## personagem NÃO gira: apenas o nó Visual, para que a câmera (filha do corpo)
## mantenha sua própria orientação. As entradas vêm do teclado e do joystick
## virtual (via os métodos `set_*`).

signal speed_changed(speed: float)
signal grounded_changed(grounded: bool)

@export_group("Movimento")
## Velocidade da caminhada, em metros por segundo.
@export var walk_speed: float = 3.2
## Velocidade da corrida, em metros por segundo.
@export var run_speed: float = 7.0
@export var acceleration: float = 14.0
@export var deceleration: float = 18.0
## Altura máxima do pulo, em metros.
@export var jump_height: float = 1.3
## Gravidade própria do personagem; maior que a física real dá um pulo mais seco.
@export var gravity: float = 22.0

@export_group("Rotação")
## Quão rápido o personagem encara a direção do movimento.
@export var turn_speed: float = 12.0

@export_group("Referências")
@export var visual_path: NodePath = ^"Visual"
@export var camera_rig_path: NodePath = ^"CameraRig"

var _move_vector: Vector2 = Vector2.ZERO
var _jump_requested: bool = false
var _run_held: bool = false
var _was_grounded: bool = true

@onready var _visual: Node3D = get_node_or_null(visual_path)
@onready var _camera_rig: Node3D = get_node_or_null(camera_rig_path)


func _ready() -> void:
	PlayerInput.ensure_actions()
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var input := _read_move_input()
	var direction := _camera_relative_direction(input)
	var wants_run := _run_held or Input.is_action_pressed("run")
	var target_speed := run_speed if wants_run else walk_speed

	_apply_horizontal_movement(direction, target_speed, delta)
	_apply_gravity_and_jump(delta)
	move_and_slide()
	_face_movement_direction(direction, delta)
	_report_state()


## Entradas de movimento no formato (x = direita, y = para trás), igual ao
## retorno de Input.get_vector. O joystick tem prioridade quando ativo.
func _read_move_input() -> Vector2:
	if _move_vector.length_squared() > 0.0:
		return _move_vector.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _camera_relative_direction(input: Vector2) -> Vector3:
	if input.length_squared() < 0.0001:
		return Vector3.ZERO
	var yaw := _camera_rig.global_rotation.y if _camera_rig != null else 0.0
	var basis := Basis(Vector3.UP, yaw)
	return (basis * Vector3(input.x, 0.0, input.y)).normalized()


func _apply_horizontal_movement(direction: Vector3, target_speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var desired := direction * target_speed
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	horizontal = horizontal.move_toward(desired, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_gravity_and_jump(delta: float) -> void:
	var grounded := is_on_floor()
	if grounded and velocity.y <= 0.0:
		velocity.y = -0.1

	var jump_pressed := _jump_requested or Input.is_action_just_pressed("jump")
	_jump_requested = false
	if jump_pressed and grounded:
		velocity.y = sqrt(2.0 * gravity * jump_height)
	elif not grounded:
		velocity.y -= gravity * delta


func _face_movement_direction(direction: Vector3, delta: float) -> void:
	if _visual == null or direction == Vector3.ZERO:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _report_state() -> void:
	speed_changed.emit(current_speed())
	var grounded := is_on_floor()
	if grounded != _was_grounded:
		_was_grounded = grounded
		grounded_changed.emit(grounded)


## Velocidade horizontal atual, usada pelo sistema de animação.
func current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_grounded() -> bool:
	return is_on_floor()


## Vetor do joystick virtual. x = direita, y = para trás (para cima é negativo).
func set_move_vector(value: Vector2) -> void:
	_move_vector = value


func set_jump_requested() -> void:
	_jump_requested = true


func set_run_held(value: bool) -> void:
	_run_held = value
