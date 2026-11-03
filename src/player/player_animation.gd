class_name PlayerAnimation
extends Node
## Animação do personagem, baseada na velocidade do controlador.
##
## Dois modos, escolhidos automaticamente:
## 1. **Esqueleto** — quando existe um Skeleton3D no nó Visual. Dirige os ossos
##    de deformação do modelo (o rig do arquivo não traz clipes de animação).
## 2. **Procedural** — sem esqueleto, balança os membros de um bloco de teste.
##
## Os nomes de ossos abaixo foram confirmados no rig importado: são ossos cujo
## pai é um osso de controle, e que portanto deformam a malha.

@export_group("Referências")
@export var visual_path: NodePath = ^"../Visual"
@export var controller_path: NodePath = ^".."

@export_group("Velocidades de referência")
## Velocidade em que a passada atinge a amplitude máxima.
@export var run_blend_start: float = 4.5
## Frequência da passada andando e correndo (ciclos por segundo).
@export var walk_stride_rate: float = 1.6
@export var run_stride_rate: float = 2.6

@export_group("Amplitudes (graus)")
@export var leg_swing_walk: float = 22.0
@export var leg_swing_run: float = 38.0
@export var knee_bend: float = 26.0
@export var arm_swing_walk: float = 18.0
@export var arm_swing_run: float = 32.0
## Inclinação do tronco para frente ao correr.
@export var lean_run: float = 9.0
## Agachamento ao pular (dobra dos joelhos no ar).
@export var jump_crouch: float = 30.0

@export_group("Ossos do rig")
@export var thigh_bones: Array[String] = ["c_thigh_fk.l", "c_thigh_fk.r"]
@export var knee_bones: Array[String] = ["c_leg_fk.l", "c_leg_fk.r"]
@export var arm_bones: Array[String] = ["c_shoulder.l", "c_shoulder.r"]
@export var spine_bone: String = "c_spine_02.x"

var _controller: Node
var _visual: Node3D
var _skeleton: Skeleton3D
var _limbs: Array[Node3D] = []
var _thigh_indices: Array[int] = []
var _knee_indices: Array[int] = []
var _arm_indices: Array[int] = []
var _spine_index: int = -1
var _phase: float = 0.0
var _using_skeleton: bool = false


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_visual = get_node_or_null(visual_path)
	_skeleton = _find_skeleton(_visual)
	_using_skeleton = _skeleton != null
	if _using_skeleton:
		_cache_bones()
	else:
		_collect_limbs()


func _process(delta: float) -> void:
	if _controller == null:
		return
	var speed: float = _controller.current_speed()
	var grounded: bool = _controller.is_grounded()
	if _using_skeleton:
		_drive_skeleton(speed, grounded, delta)
	else:
		_drive_procedural(speed, grounded, delta)


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


func _cache_bones() -> void:
	_thigh_indices = _resolve(thigh_bones)
	_knee_indices = _resolve(knee_bones)
	_arm_indices = _resolve(arm_bones)
	_spine_index = _skeleton.find_bone(spine_bone)


func _resolve(names: Array[String]) -> Array[int]:
	var indices: Array[int] = []
	for bone_name in names:
		indices.append(_skeleton.find_bone(bone_name))
	return indices


## Dirige os ossos do rig. A fase avança com a velocidade, então a passada
## acelera junto com a corrida em vez de ficar em frequência fixa.
func _drive_skeleton(speed: float, grounded: bool, delta: float) -> void:
	var blend := clampf(speed / maxf(run_blend_start, 0.001), 0.0, 1.0)
	var moving := speed > 0.15
	if moving:
		_phase += delta * lerpf(walk_stride_rate, run_stride_rate, blend) * TAU

	var leg_amplitude := deg_to_rad(lerpf(leg_swing_walk, leg_swing_run, blend)) if moving else 0.0
	var arm_amplitude := deg_to_rad(lerpf(arm_swing_walk, arm_swing_run, blend)) if moving else 0.0

	for index in _thigh_indices.size():
		var side := 1.0 if index == 0 else -1.0
		var angle := sin(_phase) * leg_amplitude * side
		if not grounded:
			angle = deg_to_rad(jump_crouch) * 0.5 * side
		_rotate(_thigh_indices[index], Vector3.RIGHT, angle)

	for index in _knee_indices.size():
		var side := 1.0 if index == 0 else -1.0
		# O joelho dobra só para trás, então a amplitude é sempre positiva.
		var bend := deg_to_rad(knee_bend) * (0.5 + 0.5 * sin(_phase + PI)) if moving else 0.0
		if not grounded:
			bend = deg_to_rad(jump_crouch)
		_rotate(_knee_indices[index], Vector3.RIGHT, -absf(bend) * side)

	for index in _arm_indices.size():
		var side := 1.0 if index == 0 else -1.0
		# Braços em oposição às pernas do mesmo lado.
		_rotate(_arm_indices[index], Vector3.RIGHT, -sin(_phase) * arm_amplitude * side)

	if _spine_index >= 0:
		_rotate(_spine_index, Vector3.RIGHT, deg_to_rad(lean_run) * blend)


## Aplica uma rotação em torno de um eixo global, convertida para o espaço do osso.
func _rotate(bone_index: int, world_axis: Vector3, angle: float) -> void:
	if bone_index < 0:
		return
	if is_zero_approx(angle):
		_skeleton.set_bone_pose_rotation(bone_index, Quaternion())
		return
	var rest := _skeleton.get_bone_rest(bone_index).basis
	var local := rest.inverse() * Basis(Quaternion(world_axis, angle)) * rest
	_skeleton.set_bone_pose_rotation(bone_index, local.get_rotation_quaternion())


## Modo sem esqueleto: balança os membros do bloco de teste.
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
	var amplitude := clampf(speed / maxf(run_blend_start, 0.001), 0.0, 1.0)
	_phase += delta * (2.0 + speed * 1.6)
	var swing := sin(_phase) * deg_to_rad(leg_swing_run) * amplitude
	for index: int in _limbs.size():
		var limb := _limbs[index]
		var is_arm := index < 2
		var side := 1.0 if index % 2 == 0 else -1.0
		var angle := swing * side * (0.75 if is_arm else 1.0)
		if not grounded:
			angle = deg_to_rad(-18.0 if is_arm else 12.0) * side
		limb.rotation.x = angle
