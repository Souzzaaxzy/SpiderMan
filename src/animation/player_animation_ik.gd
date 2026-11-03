class_name PlayerAnimationIK
extends Node
## Ajustes procedurais por cima do clipe: braços, tronco e pernas.
##
## ## O que isto é e o que não é
##
## Isto **não** é animação. São ajustes pequenos de rotação aplicados em memória
## sobre o clipe que já está tocando, para a pose reagir ao que o corpo está
## fazendo de verdade. A missão pede exatamente isso em 7.5, e ao mesmo tempo
## proíbe "rotações arbitrárias exageradas" — os ângulos aqui são contidos e
## limitados por export.
##
## O rig em disco **não é alterado**: tudo é escrito no `Skeleton3D` em tempo de
## execução, e o clipe volta ao normal quando o ajuste sai.
##
## ## Limite importante
##
## `set_bone_pose_rotation` funciona em qualquer osso. Já `set_bone_pose_position`
## nos controles IK **não funciona** na Godot: quem obedece ao controle são as
## constraints, que não existem em glTF. Por isso todo ajuste aqui é de rotação.

@export_group("Referências")
@export var controller_path: NodePath = ^".."
@export var web_path: NodePath = ^"../WebSwing"
@export var skeleton_path: NodePath = ^"../Visual/Model/rig/Skeleton3D"

@export_group("Braços na teia")
## Quanto o braço do lado da teia levanta na direção da ancoragem, em graus.
@export var arm_reach_degrees: float = 62.0
@export var arm_reach_blend_speed: float = 5.0
@export var upper_arm_bones: Array[StringName] = [&"c_shoulder.l", &"c_shoulder.r"]
## Braço usado pela teia (índice em `upper_arm_bones`). 1 = direito.
@export var web_arm_index: int = 1

@export_group("Tronco")
## Inclinação para frente conforme a aceleração horizontal, em graus.
@export var max_lean_degrees: float = 12.0
@export var lean_blend_speed: float = 4.0
@export var spine_bone: StringName = &"c_spine_02.x"

@export_group("Pernas")
## Recolhimento das pernas durante o balanço e a queda, em graus.
@export var tuck_degrees: float = 18.0
@export var tuck_blend_speed: float = 4.0
@export var thigh_bones: Array[StringName] = [&"c_thigh_fk.l", &"c_thigh_fk.r"]
@export var knee_bones: Array[StringName] = [&"c_leg_fk.l", &"c_leg_fk.r"]

var _controller: CharacterBody3D
var _web: Node
var _skeleton: Skeleton3D
var _upper_arms: Array[int] = []
var _thighs: Array[int] = []
var _knees: Array[int] = []
var _spine: int = -1
var _reach_blend: float = 0.0
var _tuck_blend: float = 0.0
var _lean_blend: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as CharacterBody3D
	_web = get_node_or_null(web_path)
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		_skeleton = _find_skeleton(get_node_or_null(^"../Visual"))
	if _skeleton == null:
		push_warning("PlayerAnimationIK: esqueleto nao encontrado; ajustes procedurais desativados.")
		return
	_upper_arms = _resolve(upper_arm_bones)
	_thighs = _resolve(thigh_bones)
	_knees = _resolve(knee_bones)
	_spine = _skeleton.find_bone(spine_bone)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _resolve(names: Array[StringName]) -> Array[int]:
	var indices: Array[int] = []
	for bone_name in names:
		indices.append(_skeleton.find_bone(bone_name))
	return indices


func _process(delta: float) -> void:
	if _skeleton == null or _controller == null:
		return
	_apply_arm_reach(delta)
	_apply_tuck(delta)
	_apply_lean(delta)
	_last_velocity = _controller.velocity


## O braço do lado da teia levanta na direção da ancoragem.
func _apply_arm_reach(delta: float) -> void:
	var swinging: bool = _web != null and (_web.is_swinging() or _web.is_zipping())
	_reach_blend = move_toward(_reach_blend, 1.0 if swinging else 0.0, arm_reach_blend_speed * delta)
	if is_zero_approx(_reach_blend) or _upper_arms.is_empty():
		return
	if web_arm_index < 0 or web_arm_index >= _upper_arms.size():
		return

	var bone := _upper_arms[web_arm_index]
	if bone < 0:
		return

	# Direção da mão até a ancoragem, em espaço de mundo, convertida para o osso.
	var target := Vector3.ZERO
	if _web.has_method("current_anchor") and _web.is_swinging():
		target = _web.current_anchor()
	elif _web.has_method("zip_target") and _web.is_zipping():
		target = _web.zip_target()
	if target == Vector3.ZERO:
		return

	var to_target := (target - _controller.global_position).normalized()
	# O braço aponta para o alvo: rotação em torno do eixo perpendicular.
	var horizontal := Vector3(to_target.x, 0.0, to_target.z)
	var angle := deg_to_rad(arm_reach_degrees) * _reach_blend
	if horizontal.length() > 0.01:
		var axis := Vector3.UP.cross(horizontal.normalized())
		_rotate_bone(bone, axis, angle)
	else:
		_rotate_bone(bone, Vector3.RIGHT, -angle)


## Pernas recolhidas no ar e no balanço: dá leitura de corpo no ar.
func _apply_tuck(delta: float) -> void:
	var airborne: bool = not _controller.is_grounded()
	_tuck_blend = move_toward(_tuck_blend, 1.0 if airborne else 0.0, tuck_blend_speed * delta)
	if is_zero_approx(_tuck_blend):
		return
	var angle := deg_to_rad(tuck_degrees) * _tuck_blend
	for bone in _thighs:
		_rotate_bone(bone, Vector3.RIGHT, angle)
	for bone in _knees:
		_rotate_bone(bone, Vector3.RIGHT, -angle)


## Tronco inclina conforme a aceleração: acelera para frente, freia para trás.
func _apply_lean(delta: float) -> void:
	if _spine < 0:
		return
	var velocity := _controller.velocity
	var acceleration := (velocity - _last_velocity) / maxf(delta, 0.0001)
	var forward_speed := acceleration.length() * signf(velocity.dot(acceleration))
	# Normaliza por uma aceleração de referência, para o ângulo ficar contido.
	var ratio := clampf(forward_speed / 40.0, -1.0, 1.0)
	_lean_blend = move_toward(_lean_blend, ratio, lean_blend_speed * delta)
	if is_zero_approx(_lean_blend):
		return
	_rotate_bone(_spine, Vector3.RIGHT, deg_to_rad(max_lean_degrees) * _lean_blend)


## Rotação em torno de um eixo global, convertida para o espaço do osso.
func _rotate_bone(bone_index: int, world_axis: Vector3, angle: float) -> void:
	if bone_index < 0 or world_axis.length() < 0.0001:
		return
	var rest := _skeleton.get_bone_rest(bone_index).basis
	var local := rest.inverse() * Basis(Quaternion(world_axis.normalized(), angle)) * rest
	_skeleton.set_bone_pose_rotation(bone_index, local.get_rotation_quaternion())


func reach_blend() -> float:
	return _reach_blend


func tuck_blend() -> float:
	return _tuck_blend
