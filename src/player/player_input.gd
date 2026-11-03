class_name PlayerInput
extends RefCounted
## Ações de entrada do jogador.
##
## As ações são registradas em tempo de execução para que o projeto não dependa
## de um bloco `[input]` extenso no project.godot. O joystick virtual escreve
## direto no controlador; o teclado existe para testes em desktop.

const ACTION_KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"run": [KEY_SHIFT],
	"web_fire": [KEY_E],
	"web_release": [KEY_Q],
	"web_reel_in": [KEY_R],
	"web_reel_out": [KEY_F],
}


static func ensure_actions() -> void:
	for action_name: String in ACTION_KEYS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode: int in ACTION_KEYS[action_name]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			if not InputMap.action_has_event(action_name, event):
				InputMap.action_add_event(action_name, event)
