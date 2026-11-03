class_name TouchJoystick
extends Control
## Joystick virtual para movimentação por toque.
##
## Emite `value_changed` com x = direita e y = para trás (para cima é negativo),
## no mesmo formato de `Input.get_vector`. Funciona com toque e, para testes em
## desktop, com o botão esquerdo do mouse.

signal value_changed(value: Vector2)

@export var knob_path: NodePath = ^"Knob"
## Fração do menor lado usada como raio máximo do joystick.
@export var max_radius_ratio: float = 0.40
## Movimentos menores que isto são tratados como zero.
@export var dead_zone: float = 0.08

var _active_pointer: int = -1
var _center: Vector2 = Vector2.ZERO
var _radius: float = 1.0

@onready var _knob: Control = get_node_or_null(knob_path)


func _ready() -> void:
	_refresh_geometry()
	resized.connect(_refresh_geometry)


func _refresh_geometry() -> void:
	_center = size * 0.5
	_radius = maxf(minf(size.x, size.y) * max_radius_ratio, 1.0)
	_reset_knob()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _active_pointer == -1:
			_active_pointer = event.index
			_update_from_local(event.position)
			accept_event()
		elif not event.pressed and event.index == _active_pointer:
			_release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _active_pointer:
		_update_from_local(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_active_pointer = 0
			_update_from_local(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _active_pointer == 0:
		_update_from_local(event.position)
		accept_event()


func _update_from_local(local_position: Vector2) -> void:
	var offset := local_position - _center
	if offset.length() > _radius:
		offset = offset.normalized() * _radius
	if _knob != null:
		_knob.position = _center + offset - _knob.size * 0.5
	var value := offset / _radius
	if value.length() < dead_zone:
		value = Vector2.ZERO
	value_changed.emit(value)


func _release() -> void:
	_active_pointer = -1
	_reset_knob()
	value_changed.emit(Vector2.ZERO)


func _reset_knob() -> void:
	if _knob != null:
		_knob.position = _center - _knob.size * 0.5
