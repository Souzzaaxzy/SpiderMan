extends SceneTree
## Captura imagens do jogo rodando, para inspeção visual.
##
## Este é o teste que faltava: em vez de só medir números, tira fotos do
## personagem em cada situação e salva em disco. É o que permite ver se a pose
## está natural ou se o personagem "parece um alienígena se mexendo".
##
## Uso:
##   xvfb-run -a godot --path . --script res://tools/tests/capture_shots.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"
const OUTPUT_DIR := "res://../shots"

var _player: Node3D
var _web: Node
var _camera: Camera3D
var _rig: Node3D
var _spring: SpringArm3D
var _shots: int = 0
var _dir: String


func _initialize() -> void:
	_run()


func _run() -> void:
	_dir = ProjectSettings.globalize_path("res://") + "../shots"
	DirAccess.make_dir_recursive_absolute(_dir)
	print("salvando imagens em: %s" % _dir)

	var district := (load(DISTRICT_SCENE) as PackedScene).instantiate()
	root.add_child(district)
	await process_frame
	await process_frame
	var city: CityGenerator = district.call("city")

	_player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(_player)
	await process_frame
	await process_frame

	_web = _player.get_node_or_null("WebSwing")
	_camera = _player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
	_rig = _player.get_node_or_null("CameraRig")
	_spring = _player.get_node_or_null("CameraRig/SpringArm3D")

	# --- Parado, de perto: é aqui que a pose ruim apareceria ---
	await _place(Vector3(-28.0, 1.2, -12.3), 0.0, -5.0)
	await _settle(150)
	await _shot("01_parado_frente")
	await _orbit_and_shot("02_parado_lado", 90.0)
	await _orbit_and_shot("03_parado_costas", 180.0)

	# --- Parado visto de muito perto, para inspecionar a pose ---
	await _close_up("04_parado_close")

	# --- Caminhando ---
	_player.set_move_vector(Vector2(0, -1))
	await _settle(60)
	await _shot("05_andando")
	await _settle(20)
	await _shot("06_andando_b")

	# --- Correndo ---
	_player.set_run_held(true)
	await _settle(90)
	await _shot("07_correndo")
	await _settle(20)
	await _shot("08_correndo_b")
	_player.set_run_held(false)
	_player.set_move_vector(Vector2.ZERO)

	# --- Pulando ---
	await _place(Vector3(-28.0, 1.2, -12.3), 0.0, -5.0)
	await _settle(60)
	_player.set_jump_requested()
	await _settle(14)
	await _shot("09_pulando")
	await _settle(40)
	await _shot("10_caindo")

	# --- Balanço com teia ---
	await _place(Vector3(-28.0, 16.0, 4.0), 180.0, 10.0)
	_player.velocity = Vector3(0.0, 0.0, -6.0)
	await _settle(4)
	var fired: bool = _web.fire()
	if fired:
		await _settle(30)
		await _shot("11_balanco_inicio")
		await _settle(40)
		await _shot("12_balanco_meio")
		await _settle(40)
		await _shot("13_balanco_fim")
		_web.release()

	# --- Web Zip ---
	await _place(Vector3(-28.0, 3.0, 6.0), 90.0, 8.0)
	await _settle(20)
	if _web.zip():
		await _settle(20)
		await _shot("14_zip")

	# --- Visão geral do distrito ---
	await _place(Vector3(-28.0, 40.0, 20.0), 90.0, -15.0)
	await _settle(30)
	await _shot("15_distrito")

	print("total de imagens: %d" % _shots)
	quit(0)


func _place(position: Vector3, yaw: float, pitch: float) -> void:
	if _web.is_busy():
		_web.release()
		_web.cancel_zip()
	_player.velocity = Vector3.ZERO
	_player.swing_active = false
	_player.global_position = position
	_player.set_move_vector(Vector2.ZERO)
	_player.set_run_held(false)
	if _rig != null:
		_rig.set_yaw(yaw)
	if _spring != null:
		_spring.rotation = Vector3(deg_to_rad(pitch), 0.0, 0.0)
	await process_frame
	await process_frame


## Espera em frames de processo (renderização), não de física.
func _settle(frames: int) -> void:
	for _index: int in frames:
		await process_frame


func _orbit_and_shot(name: String, yaw: float) -> void:
	if _rig != null:
		_rig.set_yaw(yaw)
	await _settle(20)
	await _shot(name)


## Aproxima a câmera para ver a pose de perto.
func _close_up(name: String) -> void:
	if _spring != null:
		_spring.spring_length = 2.6
	await _settle(30)
	await _shot(name)
	if _spring != null:
		_spring.spring_length = 4.5
	await _settle(20)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		print("  falhou: %s" % name)
		return
	var path := "%s/%s.png" % [_dir, name]
	image.save_png(path)
	_shots += 1
	print("  salvo: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
