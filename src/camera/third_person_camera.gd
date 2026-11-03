class_name ThirdPersonCamera
extends Node3D
## Câmera em terceira pessoa com controle por toque.
##
## Este nó é o pivô da câmera e fica como filho do personagem, então acompanha o
## movimento automaticamente. O SpringArm3D cuida da colisão com o cenário e da
## suavização. A rotação (yaw/pitch) é alimentada pelo arrasto na área direita
## da tela ou pelo mouse, para testes em desktop.

@export_group("Sensibilidade")
## Pixels de arrasto do mouse necessários para girar 1 grau.
@export var mouse_pixels_per_degree: float = 4.0
## Pixels de arrasto na tela necessários para girar 1 grau.
@export var touch_pixels_per_degree: float = 4.5

@export_group("Limites")
@export var min_pitch: float = -60.0
@export var max_pitch: float = 40.0
@export var start_pitch: float = -14.0
@export var start_yaw: float = 0.0

@export_group("Referências")
@export var spring_arm_path: NodePath = ^"SpringArm3D"

@export_group("Câmera dinâmica (balanço)")
## Comprimento do braço com o jogador devagar e na velocidade máxima.
@export var rest_spring_length: float = 4.5
@export var fast_spring_length: float = 6.5
## Velocidade em que o braço chega ao comprimento máximo.
@export var fast_length_speed: float = 22.0
## Quão rápido o comprimento e o alinhamento se ajustam (0 = nunca).
@export var length_lerp_speed: float = 2.5
## Quanto do giro automático é aplicado por segundo durante o balanço. Mantido
## baixo para não tirar o controle manual do jogador.
@export var swing_align_speed: float = 1.6

var _yaw: float = 0.0
var _pitch: float = 0.0
var _pending_look: Vector2 = Vector2.ZERO
var _target_length: float = 4.5

@onready var _spring_arm: SpringArm3D = get_node_or_null(spring_arm_path)


func _ready() -> void:
	_yaw = deg_to_rad(start_yaw)
	_pitch = deg_to_rad(start_pitch)
	_target_length = rest_spring_length
	if _spring_arm != null:
		_spring_arm.spring_length = rest_spring_length
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


## Aproxima suavemente o comprimento do braço do alvo, para a mudança de
## velocidade não dar um solavanco na câmera.
func _smooth_spring_length(delta: float) -> void:
	if _spring_arm == null:
		return
	if is_equal_approx(_spring_arm.spring_length, _target_length):
		return
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, _target_length,
		clampf(length_lerp_speed * delta, 0.0, 1.0))


## Chamado pelo sistema de teia a cada quadro do balanço: afasta a câmera com a
## velocidade e vai virando devagar para a direção do movimento.
func align_to_swing(velocity: Vector3, delta: float) -> void:
	var speed := velocity.length()
	var ratio := clampf(speed / maxf(fast_length_speed, 0.001), 0.0, 1.0)
	_target_length = lerpf(rest_spring_length, fast_spring_length, ratio)

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 1.0:
		return
	var desired_yaw := atan2(-flat.x, -flat.z)
	_yaw = lerp_angle(_yaw, desired_yaw, clampf(swing_align_speed * delta, 0.0, 1.0))
	_apply_rotation()


## Volta o braço ao comprimento de repouso (ao soltar a teia).
func reset_spring_length() -> void:
	_target_length = rest_spring_length


## Acumula um arrasto em pixels (toque ou mouse). Aplica no próximo frame.
func add_look(pixel_delta: Vector2) -> void:
	_pending_look += pixel_delta


## Define o yaw da câmera em graus. Usado ao reposicionar o personagem, para
## que a direção do movimento volte a ser previsível.
func set_yaw(degrees: float) -> void:
	_yaw = deg_to_rad(degrees)
	_pending_look = Vector2.ZERO
	_apply_rotation()


## Yaw atual da câmera, em graus.
func get_yaw_degrees() -> float:
	return rad_to_deg(_yaw)


func _apply_look(pixel_delta: Vector2) -> void:
	_yaw -= deg_to_rad(pixel_delta.x / touch_pixels_per_degree)
	_pitch -= deg_to_rad(pixel_delta.y / touch_pixels_per_degree)
	_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	if _spring_arm != null:
		_spring_arm.rotation = Vector3(_pitch, 0.0, 0.0)
