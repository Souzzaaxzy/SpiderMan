class_name WebVisual
extends Node3D
## Desenha a linha de teia entre a mão do jogador e a ancoragem.
##
## Usa um único MeshInstance3D com cilindro, esticado por transformação a cada
## quadro — nada de criar ou destruir objetos durante o balanço. O nó é apenas
## escondido quando não há teia ativa, então o custo em repouso é zero.

@export_group("Aparência")
## Espessura da teia, em metros.
@export var thickness: float = 0.06
@export var color: Color = Color(0.92, 0.94, 0.97, 1.0)
## Emissão fraca: a teia fica legível mesmo contra o céu claro.
@export var emission_energy: float = 0.25
@export var roughness: float = 0.4

## Ponto de origem, no espaço global (normalmente a mão do jogador).
var source: Vector3 = Vector3.ZERO
## Ponto de ancoragem, no espaço global.
var target: Vector3 = Vector3.ZERO

var _mesh_instance: MeshInstance3D
var _cylinder: CylinderMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_cylinder = CylinderMesh.new()
	# O cilindro da Godot nasce no eixo Y, com altura 1 e centrado na origem.
	_cylinder.height = 1.0
	_cylinder.top_radius = thickness * 0.5
	_cylinder.bottom_radius = thickness * 0.5
	_cylinder.radial_segments = 6
	_cylinder.rings = 1

	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = emission_energy
	_material.roughness = roughness

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Strand"
	_mesh_instance.mesh = _cylinder
	_mesh_instance.material_override = _material
	# A teia não precisa projetar sombra: economiza um passo de renderização.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	visible = false


## Liga a teia e posiciona a linha. `hand` e `anchor` em espaço global.
func show_strand(hand: Vector3, anchor: Vector3) -> void:
	source = hand
	target = anchor
	if not visible:
		visible = true
	_update_transform()


## Atualiza apenas as pontas, mantendo o resto da configuração.
func set_points(hand: Vector3, anchor: Vector3) -> void:
	source = hand
	target = anchor
	if visible:
		_update_transform()


## Esconde imediatamente. Não desaloca nada: o próximo disparo reusa a malha.
func hide_strand() -> void:
	visible = false


func is_showing() -> bool:
	return visible


func _update_transform() -> void:
	var delta := target - source
	var length := delta.length()
	if length < 0.001:
		visible = false
		return
	if not visible:
		visible = true
	# Escala Y = comprimento; a malha base tem altura 1.
	var direction := delta / length
	var up := Vector3.UP
	var basis: Basis
	if absf(direction.dot(up)) > 0.9999:
		basis = Basis()
	else:
		var axis := up.cross(direction).normalized()
		var angle := acos(clampf(up.dot(direction), -1.0, 1.0))
		basis = Basis(axis, angle)
	basis = basis.scaled(Vector3(1.0, length, 1.0))
	# O pivô do cilindro é o centro, então metade do caminho.
	_mesh_instance.global_transform = Transform3D(basis, source + delta * 0.5)
