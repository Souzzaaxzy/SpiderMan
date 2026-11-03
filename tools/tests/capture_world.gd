extends SceneTree
## Vistas do mundo para inspeção visual: rua, parque, quarteirão de torres.
##
## Uso: xvfb-run -a godot --path . --script res://tools/tests/capture_world.gd

const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"
const OUTPUT_DIR := "res://../shots"

var _camera: Camera3D
var _dir: String


func _initialize() -> void:
	_run()


func _run() -> void:
	_dir = ProjectSettings.globalize_path("res://") + "../shots"
	DirAccess.make_dir_recursive_absolute(_dir)

	var district := (load(DISTRICT_SCENE) as PackedScene).instantiate()
	root.add_child(district)
	await process_frame
	await process_frame
	var city: CityGenerator = district.call("city")
	var extent: float = CityLayout.district_extent(5)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	root.add_child(_camera)
	_camera.make_current()

	# Rua central, ao nível do chão: mostra a largura e os prédios dos dois lados.
	await _view("w1_rua", Vector3(0.0, 3.0, extent * 0.35), Vector3(0.0, 8.0, 0.0))
	# Parque: uma das áreas verdes.
	var parks := CityLayout.parks(5)
	if not parks.is_empty():
		var park: Vector3 = parks[0]
		await _view("w2_parque", park + Vector3(0.0, 22.0, 46.0), park + Vector3(0.0, 2.0, 0.0))
		await _view("w3_parque_perto", park + Vector3(6.0, 6.0, 22.0), park + Vector3(0.0, 3.0, 0.0))
	# Miolo, visto do alto: os arranha-céus.
	await _view("w4_centro_alto", Vector3(0.0, 90.0, 120.0), Vector3(0.0, 40.0, 0.0))
	# Vista rasante, como quem balança entre prédios.
	await _view("w5_rasante", Vector3(-60.0, 45.0, 90.0), Vector3(20.0, 30.0, -40.0))

	print("vistas salvas em %s" % _dir)
	quit(0)


func _view(name: String, from: Vector3, to: Vector3) -> void:
	_camera.global_position = from
	_camera.look_at(to, Vector3.UP)
	await process_frame
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image == null:
		print("  falhou: %s" % name)
		return
	image.save_png("%s/%s.png" % [_dir, name])
	print("  salvo: %s.png" % name)
