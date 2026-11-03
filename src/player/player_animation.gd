class_name PlayerAnimation
extends Node
## Animação do personagem, dirigida pela velocidade do controlador.
##
## Os clipes (`idle`, `walk`, `run`, `jump`) vêm assados no próprio `.glb`: o rig
## é do tipo Rigify em modo IK e depende de 279 constraints que não existem em
## glTF, então a pose foi calculada e assada no Blender por
## `tools/build_animations.py`. Aqui só escolhemos o clipe e ajustamos a
## velocidade de reprodução.
##
## Se o modelo não tiver os clipes (ex.: um bloco de teste sem esqueleto), cai no
## modo procedural.

@export_group("Referências")
@export var visual_path: NodePath = ^"../Visual"
@export var controller_path: NodePath = ^".."
@export var animation_player_path: NodePath = ^"../AnimationPlayer"

@export_group("Nomes dos clipes")
@export var idle_clip: StringName = &"idle"
@export var walk_clip: StringName = &"walk"
@export var run_clip: StringName = &"run"
@export var jump_clip: StringName = &"jump"

@export_group("Velocidades de referência")
## Velocidade em que o clipe de caminhada atinge a reprodução normal.
@export var walk_speed_reference: float = 3.2
## Velocidade em que o clipe de corrida atinge a reprodução normal.
@export var run_speed_reference: float = 7.0
## Acima desta velocidade usamos o clipe de corrida.
@export var run_threshold: float = 4.5

@export_group("Modo procedural (sem clipes)")
@export var swing_degrees: float = 30.0

@export_group("Balanço por teia")
## Postura de balanço: tronco inclinado e pernas recolhidas, aplicada por cima do
## clipe. Valores baixos de propósito — é um ajuste discreto, não uma animação
## falsa.
##
## Só a rotação é ajustada aqui, porque `set_bone_pose_rotation` funciona em
## qualquer osso. Já a posição dos controles IK não funciona: quem obedece ao
## controle são as constraints, que não existem em glTF. Por isso os braços
## caídos vêm assados nos clipes.
@export var swing_lean_degrees: float = 16.0
@export var swing_pose_blend_speed: float = 3.5
## Ossos usados na postura. Se algum não existir, o ajuste é ignorado.
@export var spine_bone: StringName = &"c_spine_02.x"
@export var thigh_bones: Array[StringName] = [&"c_thigh_fk.l", &"c_thigh_fk.r"]
@export var knee_bones: Array[StringName] = [&"c_leg_fk.l", &"c_leg_fk.r"]

var _controller: Node
var _visual: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _spine_index: int = -1
var _thigh_indices: Array[int] = []
var _knee_indices: Array[int] = []
var _swing_blend: float = 0.0
var _limbs: Array[Node3D] = []
var _phase: float = 0.0
var _current: StringName = &""
var _using_clips: bool = false


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_visual = get_node_or_null(visual_path)
	_player = get_node_or_null(animation_player_path)
	_using_clips = _player != null and _player.has_animation(idle_clip)
	if _using_clips:
		_configure_loops()
		_play(idle_clip, 1.0)
		_cache_swing_bones()
	else:
		_collect_limbs()


## Guarda os índices dos ossos da postura de balanço, uma vez só.
func _cache_swing_bones() -> void:
	_skeleton = _find_skeleton(_visual)
	if _skeleton == null:
		return
	_spine_index = _skeleton.find_bone(spine_bone)
	_thigh_indices = _resolve_bones(thigh_bones)
	_knee_indices = _resolve_bones(knee_bones)
	

func _resolve_bones(names: Array[StringName]) -> Array[int]:
	var indices: Array[int] = []
	for bone_name in names:
		indices.append(_skeleton.find_bone(bone_name))
	return indices


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## O glTF não carrega informação de loop: o importador da Godot deixa todos os
## clipes em "tocar uma vez". Os ciclos de locomoção precisam repetir; o pulo não.
func _configure_loops() -> void:
	for clip: StringName in [idle_clip, walk_clip, run_clip]:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if _player.has_animation(jump_clip):
		_player.get_animation(jump_clip).loop_mode = Animation.LOOP_NONE


func _process(delta: float) -> void:
	if _controller == null:
		return
	var speed: float = _controller.current_speed()
	var grounded: bool = _controller.is_grounded()
	if _using_clips:
		_drive_clips(speed, grounded)
		_apply_swing_pose(delta)
	else:
		_drive_procedural(speed, grounded, delta)

func _apply_swing_pose(delta: float) -> void:
	if _skeleton == null:
		return
	var target := 1.0 if _controller.swing_active else 0.0
	_swing_blend = move_toward(_swing_blend, target, swing_pose_blend_speed * delta)

	if is_zero_approx(_swing_blend):
		return

	var lean := deg_to_rad(swing_lean_degrees) * _swing_blend
	_rotate_bone(_spine_index, Vector3.RIGHT, lean)
	for index in _thigh_indices.size():
		_rotate_bone(_thigh_indices[index], Vector3.RIGHT, lean * 0.8)
	for index in _knee_indices.size():
		_rotate_bone(_knee_indices[index], Vector3.RIGHT, -lean * 0.9)


## Rotação em torno de um eixo global, convertida para o espaço do osso. É a
## mesma conversão que o Blender usou ao assar os clipes, então o resultado
## combina com o que já está animado.
func _rotate_bone(bone_index: int, world_axis: Vector3, angle: float) -> void:
	if bone_index < 0:
		return
	var rest := _skeleton.get_bone_rest(bone_index).basis
	var local := rest.inverse() * Basis(Quaternion(world_axis, angle)) * rest
	_skeleton.set_bone_pose_rotation(bone_index, local.get_rotation_quaternion())


## Escolhe o clipe pela velocidade e sincroniza a reprodução com o deslocamento,
## para o pé não "patinar" no chão.
func _drive_clips(speed: float, grounded: bool) -> void:
	if not grounded:
		_play(jump_clip, 1.0)
		return

	if speed < 0.2:
		_play(idle_clip, 1.0)
	elif speed < run_threshold:
		_play(walk_clip, clampf(speed / walk_speed_reference, 0.5, 1.6))
	else:
		_play(run_clip, clampf(speed / run_speed_reference, 0.7, 1.4))


func _play(clip: StringName, speed_scale: float) -> void:
	if _player == null or not _player.has_animation(clip):
		return
	if clip != _current:
		_current = clip
		_player.play(clip)
	_player.speed_scale = speed_scale


## Modo sem clipes: balança os membros de um bloco de teste.
func _collect_limbs() -> void:
	if _visual == null:
		return
	_limbs.clear()
	for limb_name: String in ["ArmLeft", "ArmRight", "LegLeft", "LegRight"]:
		var limb := _visual.get_node_or_null(limb_name) as Node3D
		if limb != null:
			_limbs.append(limb)


func _drive_procedural(speed: float, grounded: bool, delta: float) -> void:
	if _limbs.is_empty():
		return
	var amplitude := clampf(speed / maxf(run_speed_reference, 0.001), 0.0, 1.0)
	_phase += delta * (2.0 + speed * 1.6)
	var swing := sin(_phase) * deg_to_rad(swing_degrees) * amplitude
	for index: int in _limbs.size():
		var limb := _limbs[index]
		var is_arm := index < 2
		var side := 1.0 if index % 2 == 0 else -1.0
		var angle := swing * side * (0.75 if is_arm else 1.0)
		if not grounded:
			angle = deg_to_rad(-18.0 if is_arm else 12.0) * side
		limb.rotation.x = angle
