class_name ThirdPersonCamera
extends Node3D
## Câmera em terceira pessoa com controle por toque.
##
## Este nó é o pivô da câmera e fica como filho do jogador, então acompanha o
## movimento automaticamente. O `SpringArm3D` cuida da colisão com o cenário e da
## suavização.
##
## ## Regra de ouro
##
## A câmera **nunca** controla a física do jogador. Ela lê o estado dele (posição,
## velocidade) e reage; não escreve nada. Na versão anterior isso era violado: o
## disparo da teia saía de um raio da câmera, então sem a câmera apontada não
## havia teia — a câmera mandava na física por tabela. Agora a seleção de alvo é
## independente, e a câmera só dá um bônus leve de desempate.
##
## ## Recursos dinâmicos
##
## - Comprimento do braço cresce com a velocidade.
## - Campo de visão (FOV) abre com a velocidade, para dar sensação de rapidez.
## - Inclinação lateral nas curvas.
## - Retorno suave ao repouso depois de soltar a teia.
##
## Todos os movimentos são suavizados, com valores conservadores: o objetivo é
## acompanhar a ação sem causar desconforto.

@export_group("Sensibilidade")
## Pixels de arrasto do mouse para girar 1 grau.
@export var mouse_pixels_per_degree: float = 4.0
## Pixels de arrasto na tela para girar 1 grau.
@export var touch_pixels_per_degree: float = 4.5

@export_group("Limites")
@export var min_pitch: float = -60.0
@export var max_pitch: float = 40.0
@export var start_pitch: float = -14.0
@export var start_yaw: float = 0.0

@export_group("Distância")
@export var rest_spring_length: float = 4.5
@export var fast_spring_length: float = 7.0
## Velocidade em que o braço chega ao comprimento máximo.
@export var fast_length_speed: float = 24.0
@export var length_lerp_speed: float = 2.5

@export_group("Campo de visão")
@export var rest_fov: float = 70.0
@export var fast_fov: float = 86.0
@export var fov_lerp_speed: float = 2.0

@export_group("Alinhamento e inclinação")
## Quanto do giro automático é aplicado por segundo durante o balanço. Baixo,
## para não tirar o controle manual do jogador.
@export var swing_align_speed: float = 1.6
## Inclinação lateral máxima, em graus, ao virar em alta velocidade.
@export var max_bank_degrees: float = 8.0
@export var bank_lerp_speed: float = 3.0

@export_group("Referências")
@export var spring_arm_path: NodePath = ^"SpringArm3D"
@export var camera_path: NodePath = ^"SpringArm3D/Camera3D"

var _yaw: float = 0.0
var _pitch: float = 0.0
var _pending_look: Vector2 = Vector2.ZERO
var _target_length: float = 4.5
var _target_fov: float = 70.0
var _bank: float = 0.0
var _last_forward: Vector3 = Vector3.FORWARD

@onready var _spring_arm: SpringArm3D = get_node_or_null(spring_arm_path)
@onready var _camera: Camera3D = get_node_or_null(camera_path)


func _ready() -> void:
	_yaw = deg_to_rad(start_yaw)
	_pitch = deg_to_rad(start_pitch)
	_target_length = rest_spring_length
	_target_fov = rest_fov
	if _spring_arm != null:
		_spring_arm.spring_length = rest_spring_length
	if _camera != null:
		_camera.fov = rest_fov
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse apenas para testes em desktop; no Android o toque vem da UI.
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		add_look(event.relative * (touch_pixels_per_degree / mouse_pixels_per_degree))


func _process(delta: float) -> void:
	if _pending_look != Vector2.ZERO:
		_apply_look(_pending_look)
		_pending_look = Vector2.ZERO
	_smooth_spring_length(delta)
	_smooth_fov(delta)
	_smooth_bank(delta)


func _smooth_spring_length(delta: float) -> void:
	if _spring_arm == null or is_equal_approx(_spring_arm.spring_length, _target_length):
		return
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, _target_length,
		clampf(length_lerp_speed * delta, 0.0, 1.0))


func _smooth_fov(delta: float) -> void:
	if _camera == null or is_equal_approx(_camera.fov, _target_fov):
		return
	_camera.fov = lerpf(_camera.fov, _target_fov, clampf(fov_lerp_speed * delta, 0.0, 1.0))


func _smooth_bank(delta: float) -> void:
	if _camera == null:
		return
	var current := _camera.rotation.z
	if is_equal_approx(current, _bank):
		return
	_camera.rotation.z = lerpf(current, _bank, clampf(bank_lerp_speed * delta, 0.0, 1.0))


## Chamado pelo sistema de teia a cada quadro do balanço.
##
## Afasta a câmera, abre o FOV e vai virando devagar para a direção do movimento.
## A inclinação lateral vem da variação da direção: virar rápido inclina.
func align_to_swing(velocity: Vector3, delta: float) -> void:
	_apply_dynamic_view(velocity, delta, true)


## Comportamento normal em alta velocidade: FOV e distância, sem alinhamento
## automático (o jogador mantém o controle da câmera).
func align_to_motion(velocity: Vector3, delta: float) -> void:
	_apply_dynamic_view(velocity, delta, false)


func _apply_dynamic_view(velocity: Vector3, delta: float, auto_align: bool) -> void:
	var speed := velocity.length()
	var ratio := clampf(speed / maxf(fast_length_speed, 0.001), 0.0, 1.0)
	_target_length = lerpf(rest_spring_length, fast_spring_length, ratio)
	_target_fov = lerpf(rest_fov, fast_fov, ratio)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 1.0:
		_bank = 0.0
		return
	var forward := flat.normalized()

	# Inclinação lateral proporcional a quanto a direção mudou neste quadro.
	var turn := forward.signed_angle_to(_last_forward, Vector3.UP)
	_last_forward = forward
	var bank_ratio := clampf(turn / maxf(delta * 2.5, 0.001), -1.0, 1.0)
	_bank = deg_to_rad(max_bank_degrees) * bank_ratio * clampf(speed / 12.0, 0.0, 1.0)

	if not auto_align:
		return
	var desired_yaw := atan2(-forward.x, -forward.z)
	_yaw = lerp_angle(_yaw, desired_yaw, clampf(swing_align_speed * delta, 0.0, 1.0))
	_apply_rotation()


## Volta o braço e o FOV ao repouso (ao soltar a teia).
func reset_spring_length() -> void:
	_target_length = rest_spring_length
	_target_fov = rest_fov
	_bank = 0.0


## Acumula um arrasto em pixels (toque ou mouse). Aplica no próximo quadro.
func add_look(pixel_delta: Vector2) -> void:
	_pending_look += pixel_delta


## Define o yaw da câmera em graus.
func set_yaw(degrees: float) -> void:
	_yaw = deg_to_rad(degrees)
	_pending_look = Vector2.ZERO
	_apply_rotation()


func get_yaw_degrees() -> float:
	return rad_to_deg(_yaw)


func spring_length() -> float:
	return _spring_arm.spring_length if _spring_arm != null else 0.0


func current_fov() -> float:
	return _camera.fov if _camera != null else 0.0


func _apply_look(pixel_delta: Vector2) -> void:
	_yaw -= deg_to_rad(pixel_delta.x / touch_pixels_per_degree)
	_pitch -= deg_to_rad(pixel_delta.y / touch_pixels_per_degree)
	_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	if _spring_arm != null:
		_spring_arm.rotation = Vector3(_pitch, 0.0, 0.0)
