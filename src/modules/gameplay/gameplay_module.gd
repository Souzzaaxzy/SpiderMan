extends GameModule
## Módulo de gameplay.
##
## Instancia o mundo e o personagem jogável. O núcleo continua sem referência a
## tipos concretos de gameplay: tudo entra pelo ModuleRegistry.
##
## `world_scene` decide qual região carregar. O padrão é o distrito de Manhattan
## (MISSÃO 004); a arena de testes da MISSÃO 002 continua disponível para testar
## sistemas isolados, bastando trocar o caminho.

const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"
const ARENA_SCENE := "res://scenes/arena/test_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

@export var world_scene: String = DISTRICT_SCENE


func module_ready() -> void:
	var world := _instantiate(world_scene)
	if world == null:
		return
	add_child(world)

	var player := _instantiate(PLAYER_SCENE)
	if player == null:
		return
	# Nasce na calçada da borda do distrito, virado para o centro.
	player.position = _spawn_position(world)
	add_child(player)

	var label := "arena de teste" if world_scene == ARENA_SCENE else "distrito de Manhattan"
	print("[gameplay] Personagem e %s carregados." % label)


## Usa a posição de nascimento do mundo quando ele a oferece; senão, uma posição
## segura acima do chão.
func _spawn_position(world: Node) -> Vector3:
	if world.has_method("spawn_position"):
		return world.spawn_position()
	return Vector3(0.0, 1.2, 8.0)


func _instantiate(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("gameplay: nao foi possivel carregar '%s'." % scene_path)
		return null
	return packed.instantiate()
