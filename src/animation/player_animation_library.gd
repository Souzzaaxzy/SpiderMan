class_name PlayerAnimationLibrary
extends RefCounted
## Catálogo dos clipes de animação que o jogo espera encontrar.
##
## ## Situação real dos assets
##
## O modelo importado traz **quatro** clipes, gerados por nós no Blender
## (`tools/build_animations.py`): `idle`, `walk`, `run`, `jump`. Não existe
## biblioteca humana completa no projeto.
##
## Esta classe declara **todos** os estados que o sistema de movimentação pede, e
## marca quais já têm clipe. Quando um clipe não existe, o estado é registrado
## como pendente e o sistema usa a melhor alternativa disponível — sem inventar
## que a animação foi integrada.
##
## ## Sobre o Mixamo
##
## A missão sugere o Mixamo como fonte. **Não foi possível baixar nada de lá
## neste ambiente**: o Mixamo exige login e não oferece download por URL direta.
## Os arquivos precisam ser baixados por uma pessoa autenticada e colocados em
## `assets/animations/mixamo/` para serem importados. O pipeline já está pronto
## para recebê-los (ver `docs/ANIMATIONS.md`).

## Estado → nome do clipe esperado.
const REQUIRED_CLIPS := {
	# Locomoção terrestre
	"idle": "idle",
	"walk": "walk",
	"jog": "jog",
	"sprint": "sprint",
	"start_run": "start_run",
	"stop_run": "stop_run",
	"turn": "turn",
	# Aérea
	"jump_start": "jump_start",
	"jump_loop": "jump_loop",
	"fall": "fall",
	"land": "land",
	"land_roll": "land_roll",
	"air_move": "air_move",
	# Teias
	"web_shoot_l": "web_shoot_l",
	"web_shoot_r": "web_shoot_r",
	"swing_start": "swing_start",
	"swing_loop": "swing_loop",
	"swing_release": "swing_release",
	"web_zip": "web_zip",
	# Estruturas
	"wall_run": "wall_run",
	"wall_climb": "wall_climb",
	"wall_jump": "wall_jump",
}

## Clipes que o projeto realmente tem hoje (assados no .glb).
const AVAILABLE_CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"jump"]

## Alternativa usada quando o clipe ideal não existe.
## Chave = estado pedido; valor = estado realmente usado.
const FALLBACKS := {
	"jog": "run",
	"sprint": "run",
	"start_run": "walk",
	"stop_run": "walk",
	"turn": "walk",
	"jump_start": "jump",
	"jump_loop": "jump",
	"fall": "jump",
	"land": "jump",
	"land_roll": "jump",
	"air_move": "jump",
	"web_shoot_l": "idle",
	"web_shoot_r": "idle",
	"swing_start": "jump",
	"swing_loop": "jump",
	"swing_release": "jump",
	"web_zip": "jump",
	"wall_run": "run",
	"wall_climb": "walk",
	"wall_jump": "jump",
}


## Lista os clipes realmente presentes no AnimationPlayer dado.
static func detect_available(player: AnimationPlayer) -> Array[StringName]:
	var found: Array[StringName] = []
	if player == null:
		return found
	for clip in player.get_animation_list():
		found.append(clip)
	return found


## Devolve o clipe que deve ser tocado para um estado, ou `&""` se não houver
## nem o ideal nem alternativa.
static func resolve(state: String, available: Array[StringName]) -> StringName:
	if REQUIRED_CLIPS.has(state):
		var wanted := StringName(REQUIRED_CLIPS[state])
		if available.has(wanted):
			return wanted
	if FALLBACKS.has(state):
		var fallback := StringName(FALLBACKS[state])
		if available.has(fallback):
			return fallback
	return &""


## Estados que ainda precisam de clipe próprio. Serve para o relatório dizer
## exatamente o que falta, em vez de dar a animação por integrada.
static func missing_states(available: Array[StringName]) -> Array[String]:
	var missing: Array[String] = []
	for state: String in REQUIRED_CLIPS:
		var wanted := StringName(REQUIRED_CLIPS[state])
		if not available.has(wanted):
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
