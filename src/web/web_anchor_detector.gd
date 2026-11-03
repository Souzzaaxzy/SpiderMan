class_name WebAnchorDetector
extends Node3D
## Encontra pontos válidos para ancorar a teia.
##
## Dispara um raio da câmera em direção ao centro da tela (o que o jogador está
## olhando) e valida o resultado antes de aceitar:
##  1. a superfície precisa ser estática (prédio, chão, plataforma);
##  2. o ponto precisa estar dentro da distância máxima;
##  3. o ponto precisa estar alto o bastante acima do jogador, senão a teia
##     nasceria já esticada e o balanço não renderia;
##  4. precisa haver linha de visão entre a mão do jogador e o ponto.
##
## Devolve um dicionário com `valid`, `position`, `normal` e `reason`, para o
## teste automatizado poder verificar exatamente por que um ponto foi rejeitado.

## Distância máxima de disparo, em metros.
@export var max_distance: float = 60.0
## Altura mínima do ponto acima do jogador, em metros.
@export var min_rise: float = 1.5
## Raio usado ao verificar a linha de visão, para não prender em quinas.
@export var sight_radius: float = 0.35
## Margem de recuo da parede ao fixar o ponto, para a teia não atravessar a face.
## O ponto recua PARA FORA da superfície (no sentido da normal), senão ficaria
## dentro do prédio e a verificação de linha de visão falharia.
@export var surface_offset: float = 0.15
## Altura, acima da origem do jogador, de onde se mede a linha de visão. Evita
## que o raio comece exatamente sobre o chão e detecte o próprio piso.
@export var sight_origin_height: float = 1.0

var _ray_query: PhysicsRayQueryParameters3D
var _sight_query: PhysicsRayQueryParameters3D
var _world: World3D


func _ready() -> void:
	_world = get_world_3d()
	# As consultas são reutilizadas a cada disparo: no Android, criar objetos de
	# física por quadro gera lixo e travadas.
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	_sight_query = PhysicsRayQueryParameters3D.new()
	_sight_query.collide_with_areas = false
	_sight_query.collide_with_bodies = true


## Procura uma ancoragem a partir de um raio de câmera.
## `exclude` deve conter o corpo do jogador, para a teia não grudar nele mesmo.
func find_anchor(camera: Camera3D, player_position: Vector3,
		exclude: Array[RID]) -> Dictionary:
	if camera == null or _world == null:
		return _invalid("sem camera")

	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * max_distance

	_ray_query.from = from
	_ray_query.to = to
	_ray_query.exclude = exclude
	var hit := _world.direct_space_state.intersect_ray(_ray_query)
	if hit.is_empty():
		return _invalid("nada na mira")

	var collider = hit.get("collider")
	if not _is_valid_surface(collider):
		return _invalid("superficie invalida")

	var normal: Vector3 = hit.get("normal", Vector3.UP)
	# Recua para FORA da superfície: o ponto precisa ficar no ar, não dentro do
	# prédio, senão a checagem de visão esbarraria na própria parede.
	var point: Vector3 = hit["position"] + normal * surface_offset

	if from.distance_to(point) > max_distance:
		return _invalid("longe demais")
	if point.y - player_position.y < min_rise:
		return _invalid("alto de menos")
	# A visão é medida da altura do peito, não dos pés: o piso à frente não pode
	# bloquear um alvo que está claramente visível.
	var eye := player_position + Vector3(0.0, sight_origin_height, 0.0)
	if not has_line_of_sight(eye, point, exclude):
		return _invalid("sem visao")

	return {"valid": true, "position": point, "normal": normal, "reason": ""}


## Confere se o ponto tem visão livre a partir do jogador, considerando o corpo
## dele como obstáculo apenas na saída (não bloqueia a si mesmo).
func has_line_of_sight(from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	_sight_query.from = from
	_sight_query.to = to
	_sight_query.exclude = exclude
	_sight_query.hit_from_inside = true
	return _world.direct_space_state.intersect_ray(_sight_query).is_empty()


## Só superfícies estáticas servem: nada de ancorar em outro personagem, em
## objeto em movimento ou em área de gatilho.
func _is_valid_surface(collider) -> bool:
	if collider is StaticBody3D:
		return true
	return false


func _invalid(reason: String) -> Dictionary:
	return {"valid": false, "position": Vector3.ZERO, "normal": Vector3.UP, "reason": reason}
