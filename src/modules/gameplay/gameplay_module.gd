extends GameModule
## Módulo de gameplay da MISSÃO 002.
##
## Instancia o cenário de teste e o personagem jogável na cena de boot. O núcleo
## continua sem referência a tipos concretos de gameplay: tudo entra pelo
## ModuleRegistry. Para uma cena de produção, basta trocar `arena_scene`.

const ARENA_SCENE := "res://scenes/arena/test_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SPAWN_POSITION := Vector3(0.0, 1.2, 8.0)


func module_ready() -> void:
	var arena := _instantiate(ARENA_SCENE)
	if arena != null:
		add_child(arena)

	var player := _instantiate(PLAYER_SCENE)
	if player == null:
		return
	player.position = SPAWN_POSITION
	add_child(player)
	print("[gameplay] Personagem e cenario de teste carregados.")


func _instantiate(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("gameplay: nao foi possivel carregar '%s'." % scene_path)
		return null
	return packed.instantiate()
