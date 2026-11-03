class_name PlayerHud
extends CanvasLayer
## Interface touchscreen que traduz toques em chamadas ao controlador e à câmera.
##
## Não contém lógica de movimento: apenas conecta os controles de tela aos nós
## responsáveis. Os caminhos são exportados para permitir reuso em outras cenas.

@export var controller_path: NodePath = ^".."
@export var camera_path: NodePath = ^"../CameraRig"
@export var web_path: NodePath = ^"../WebSwing"

@onready var _joystick: TouchJoystick = $Root/Joystick
@onready var _look_area: TouchLookArea = $Root/LookArea
@onready var _jump_button: Button = $Root/Actions/JumpButton
@onready var _run_button: Button = $Root/Actions/RunButton
@onready var _web_button: Button = $Root/Web/FireButton
@onready var _release_button: Button = $Root/Web/ReleaseButton
@onready var _reel_slider: HSlider = $Root/Web/ReelSlider

var _controller: Node
var _camera: Node
var _web: Node


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_camera = get_node_or_null(camera_path)
	_web = get_node_or_null(web_path)
	if _controller == null:
		push_warning("PlayerHud: controlador nao encontrado em '%s'." % controller_path)
		return

	_joystick.value_changed.connect(_on_joystick_moved)
	_jump_button.pressed.connect(_on_jump_pressed)
	_run_button.toggled.connect(_on_run_toggled)
	if _camera != null:
		_look_area.look.connect(_on_look_dragged)

	# Controles de teia. Se o modulo nao estiver na cena, os botoes ficam inertes
	# em vez de quebrar a HUD.
	if _web != null:
		_web_button.pressed.connect(_on_web_pressed)
		_release_button.pressed.connect(_on_release_pressed)
		_reel_slider.value_changed.connect(_on_reel_changed)
	else:
		_web_button.disabled = true
		_release_button.disabled = true
		_reel_slider.editable = false


func _on_joystick_moved(value: Vector2) -> void:
	if _controller != null:
		_controller.set_move_vector(value)


func _on_look_dragged(pixel_delta: Vector2) -> void:
	if _camera != null:
		_camera.add_look(pixel_delta)


func _on_jump_pressed() -> void:
	if _controller != null:
		_controller.set_jump_requested()


func _on_run_toggled(pressed: bool) -> void:
	if _controller != null:
		_controller.set_run_held(pressed)


func _on_web_pressed() -> void:
	if _web != null:
		_web.fire()


func _on_release_pressed() -> void:
	if _web != null:
		_web.release()


## O controle deslizante vale -1 (afrouxar) a +1 (recolher), com 0 no centro.
func _on_reel_changed(value: float) -> void:
	if _web != null:
		_web.set_reel_input(value)
