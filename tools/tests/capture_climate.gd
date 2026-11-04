extends SceneTree
## Captura o distrito em varias horas do dia e climas, para inspecao visual.
##
## Uso: xvfb-run -a godot --path . --script res://tools/tests/capture_climate.gd

const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"

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
	var climate: WorldClimate = district.call("climate")
	climate.auto_advance = false
	climate.weather_enabled = false

	_camera = Camera3D.new()
	_camera.fov = 60.0
	root.add_child(_camera)
	_camera.make_current()
	var extent: float = CityLayout.district_extent(7)
	_camera.global_position = Vector3(0.0, 45.0, extent * 0.55)
	_camera.look_at(Vector3(0.0, 20.0, 0.0), Vector3.UP)

	var moments := [
		["manha", 0.30, WorldClimate.Weather.CLEAR],
		["meiodia", 0.50, WorldClimate.Weather.CLEAR],
		["tarde", 0.68, WorldClimate.Weather.OVERCAST],
		["noite", 0.92, WorldClimate.Weather.CLEAR],
		["chuva", 0.45, WorldClimate.Weather.RAIN],
	]
	for entry: Array in moments:
		climate.set_time_of_day(entry[1])
		climate.set_weather(entry[2])
		for _i in 90:
			await process_frame
		var image := root.get_texture().get_image()
		if image != null:
			image.save_png("%s/clima_%s.png" % [_dir, entry[0]])
			print("salvo clima_%s" % entry[0])
	quit(0)
