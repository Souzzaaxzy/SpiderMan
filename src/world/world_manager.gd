class_name WorldManager
extends Node3D
## Gerencia o distrito: ambiente, luz e organização espacial.
##
## A cena `manhattan_district.tscn` é o ponto de entrada; este script cuida do
## ambiente e mantém o distrito organizado em um nó próprio, para permitir trocar
## ou recarregar a região sem mexer no resto da cena.

## Quarteirões por lado do primeiro distrito.
@export var blocks_per_side: int = 5
@export var layout_seed: int = 20261103

var _city: CityGenerator
var _sun: DirectionalLight3D


func _ready() -> void:
	_setup_environment()
	_setup_sun()
	_build_city()


## Ambiente urbano: céu limpo de fim de tarde, névoa leve para dar profundidade
## sem custo. Sem ciclo de dia/noite ainda — só a base para recebê-lo depois.
func _setup_environment() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.42, 0.68)
	sky_material.sky_horizon_color = Color(0.62, 0.66, 0.72)
	sky_material.ground_bottom_color = Color(0.16, 0.16, 0.18)
	sky_material.ground_horizon_color = Color(0.42, 0.42, 0.44)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	# Névoa: esconde o limite do distrito e dá leitura de distância, o que ajuda
	# bastante o desempenho em aparelho modesto.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.62, 0.66, 0.72)
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.4

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


## Luz solar com sombras dimensionadas para Mobile: alcance curto e resolução
## baixa. Sombras longas e nítidas custariam caro no Galaxy A14.
func _setup_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	_sun.light_energy = 1.15
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# Só as sombras próximas do jogador são desenhadas.
	_sun.directional_shadow_max_distance = 90.0
	_sun.shadow_bias = 0.08
	_sun.shadow_normal_bias = 1.5
	add_child(_sun)


func _build_city() -> void:
	_city = CityGenerator.new()
	_city.name = "District"
	_city.blocks_per_side = blocks_per_side
	_city.layout_seed = layout_seed
	add_child(_city)
	var stats: Dictionary = _city.statistics()
	print("[world] Distrito gerado: %d quarteiroes, %d predios, extensao %.0f m, altura maxima %.0f m." % [
		stats.get("blocks", 0), stats.get("buildings", 0),
		stats.get("district_extent", 0.0), stats.get("max_building_height", 0.0)])


func city() -> CityGenerator:
	return _city


func spawn_position() -> Vector3:
	return _city.spawn_position() if _city != null else Vector3.ZERO
