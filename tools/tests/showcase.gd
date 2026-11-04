extends SceneTree
## Retratos limpos do personagem (sem HUD), para inspecao visual.
##
## Uso:
##   xvfb-run -a godot --path . --script res://tools/tests/showcase.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
var _player: Node3D
var _camera: Camera3D

func _initialize() -> void:
	_run()

func _run() -> void:
	var dir := ProjectSettings.globalize_path("res://") + "../shots"
	DirAccess.make_dir_recursive_absolute(dir)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	root.add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.8
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.9
	root.add_child(fill)

	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(_player)
	for _i in 60:
		await physics_frame
	var hud := _player.get_node_or_null("Hud")
	if hud != null:
		(hud as CanvasLayer).visible = false

	_camera = Camera3D.new()
	_camera.fov = 32.0
	root.add_child(_camera)
	_camera.make_current()

	await _shot("show_idle_front", 0.0)
	await _shot("show_idle_side", 90.0)
	await _shot("show_idle_back", 180.0)

	_player.set_move_vector(Vector2(0, -1))
	await _settle(50)
	await _shot("show_walk_side", 90.0)
	await _settle(20)
	await _shot("show_walk_front", 0.0)
	_player.set_run_held(true)
	await _settle(70)
	await _shot("show_run_side", 90.0)
	_player.set_run_held(false)
	_player.set_move_vector(Vector2.ZERO)
	await _settle(40)
	_player.set_jump_requested()
	await _settle(12)
	await _shot("show_jump", 60.0)
	print("showcase pronto")
	quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await physics_frame

func _shot(name: String, yaw_deg: float) -> void:
	var center := _player.global_position + Vector3(0, 1.0, 0)
	var yaw := deg_to_rad(yaw_deg)
	_camera.global_position = center + Vector3(sin(yaw), 0.0, cos(yaw)) * 4.0 + Vector3(0, 0.2, 0)
	_camera.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("res://../shots/%s.png" % name)
		print("salvo %s" % name)
