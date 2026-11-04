class_name PlayerController
extends CharacterBody3D
## Controlador do personagem em terceira pessoa.
##
## Movimento relativo à câmera, gravidade, pulo (simples e duplo), escalada de
## parede, controle aéreo e rotação suave. O corpo não gira: apenas o nó
## `Visual`, para a câmera (filha do corpo) manter sua própria orientação.
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
signal wall_state_changed(climbing: bool)

enum WallState { NONE, CLIMBING }

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
## Amortecimento horizontal extra no ar, por segundo. Um valor maior faz o pulo
## perder velocidade em vez de "voar" até o destino.
@export var air_brake: float = 0.45

@export_group("Pulo duplo")
## Quantos pulos extras no ar. 1 = pulo duplo.
@export var extra_jumps: int = 1
## Fração da força do pulo aplicada no pulo extra.
@export var double_jump_scale: float = 0.92
## Empurrão horizontal que acompanha o pulo extra, na direção desejada.
@export var double_jump_forward: float = 3.0

@export_group("Escalada de parede")
## Distância do raio que procura a parede à frente.
@export var wall_check_distance: float = 0.9
## Velocidade de subida na parede, em m/s.
@export var climb_speed: float = 3.2
## Distância mínima da parede para começar a escalar.
@export var climb_attach_distance: float = 0.75
## Empurrão para fora da parede ao pular da escalada.
@export var wall_jump_push: float = 6.0
## Subida extra no pulo de parede.
@export var wall_jump_lift: float = 7.5

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
var _jumps_left: int = 1
var _wall_state: int = WallState.NONE
var _wall_normal: Vector3 = Vector3.ZERO
var _wall_query: PhysicsRayQueryParameters3D
## Última direção desejada, usada pelo pulo duplo e pela escalada.
var _last_direction: Vector3 = Vector3.ZERO

@onready var _visual: Node3D = get_node_or_null(visual_path)
@onready var _camera_rig: Node3D = get_node_or_null(camera_rig_path)


func _ready() -> void:
	PlayerInput.ensure_actions()
	add_to_group("player")
	_wall_query = PhysicsRayQueryParameters3D.new()
	_wall_query.collide_with_areas = false
	_wall_query.collide_with_bodies = true
	_jumps_left = extra_jumps + 1


func _physics_process(delta: float) -> void:
	var input := _read_move_input()
	var direction := _camera_relative_direction(input)
	var grounded := is_on_floor()
	var jump_pressed := _consume_jump()

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
		_apply_gravity(delta)
		_velocity_step(delta)
		move_and_slide()
		_position_step(delta)
		_face_velocity_direction(delta, grounded)
		_report_state()
		return

	if _wall_state == WallState.CLIMBING:
		_climb_step(direction, jump_pressed, delta, grounded)
		return

	_apply_horizontal_movement(direction, _target_speed(), delta, grounded)
	_apply_jump_and_gravity(jump_pressed, delta, grounded)
	move_and_slide()
	_face_movement_direction(direction, delta, grounded)
	_try_start_climb(direction, grounded)
	_report_state()


## Lê e consome o pedido de pulo (teclado + HUD).
func _consume_jump() -> bool:
	var pressed := _jump_requested or Input.is_action_just_pressed("jump")
	_jump_requested = false
	return pressed


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
		# No ar o controle e parcial: o jogador ajusta a trajetoria sem apagar o
		# impulso que ja tem. E o que preserva a inercia depois de soltar a teia.
		# NAO ha teto duro de velocidade: um teto mataria o impulso do balanco ao
		# soltar a teia. O que limita o pulo e o amortecimento, abaixo.
		horizontal += desired * air_control * acceleration * delta
		horizontal = horizontal.move_toward(Vector3.ZERO,
				(air_drag + air_brake) * horizontal.length() * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -0.1
	elif not is_on_floor():
		velocity.y -= gravity * delta


## Pulo no chão (restaura os pulos extras) e pulo duplo no ar.
func _apply_jump_and_gravity(jump_pressed: bool, delta: float, grounded: bool) -> void:
	if grounded:
		_jumps_left = extra_jumps + 1
		if jump_pressed:
			velocity.y = sqrt(2.0 * gravity * jump_height)
			_jumps_left -= 1
		elif velocity.y <= 0.0:
			velocity.y = -0.1
		return

	# No ar: pulo duplo enquanto houver pulos extras.
	if jump_pressed and _jumps_left > 0:
		_jumps_left -= 1
		velocity.y = sqrt(2.0 * gravity * jump_height) * double_jump_scale
		# Um empurrão leve na direção desejada, para o pulo duplo ir para onde o
		# jogador aponta em vez de subir reto.
		if _last_direction != Vector3.ZERO:
			velocity.x += _last_direction.x * double_jump_forward
			velocity.z += _last_direction.z * double_jump_forward
		return

	velocity.y -= gravity * delta


## --- Escalada de parede ---

## Procura parede à frente e começa a escalar, se o jogador estiver no ar e
## indo na direção dela.
##
## A direção testada é a do **movimento real** (velocidade), com a do joystick
## como reserva: é o que o corpo está fazendo agora, e evita depender de a câmera
## estar apontada para a parede.
func _try_start_climb(direction: Vector3, grounded: bool) -> void:
	if grounded or swing_active or _wall_state != WallState.NONE:
		return
	# Usa a própria detecção de parede do motor (`is_on_wall`), que já respeita a
	# colisão do corpo. É mais robusto do que um raio fino, que passava batido em
	# fachadas alinhadas com o eixo.
	if not is_on_wall():
		return
	var normal := get_wall_normal()
	normal.y = 0.0
	if normal.length() < 0.01:
		return
	normal = normal.normalized()
	_wall_normal = normal
	_wall_state = WallState.CLIMBING
	velocity = Vector3.ZERO
	wall_state_changed.emit(true)
	# Encara a parede.
	if _visual != null:
		_visual.rotation.y = atan2(-normal.x, -normal.z)


## Normal da parede à frente (Vector3.ZERO se não houver).
func _wall_ahead(direction: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return Vector3.ZERO
	var probe := direction
	if probe.length() < 0.01:
		probe = -global_transform.basis.z
		probe.y = 0.0
		if probe.length() < 0.01:
			return Vector3.ZERO
		probe = probe.normalized()
	var from := global_position + Vector3(0, 1.0, 0)
	_wall_query.from = from
	_wall_query.to = from + probe * wall_check_distance
	_wall_query.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(_wall_query)
	if hit.is_empty():
		return Vector3.ZERO
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	if normal.length() < 0.01:
		return Vector3.ZERO
	return normal.normalized()


func _climb_step(direction: Vector3, jump_pressed: bool, delta: float, grounded: bool) -> void:
	# Soltar no chão encerra a escalada.
	if grounded:
		_end_climb()
		return
	# Sem parede em contato: chegou ao topo (ou à borda). Solta subindo.
	if not is_on_wall():
		_end_climb()
		velocity.y = maxf(velocity.y, 3.0)
		move_and_slide()
		return
	var normal := get_wall_normal()
	normal.y = 0.0
	if normal.length() > 0.01:
		_wall_normal = normal.normalized()

	# Pular na parede solta o jogador, com um empurrão para trás e para cima.
	if jump_pressed:
		velocity = _wall_normal * wall_jump_push + Vector3.UP * wall_jump_lift
		_end_climb()
		move_and_slide()
		return

	# Na parede: o personagem SOBE sozinho (é o gesto de escalar). O joystick
	# esquerda/direita desliza pela superfície; puxar para trás (para longe da
	# parede) desce. Sem input, sobe.
	var right := _wall_normal.cross(Vector3.UP).normalized()
	var lateral := direction.dot(right) * walk_speed
	var vertical := climb_speed
	if direction.length() > 0.01:
		# `_wall_normal` aponta para FORA da parede. Componente positiva = puxando
		# para longe = descer.
		var outward := direction.dot(_wall_normal)
		if outward > 0.35:
			vertical = -climb_speed
	velocity = right * lateral + Vector3.UP * vertical - _wall_normal * 1.5
	move_and_slide()
	_face_velocity_direction(delta, false)
	_report_state()


func _end_climb() -> void:
	if _wall_state == WallState.CLIMBING:
		_wall_state = WallState.NONE
		wall_state_changed.emit(false)


func _face_movement_direction(direction: Vector3, delta: float, grounded: bool) -> void:
	if _visual == null or direction == Vector3.ZERO:
		return
	_last_direction = direction
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


func is_climbing() -> bool:
	return _wall_state == WallState.CLIMBING


func jumps_left() -> int:
	return _jumps_left


func set_move_vector(value: Vector2) -> void:
	_move_vector = value


func set_jump_requested() -> void:
	_jump_requested = true


func set_run_held(value: bool) -> void:
	_run_held = value


func set_sprint_held(value: bool) -> void:
	_sprint_held = value
