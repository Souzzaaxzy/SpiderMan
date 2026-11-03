class_name PlayerHud
extends CanvasLayer
## Interface touchscreen que traduz toques em chamadas ao controlador e à câmera.
##
## Não contém lógica de movimento: apenas conecta os controles de tela aos nós
## responsáveis. Os caminhos são exportados para permitir reuso em outras cenas.

@export var controller_path: NodePath = ^".."
@export var camera_path: NodePath = ^"../CameraRig"

@onready var _joystick: TouchJoystick = $Root/Joystick
@onready var _look_area: TouchLookArea = $Root/LookArea
@onready var _jump_button: Button = $Root/Actions/JumpButton
@onready var _run_button: Button = $Root/Actions/RunButton

var _controller: Node
var _camera: Node


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_camera = get_node_or_null(camera_path)
	if _controller == null:
		push_warning("PlayerHud: controlador nao encontrado em '%s'." % controller_path)
		return

	_joystick.value_changed.connect(_on_joystick_moved)
	_jump_button.pressed.connect(_on_jump_pressed)
	_run_button.toggled.connect(_on_run_toggled)
	if _camera != null:
		_look_area.look.connect(_on_look_dragged)


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
