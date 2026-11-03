class_name PlayerAnimation
extends Node
## Animação do personagem, baseada na velocidade do controlador.
##
## Dois modos, escolhidos automaticamente:
## 1. **Animator** — se existir um AnimationPlayer com animações nomeadas
##    (usado quando o modelo final for importado).
## 2. **Procedural** — sem animações disponíveis, balança os membros do bloco
##    de teste para dar leitura visual de caminhada, corrida e queda.

@export_group("Referências")
@export var visual_path: NodePath = ^"../Visual"
@export var animation_player_path: NodePath = ^"../AnimationPlayer"
@export var controller_path: NodePath = ^".."

@export_group("Nomes das animações do modelo")
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var run_animation: StringName = &"run"
@export var jump_animation: StringName = &"jump"

@export_group("Animação procedural")
@export var run_blend_start: float = 4.5
@export var swing_degrees: float = 30.0
@export var arm_swing_ratio: float = 0.75

var _controller: Node
var _visual: Node3D
var _animation_player: AnimationPlayer
var _limbs: Array[Node3D] = []
var _phase: float = 0.0
var _using_model_animations: bool = false
var _last_animation: StringName = &""


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_visual = get_node_or_null(visual_path)
	_animation_player = get_node_or_null(animation_player_path)
	_using_model_animations = _animation_player != null and _animation_player.get_animation_list().size() > 0
	if not _using_model_animations:
		_collect_limbs()


func _process(delta: float) -> void:
	if _controller == null:
		return
	var speed: float = _controller.current_speed()
	var grounded: bool = _controller.is_grounded()
	if _using_model_animations:
		_drive_model_animations(speed, grounded)
	else:
		_drive_procedural(speed, grounded, delta)


## Guarda referências aos membros do bloco de teste, quando presentes.
func _collect_limbs() -> void:
	if _visual == null:
		return
	_limbs.clear()
	for limb_name: String in ["ArmLeft", "ArmRight", "LegLeft", "LegRight"]:
		var limb := _visual.get_node_or_null(limb_name) as Node3D
		if limb != null:
			_limbs.append(limb)


func _drive_model_animations(speed: float, grounded: bool) -> void:
	var target: StringName
	if not grounded:
		target = jump_animation
	elif speed >= run_blend_start:
		target = run_animation
	elif speed > 0.2:
		target = walk_animation
	else:
		target = idle_animation
	_play_if_available(target)


func _play_if_available(animation_name: StringName) -> void:
	if animation_name == _last_animation:
		return
	if not _animation_player.has_animation(animation_name):
		return
	_last_animation = animation_name
	_animation_player.play(animation_name)


func _drive_procedural(speed: float, grounded: bool, delta: float) -> void:
	if _limbs.is_empty():
		return
	var amplitude := clampf(speed / maxf(run_blend_start, 0.001), 0.0, 1.0)
	_phase += delta * (2.0 + speed * 1.6)
	var swing := sin(_phase) * deg_to_rad(swing_degrees) * amplitude
	for index: int in _limbs.size():
		var limb := _limbs[index]
		var is_arm := index < 2
		var side := 1.0 if index % 2 == 0 else -1.0
		var angle := swing * side * (arm_swing_ratio if is_arm else 1.0)
		if not grounded:
			angle = deg_to_rad(-18.0 if is_arm else 12.0) * side
		limb.rotation.x = angle
