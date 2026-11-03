class_name TouchLookArea
extends Control
## Área de toque para girar a câmera.
##
## Emite `look` com o deslocamento em pixels desde o último evento. Cobre apenas
## a metade direita da tela para não disputar o toque com o joystick.

signal look(pixel_delta: Vector2)

var _active_pointer: int = -1
var _last_position: Vector2 = Vector2.ZERO
var _mouse_down: bool = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _active_pointer == -1:
			_active_pointer = event.index
			_last_position = event.position
		elif not event.pressed and event.index == _active_pointer:
			_active_pointer = -1
	elif event is InputEventScreenDrag and event.index == _active_pointer:
		look.emit(event.position - _last_position)
		_last_position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
		_last_position = event.position
	elif event is InputEventMouseMotion and _mouse_down:
		look.emit(event.relative)
