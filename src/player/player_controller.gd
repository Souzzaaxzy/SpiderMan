class_name PlayerController
extends CharacterBody3D
## Controlador do personagem em terceira pessoa.
##
## Movimento relativo à câmera, gravidade, pulo, controle aéreo e rotação suave.
## O corpo não gira: apenas o nó `Visual`, para a câmera (filha do corpo)
## manter sua própria orientação.
##
## ## Ganchos de física externa
##
## O sistema de teias não assume o `move_and_slide`, que continua sendo
## responsabilidade deste script. Ele entra por três `Callable`, chamados em
## pontos precisos do ciclo:
##
## - `web_velocity_stepper` — antes do `move_and_slide`: corrige a **velocidade**.
## - `web_position_stepper` — depois: corrige a **posição** de forma limitada.
## - `web_zip_stepper` — durante o impulso de teia.
##
## Essa divisão é o que impede o teletransporte: a corda nunca impõe uma posição
## antes da física ter chance de resolver as colisões.

signal speed_changed(speed: float)
signal grounded_changed(grounded: bool)

@export_group("Movimento")
@export var walk_speed: float = 3.2
@export var run_speed: float = 7.0
@export var sprint_speed: float = 11.0
@export var acceleration: float = 14.0
@export var deceleration: float = 18.0
@export var jump_height: float = 1.3
## Gravidade própria do personagem; maior que a física real dá um pulo mais seco.
@export var gravity: float = 22.0

@export_group("Controle aéreo")
## Quanto o jogador consegue mudar de direção no ar. Baixo preserva o impulso.
@export var air_control: float = 0.35
## Amortecimento horizontal no ar, por segundo. 0 = nenhum.
@export var air_drag: float = 0.15

@export_group("Rotação")
@export var turn_speed: float = 12.0
## No ar o personagem gira mais devagar, para não parecer que está no chão.
@export var air_turn_speed: float = 5.0

@export_group("Referências")
@export var visual_path: NodePath = ^"Visual"
@export var camera_rig_path: NodePath = ^"CameraRig"

@export_group("Teias")
## Ligado pelo sistema de teia enquanto há corda ou impulso ativos.
@export var swing_active: bool = false
var web_velocity_stepper: Callable = Callable()
var web_position_stepper: Callable = Callable()
var web_zip_stepper: Callable = Callable()

var _move_vector: Vector2 = Vector2.ZERO
var _jump_requested: bool = false
var _run_held: bool = false
var _sprint_held: bool = false
var _was_grounded: bool = true

@onready var _visual: Node3D = get_node_or_null(visual_path)
@onready var _camera_rig: Node3D = get_node_or_null(camera_rig_path)


func _ready() -> void:
	PlayerInput.ensure_actions()
	add_to_group("player")


func _physics_process(delta: float) -> void:
	var input := _read_move_input()
	var direction := _camera_relative_direction(input)
	var grounded := is_on_floor()

	# O sistema de teia recebe a direção desejada, para escolher um alvo que
	# continue o movimento em vez de contrariá-lo.
	if swing_active:
		_push_desired_direction(direction)

	# O Web Zip tem o próprio passo e manda na velocidade enquanto durar.
	if _zip_step(delta):
		move_and_slide()
		_position_step(delta)
		_face_velocity_direction(delta, grounded)
		_report_state()
		return

	if swing_active:
		# No balanço o pêndulo manda. O jogador ainda pode bombear, mas o arco
		# vem da física, não do joystick.
		_apply_gravity_and_jump(delta)
		_velocity_step(delta)
		move_and_slide()
		_position_step(delta)
		_face_velocity_direction(delta, grounded)
		_report_state()
		return

	_apply_horizontal_movement(direction, _target_speed(), delta, grounded)
	_apply_gravity_and_jump(delta)
	move_and_slide()
	_face_movement_direction(direction, delta, grounded)
	_report_state()


func _push_desired_direction(direction: Vector3) -> void:
	if direction != Vector3.ZERO:
		_controller_desired(direction)


## Repassa a direção desejada ao sistema de teia, sem acoplar os dois scripts.
func _controller_desired(direction: Vector3) -> void:
	var web := get_node_or_null("WebSwing")
	if web != null and web.has_method("set_desired_direction"):
		web.set_desired_direction(direction)


func _velocity_step(delta: float) -> void:
	if web_velocity_stepper.is_valid():
		web_velocity_stepper.call(delta)


func _position_step(delta: float) -> void:
	if web_position_stepper.is_valid():
		web_position_stepper.call(delta)


func _zip_step(delta: float) -> bool:
	if not web_zip_stepper.is_valid():
		return false
	return web_zip_stepper.call(delta)


func _target_speed() -> float:
	if _sprint_held:
		return sprint_speed
	if _run_held or Input.is_action_pressed("run"):
		return run_speed
	return walk_speed


## Entradas no formato (x = direita, y = para trás). O joystick tem prioridade.
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


func _apply_horizontal_movement(direction: Vector3, target_speed: float,
		delta: float, grounded: bool) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var desired := direction * target_speed

	if grounded:
		var rate := acceleration if direction != Vector3.ZERO else deceleration
		horizontal = horizontal.move_toward(desired, rate * delta)
	else:
		# No ar o controle é parcial: o jogador ajusta a trajetória sem apagar o
		# impulso que já tem. É o que preserva a inércia depois de soltar a teia.
		horizontal += desired * air_control * acceleration * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, air_drag * horizontal.length() * delta)
		var limit := maxf(target_speed, sprint_speed)
		if horizontal.length() > limit:
			horizontal = horizontal.normalized() * limit

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


func _face_movement_direction(direction: Vector3, delta: float, grounded: bool) -> void:
	if _visual == null or direction == Vector3.ZERO:
		return
	var speed := turn_speed if grounded else air_turn_speed
	var target_yaw := atan2(-direction.x, -direction.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(speed * delta, 0.0, 1.0))


## Em movimento aéreo o personagem encara para onde está indo.
func _face_velocity_direction(delta: float, grounded: bool) -> void:
	if _visual == null:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 0.5:
		return
	var speed := turn_speed if grounded else air_turn_speed
	var target_yaw := atan2(-flat.x, -flat.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(speed * delta, 0.0, 1.0))


func _report_state() -> void:
	speed_changed.emit(current_speed())
	var grounded := is_on_floor()
	if grounded != _was_grounded:
		_was_grounded = grounded
		grounded_changed.emit(grounded)


func current_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func total_speed() -> float:
	return velocity.length()


func is_grounded() -> bool:
	return is_on_floor()


func is_airborne() -> bool:
	return not is_on_floor()


func set_move_vector(value: Vector2) -> void:
	_move_vector = value


func set_jump_requested() -> void:
	_jump_requested = true


func set_run_held(value: bool) -> void:
	_run_held = value


func set_sprint_held(value: bool) -> void:
	_sprint_held = value
