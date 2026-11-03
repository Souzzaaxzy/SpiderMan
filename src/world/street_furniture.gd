class_name StreetFurniture
extends Node3D
## Mobiliário urbano: postes de luz, semáforos, placas e hidrantes.
##
## Cada tipo de objeto é um MultiMesh. São poucos tipos e muitos exemplares, que
## é exatamente o caso em que o MultiMesh compensa. Nada de colisão: são detalhes
## decorativos e não devem custar física.

const POLE_COLOR := Color(0.22, 0.23, 0.26)
const LAMP_COLOR := Color(0.95, 0.9, 0.75)
const SIGN_COLOR := Color(0.14, 0.32, 0.2)
const HYDRANT_COLOR := Color(0.65, 0.16, 0.16)
const SIGNAL_COLOR := Color(0.15, 0.15, 0.17)

const POLE_HEIGHT := 7.0
const POLE_THICKNESS := 0.22

var _stats: Dictionary = {}


## Coloca o mobiliário ao longo das ruas, em intervalos regulares.
func build(blocks_per_side: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777001

	var lines := CityLayout.street_lines(blocks_per_side)
	var pole_positions: Array[Transform3D] = []
	var lamp_positions: Array[Transform3D] = []
	var signal_positions: Array[Transform3D] = []
	var sign_positions: Array[Transform3D] = []
	var hydrant_positions: Array[Transform3D] = []

	var spacing: float = 16.0
	for line: Dictionary in lines:
		var coordinate: float = line["coordinate"]
		var length: float = line["length"]
		var count := int(length / spacing)
		var start := -length * 0.5 + spacing * 0.5
		for index in count:
			var along: float = start + index * spacing
			# Poste na calçada, dos dois lados da rua.
			for side: float in [-1.0, 1.0]:
				var x: float = coordinate + side * (CityLayout.STREET_WIDTH * 0.5 + 1.0)
				var base := Vector3(x, CityLayout.CURB_HEIGHT, along)
				pole_positions.append(Transform3D(
					Basis().scaled(Vector3(POLE_THICKNESS, POLE_HEIGHT, POLE_THICKNESS)),
					base + Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)))
				# Braço e luminária apontando para a rua.
				lamp_positions.append(Transform3D(
					Basis().scaled(Vector3(1.4, 0.18, 0.5)),
					base + Vector3(-side * 0.7, POLE_HEIGHT - 0.2, 0.0)))
				if rng.randf() < 0.25:
					sign_positions.append(Transform3D(
						Basis().scaled(Vector3(0.06, 0.9, 0.7)),
						base + Vector3(0.0, POLE_HEIGHT - 1.6, 0.0)))
				if rng.randf() < 0.3:
					hydrant_positions.append(Transform3D(
						Basis().scaled(Vector3(0.4, 0.9, 0.4)),
						base + Vector3(-side * 1.6, CityLayout.CURB_HEIGHT + 0.45, 0.0)))

	# Semáforos nos cruzamentos.
	for line: Dictionary in lines:
		var coordinate: float = line["coordinate"]
		for other: Dictionary in lines:
			var cross: float = other["coordinate"]
			var corner_offset := CityLayout.BLOCK_SIZE * 0.5 + CityLayout.SIDEWALK_WIDTH
			for corner_x: float in [-1.0, 1.0]:
				var base := Vector3(
					cross + corner_x * corner_offset,
					CityLayout.CURB_HEIGHT,
					coordinate + corner_offset)
				signal_positions.append(Transform3D(
					Basis().scaled(Vector3(0.3, 5.2, 0.3)),
					base + Vector3(0.0, 2.6, 0.0)))

	_add_multimesh("LightPoles", _unit_box(), POLE_COLOR, pole_positions)
	_add_multimesh("Lamps", _unit_box(), LAMP_COLOR, lamp_positions)
	_add_multimesh("TrafficSignals", _unit_box(), SIGNAL_COLOR, signal_positions)
	_add_multimesh("StreetSigns", _unit_box(), SIGN_COLOR, sign_positions)
	_add_multimesh("Hydrants", _unit_box(), HYDRANT_COLOR, hydrant_positions)

	_stats["light_poles"] = pole_positions.size()
	_stats["lamps"] = lamp_positions.size()
	_stats["traffic_signals"] = signal_positions.size()
	_stats["street_signs"] = sign_positions.size()
	_stats["hydrants"] = hydrant_positions.size()
	return _stats


func _add_multimesh(node_name: String, mesh: Mesh, color: Color,
		transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _unit_box() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box
