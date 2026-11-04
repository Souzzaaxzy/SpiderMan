class_name WorldClimate
extends Node
## Ciclo de dia/noite e clima do distrito.
##
## ## O que faz
##
## - **Dia/noite**: gira o sol num arco leste-oeste, escurece o céu, a luz, o
##   ambiente e a névoa conforme a hora.
## - **Clima**: alterna entre **limpo**, **nublado** e **chuva**, com transição
##   suave. O clima muda a cor do céu, a densidade da névoa e a força do sol.
##
## ## Por que aqui, e não no `WorldManager`
##
## O `WorldManager` monta a cena uma vez; o clima muda **todo quadro**. Separar
## deixa claro o que é construção e o que é animação do ambiente, e permite ao
## teste medir o ciclo sem regerar a cidade.
##
## ## Custo
##
## Tudo é atualização de uniformes (rotação de luz e cores), não geometria. O
## céu é procedural, então não há textura para trocar. Seguro para Mobile.

enum Weather { CLEAR, OVERCAST, RAIN }

## Duração de um ciclo completo, em segundos. 4 min = dia e noite curtos o
## bastante para o jogador ver os dois numa sessão.
@export var day_length_seconds: float = 240.0
## Hora inicial, de 0 a 1 (0 = meia-noite, 0.25 = amanhecer, 0.5 = meio-dia).
@export var start_time: float = 0.30
## Avança o tempo sozinho. Desligado, a hora fica parada (útil no teste).
@export var auto_advance: bool = true
## Liga a troca automática de clima.
@export var weather_enabled: bool = true
## Intervalo entre mudanças de clima, em segundos.
@export var weather_interval: float = 45.0
## Velocidade da transição de clima (quanto maior, mais rápido).
@export var weather_blend_speed: float = 0.5

var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _time: float = 0.30
var _weather: int = Weather.CLEAR
var _weather_from: int = Weather.CLEAR
var _weather_to: int = Weather.CLEAR
var _weather_blend: float = 1.0
var _weather_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

## Paletas do céu por momento do dia: topo, horizonte, chão, energia do ambiente
## e cor da névoa.
const SKY_NIGHT := {
        "top": Color(0.02, 0.03, 0.09), "horizon": Color(0.05, 0.07, 0.16),
        "ground": Color(0.02, 0.02, 0.04), "ambient": 0.22, "fog": Color(0.05, 0.07, 0.15),
}
const SKY_DAWN := {
        "top": Color(0.20, 0.26, 0.48), "horizon": Color(0.85, 0.52, 0.32),
        "ground": Color(0.16, 0.14, 0.14), "ambient": 0.55, "fog": Color(0.70, 0.50, 0.42),
}
const SKY_DAY := {
        "top": Color(0.28, 0.46, 0.78), "horizon": Color(0.62, 0.72, 0.85),
        "ground": Color(0.16, 0.16, 0.18), "ambient": 0.95, "fog": Color(0.66, 0.72, 0.82),
}
const SKY_DUSK := {
        "top": Color(0.18, 0.16, 0.36), "horizon": Color(0.92, 0.46, 0.24),
        "ground": Color(0.14, 0.10, 0.10), "ambient": 0.48, "fog": Color(0.62, 0.40, 0.34),
}


func setup(sun: DirectionalLight3D, environment: Environment) -> void:
        _sun = sun
        _environment = environment
        if _environment != null and _environment.sky != null:
                _sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
        _rng.seed = 20261104
        _time = start_time
        _weather = Weather.CLEAR
        _weather_from = Weather.CLEAR
        _weather_to = Weather.CLEAR
        _weather_blend = 1.0
        _weather_timer = 0.0
        _apply()


func _process(delta: float) -> void:
        if auto_advance and day_length_seconds > 0.0:
                _time = fposmod(_time + delta / day_length_seconds, 1.0)
        _update_weather(delta)
        _apply()


## Avança a hora direto (usado pelo teste e por um controle de debug).
func set_time_of_day(value: float) -> void:
        _time = fposmod(value, 1.0)
        _apply()


func time_of_day() -> float:
        return _time


func is_night() -> bool:
        return _sun_elevation() < 0.02


func weather_name() -> String:
        match _weather:
                Weather.OVERCAST:
                        return "nublado"
                Weather.RAIN:
                        return "chuva"
                _:
                        return "limpo"


## Escolhe um novo clima, evitando repetir o atual.
func set_weather(value: int) -> void:
        if value == _weather_to:
                return
        _weather_from = _weather
        _weather_to = value
        _weather = value
        _weather_blend = 0.0
        _weather_timer = 0.0


func _update_weather(delta: float) -> void:
        if _weather_blend < 1.0:
                _weather_blend = minf(_weather_blend + weather_blend_speed * delta, 1.0)
        if not weather_enabled:
                return
        _weather_timer += delta
        if _weather_timer >= weather_interval:
                _weather_timer = 0.0
                var options: Array[int] = [Weather.CLEAR, Weather.CLEAR, Weather.OVERCAST, Weather.RAIN]
                set_weather(options[_rng.randi() % options.size()])


## Elevação do sol: -1 (meia-noite) a +1 (meio-dia).
func _sun_elevation() -> float:
        return sin((_time - 0.25) * TAU)


## Mistura as paletas do céu conforme a hora.
func _sky_palette() -> Dictionary:
        var t := _time
        if t < 0.20:
                return SKY_NIGHT
        elif t < 0.30:
                return _lerp_palette(SKY_NIGHT, SKY_DAWN, (t - 0.20) / 0.10)
        elif t < 0.36:
                return _lerp_palette(SKY_DAWN, SKY_DAY, (t - 0.30) / 0.06)
        elif t < 0.64:
                return SKY_DAY
        elif t < 0.72:
                return _lerp_palette(SKY_DAY, SKY_DUSK, (t - 0.64) / 0.08)
        elif t < 0.80:
                return _lerp_palette(SKY_DUSK, SKY_NIGHT, (t - 0.72) / 0.08)
        return SKY_NIGHT


func _lerp_palette(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
        var w := clampf(weight, 0.0, 1.0)
        return {
                "top": (a["top"] as Color).lerp(b["top"], w),
                "horizon": (a["horizon"] as Color).lerp(b["horizon"], w),
                "ground": (a["ground"] as Color).lerp(b["ground"], w),
                "ambient": lerpf(a["ambient"], b["ambient"], w),
                "fog": (a["fog"] as Color).lerp(b["fog"], w),
        }


## Fatores do clima aplicados por cima da paleta do dia.
func _weather_factors() -> Dictionary:
        var from := _weather_profile(_weather_from)
        var to := _weather_profile(_weather_to)
        var w := clampf(_weather_blend, 0.0, 1.0)
        return {
                "desaturate": lerpf(from["desaturate"], to["desaturate"], w),
                "fog": lerpf(from["fog"], to["fog"], w),
                "sun": lerpf(from["sun"], to["sun"], w),
        }


func _weather_profile(kind: int) -> Dictionary:
        match kind:
                Weather.OVERCAST:
                        return {"desaturate": 0.55, "fog": 2.4, "sun": 0.45}
                Weather.RAIN:
                        return {"desaturate": 0.75, "fog": 4.0, "sun": 0.22}
                _:
                        return {"desaturate": 0.0, "fog": 1.0, "sun": 1.0}


func _apply() -> void:
        if _sun == null:
                return
        var solar := (_time - 0.25) * TAU
        var elevation := _sun_elevation()
        var day := clampf(elevation, 0.0, 1.0)
        var palette := _sky_palette()
        var weather := _weather_factors()

        # --- Sol: arco leste-oeste, energia e cor ---
        _sun.rotation_degrees = Vector3(-maxf(elevation, 0.04) * 88.0, -cos(solar) * 100.0, 0.0)
        _sun.visible = elevation > -0.08
        var warm := clampf(1.0 - elevation * 2.2, 0.0, 1.0)
        _sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.62, 0.36), warm)
        _sun.light_energy = (0.12 + day * 1.15) * float(weather["sun"])

        # --- Céu, ambiente e névoa ---
        var desat := float(weather["desaturate"])
        var top := _desaturate(palette["top"], desat)
        var horizon := _desaturate(palette["horizon"], desat)
        var ground := _desaturate(palette["ground"], desat)
        var fog_color := _desaturate(palette["fog"], desat)
        if _sky_material != null:
                _sky_material.sky_top_color = top
                _sky_material.sky_horizon_color = horizon
                _sky_material.ground_bottom_color = ground
                _sky_material.ground_horizon_color = horizon.lerp(ground, 0.5)
        if _environment != null:
                _environment.ambient_light_energy = float(palette["ambient"]) * lerpf(1.0, 0.7, desat)
                _environment.fog_light_color = fog_color
                _environment.fog_density = 0.0035 * float(weather["fog"])


## Reduz a saturação de uma cor (0 = original, 1 = cinza).
func _desaturate(color: Color, amount: float) -> Color:
        if amount <= 0.0:
                return color
        var gray := color.get_luminance()
        return color.lerp(Color(gray, gray, gray), amount)
