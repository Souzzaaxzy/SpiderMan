extends SceneTree
## Retrato do personagem: fundo liso, luz frontal, câmera próxima.
##
## Serve para inspecionar a POSE com clareza — foi o que faltou nas missões
## anteriores, em que eu só media números sem nunca ver o personagem.
##
## Uso:
##   xvfb-run -a godot --path . --script res://tools/tests/capture_portrait.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const OUTPUT_DIR := "res://../shots"

var _player: Node3D
var _camera: Camera3D
var _dir: String


func _initialize() -> void:
	_run()


func _run() -> void:
	_dir = ProjectSettings.globalize_path("res://") + "../shots"
	DirAccess.make_dir_recursive_absolute(_dir)

	# Fundo liso, sem cenário: só o personagem.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.35, 0.4, 0.5)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	# Chão neutro, para dar referência de altura.
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 1.0, 30.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(collider)
	var ground_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	ground_mesh.mesh = box
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.5, 0.52, 0.55)
	ground_mesh.material_override = ground_material
	ground_mesh.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_mesh)
	root.add_child(ground)

	# Luz frontal, forte, para a silhueta ficar legível.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = false
	root.add_child(sun)

	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(_player)
	for _i in 90:
		await physics_frame

	# Câmera própria, em vez da do jogador: enquadra o corpo inteiro de perto.
	_camera = Camera3D.new()
	_camera.fov = 45.0
	root.add_child(_camera)
	_camera.make_current()

	var animator := _player.get_node("Visual/Model/AnimationPlayer") as AnimationPlayer
	var driver := _player.get_node("AnimationDriver")

	# --- Parado, de frente, de lado e de costas ---
	await _portrait("p1_parado_frente", 0.0)
	await _portrait("p2_parado_lado", 90.0)
	await _portrait("p3_parado_costas", 180.0)

	# --- Caminhada: vários instantes ---
	_player.set_move_vector(Vector2(0, -1))
	for i in 4:
		await _settle(10)
		await _portrait("p4_andando_%d" % i, 90.0)
	_player.set_move_vector(Vector2.ZERO)

	# --- Corrida ---
	_player.set_run_held(true)
	_player.set_move_vector(Vector2(0, -1))
	for i in 3:
		await _settle(10)
		await _portrait("p5_correndo_%d" % i, 90.0)
	_player.set_run_held(false)
	_player.set_move_vector(Vector2.ZERO)

	# --- Pulando ---
	await _settle(60)
	_player.set_jump_requested()
	for i in 3:
		await _settle(10)
		await _portrait("p6_pulando_%d" % i, 90.0)

	print("retratos salvos em %s" % _dir)
	quit(0)


func _settle(frames: int) -> void:
	for _index: int in frames:
		await process_frame


## Posiciona a câmera em volta do personagem e captura.
func _portrait(name: String, yaw_degrees: float) -> void:
	await process_frame
	var center := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := deg_to_rad(yaw_degrees)
	var offset := Vector3(sin(yaw), 0.0, cos(yaw)) * 4.0
	_camera.global_position = center + offset + Vector3(0.0, 0.4, 0.0)
	_camera.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		print("  falhou: %s" % name)
		return
	image.save_png("%s/%s.png" % [_dir, name])
	print("  salvo: %s.png" % name)
