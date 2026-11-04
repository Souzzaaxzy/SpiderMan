class_name PlayerAnimationLibrary
extends RefCounted
## Catálogo dos clipes de animação que o jogo espera, e onde cada um está.
##
## ## Situação atual
##
## O modelo traz **15 clipes** retargeted das animações do Mixamo
## (`tools/retarget_animations.py`). Nem todos os 22 estados da MISSÃO 005 têm
## clipe próprio: alguns continuam usando alternativa, e isso fica registrado.
##
## ## Estados sem clipe
##
## `idle`, `jump_loop`, `fall`, `air_move`, `web_shoot_*` e os de parede
## (`wall_climb`, `wall_jump`) não vieram no pacote. Cada um tem alternativa
## declarada em `FALLBACKS`, então **nenhum estado fica sem tocar nada** — mas o
## clipe não é o ideal, e o console registra isso.

## Estado do jogo → nome do clipe esperado.
const REQUIRED_CLIPS := {
	# Locomoção terrestre
	"idle": "idle",
	"walk": "walking",
	"jog": "jog",
	"sprint": "sprint",
	"start_run": "start_run",
	"turn": "turn",
	# Aérea
	"jump_start": "jump_loop",
	"land": "falling_to_landing",
	"land_roll": "land_roll",
	# Teias
	"swing_start": "swing_start",
	"swing_loop": "swing_loop",
	"swing_release": "swing_release",
	# Estruturas
	"wall_run": "wall_run",
	# Sem clipe no pacote recebido:
	"jump_loop": "jump_loop",
	"fall": "fall",
	"air_move": "air_move",
	"web_shoot_l": "web_shoot_l",
	"web_shoot_r": "web_shoot_r",
	"web_zip": "web_zip",
	"wall_climb": "wall_climb",
	"wall_jump": "wall_jump",
}

## Clipes que o pacote do Mixamo realmente trouxe (após o retargeting).
const AVAILABLE_CLIPS: Array[StringName] = [
	&"walking", &"jog", &"sprint", &"start_run", &"turn",
	&"standing_jump", &"falling_to_landing", &"land_roll",
	&"swing_start", &"swing_loop", &"swing_release", &"swing_to_land",
	&"swing_into_wall", &"wall_run", &"low_crawl",
	&"fall", &"jump_loop", &"air_move", &"wall_climb", &"wall_jump", &"web_zip",
]

## Alternativa usada quando o clipe ideal não existe.
const FALLBACKS := {
	"idle": "walking",
	"jump_loop": "jump_loop",
	"fall": "fall",
	"air_move": "air_move",
	"web_shoot_l": "swing_start",
	"web_shoot_r": "swing_start",
	"web_zip": "web_zip",
	"wall_climb": "wall_climb",
	"wall_jump": "wall_jump",
}

## Nomes alternativos que o importador da Godot pode usar para o mesmo clipe.
##
## O glTF traz `swing_loop`, mas o importador da Godot entrega `swing` — verificado
## no log do jogo. Em vez de depender do nome exato, o resolvedor aceita os dois.
const ALIASES := {
	"swing_loop": ["swing", "swinging"],
	# O importador da Godot entrega "jump" para o clipe "jump_loop".
	"jump_loop": ["jump"],
	"standing_jump": ["jump"],
	"walking": ["walk"],
	"falling_to_landing": ["landing", "fall_to_landing"],
}


## Lista os clipes realmente presentes no AnimationPlayer.
static func detect_available(player: AnimationPlayer) -> Array[StringName]:
	var found: Array[StringName] = []
	if player == null:
		return found
	for clip in player.get_animation_list():
		found.append(clip)
	return found


## Devolve o clipe a tocar para um estado, ou `&""` se não houver nem alternativa.
static func resolve(state: String, available: Array[StringName]) -> StringName:
	if REQUIRED_CLIPS.has(state):
		var wanted := StringName(REQUIRED_CLIPS[state])
		if available.has(wanted):
			return wanted
		# O importador pode ter entregue o clipe com outro nome.
		if ALIASES.has(wanted):
			for alias: String in ALIASES[wanted]:
				if available.has(StringName(alias)):
					return StringName(alias)
	if FALLBACKS.has(state):
		var fallback := StringName(FALLBACKS[state])
		if available.has(fallback):
			return fallback
	return &""


## Estados que ainda precisam de clipe próprio (nem direto, nem por alias).
static func missing_states(available: Array[StringName]) -> Array[String]:
	var missing: Array[String] = []
	for state: String in REQUIRED_CLIPS:
		var wanted := StringName(REQUIRED_CLIPS[state])
		if available.has(wanted):
			continue
		var found_alias := false
		if ALIASES.has(wanted):
			for alias: String in ALIASES[wanted]:
				if available.has(StringName(alias)):
					found_alias = true
					break
		if not found_alias:
			missing.append(state)
	return missing


## Estados que rodam com alternativa (funcionam, mas com o clipe errado).
static func fallback_states(available: Array[StringName]) -> Array[String]:
	var using_fallback: Array[String] = []
	for state: String in REQUIRED_CLIPS:
		var wanted := StringName(REQUIRED_CLIPS[state])
		if not available.has(wanted) and FALLBACKS.has(state):
			var fallback := StringName(FALLBACKS[state])
			if available.has(fallback):
				using_fallback.append(state)
	return using_fallback


## Estados sem clipe próprio e sem alternativa: não tocam nada.
static func unresolvable_states(available: Array[StringName]) -> Array[String]:
	var unresolvable: Array[String] = []
	for state: String in missing_states(available):
		if resolve(state, available) == &"":
			unresolvable.append(state)
	return unresolvable
