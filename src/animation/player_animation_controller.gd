class_name PlayerAnimationController
extends Node
## Máquina de estados de animação, dirigida pelo estado físico do jogador.
##
## ## O que mudou
##
## Antes havia só um `AnimationPlayer` tocando um de quatro clipes, escolhidos
## pela velocidade. Não existia estado, nem transição, nem reação ao que o corpo
## está fazendo no ar. Era a causa da rigidez relatada.
##
## Agora existe um **estado explícito** (`PlayerState`) que decide:
## - qual clipe tocar (com alternativa, quando o ideal não existe);
## - a que velocidade reproduzir, sincronizado com o deslocamento real;
## - quando fazer transição e com quanto de mistura.
##
## ## Honestidade sobre os assets
##
## O projeto tem **quatro** clipes. Os outros dezenove estados da missão rodam em
## alternativa (ver `AnimationLibrary`). Nada aqui finge que um clipe existe: os
## estados pendentes ficam registrados e visíveis no relatório.

@export_group("Referências")
@export var controller_path: NodePath = ^".."
@export var animation_player_path: NodePath = ^"../Visual/Model/AnimationPlayer"
@export var web_path: NodePath = ^"../WebSwing"

@export_group("Velocidades de referência")
## Velocidade em que a caminhada atinge a reprodução normal.
@export var walk_speed_reference: float = 3.2
## Velocidade em que a corrida atinge a reprodução normal.
@export var run_speed_reference: float = 7.0
## Acima desta velocidade o estado é sprint.
@export var sprint_threshold: float = 9.5
## Abaixo desta velocidade o estado é idle.
@export var idle_threshold: float = 0.25
## Acima desta velocidade o estado é jog (trote).
@export var jog_threshold: float = 5.0

@export_group("Transição")
## Duração da mistura entre estados, em segundos.
@export var blend_time: float = 0.18
## Quanto tempo no ar antes de considerar queda (evita piscar no pulo).
@export var fall_delay: float = 0.25

var _controller: Node
var _player: AnimationPlayer
var _web: Node
var _available: Array[StringName] = []
var _current_state: String = ""
var _current_clip: StringName = &""
var _airborne_time: float = 0.0
var _last_grounded: bool = true


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_player = get_node_or_null(animation_player_path)
	_web = get_node_or_null(web_path)

	if _player == null:
		push_warning("PlayerAnimationController: AnimationPlayer nao encontrado em '%s'." % animation_player_path)
		return

	_available = PlayerAnimationLibrary.detect_available(_player)
	_configure_loops()
	_report_asset_status()


## O glTF não guarda informação de loop: o importador deixa tudo em "tocar uma
## vez". Os ciclos precisam repetir.
func _configure_loops() -> void:
	for clip: StringName in _available:
		if clip == &"jump":
			_player.get_animation(clip).loop_mode = Animation.LOOP_NONE
		else:
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## Registra no console o que existe e o que falta, para o relatório ser honesto.
func _report_asset_status() -> void:
	var without_own: Array[String] = PlayerAnimationLibrary.missing_states(_available)
	var using_fallback: Array[String] = PlayerAnimationLibrary.fallback_states(_available)
	var with_own: int = PlayerAnimationLibrary.REQUIRED_CLIPS.size() - without_own.size()

	print("[anim] clipes disponiveis: %s" % [_available])
	print("[anim] estados com clipe proprio: %d de %d" % [
		with_own, PlayerAnimationLibrary.REQUIRED_CLIPS.size()])
	if not using_fallback.is_empty():
		print("[anim] %d estados rodando em clipe alternativo: %s" % [
			using_fallback.size(), using_fallback])
	var truly_missing: Array[String] = []
	for state: String in without_own:
		if not using_fallback.has(state):
			truly_missing.append(state)
	if truly_missing.is_empty():
		print("[anim] nenhum estado ficou sem animacao (todos usam alternativa).")
	else:
		print("[anim] SEM clipe e SEM alternativa (%d): %s" % [
			truly_missing.size(), truly_missing])


func _process(delta: float) -> void:
	if _controller == null or _player == null:
		return
	_update_airborne(delta)
	var state := _resolve_state()
	if state != _current_state:
		_enter_state(state)


## Decide o estado a partir do que o corpo está fazendo.
func _resolve_state() -> String:
	# A teia tem prioridade: é o que o jogador está fazendo agora.
	if _web != null:
		if _web.is_zipping():
			return "web_zip"
		if _web.is_swinging():
			return "swing_loop"

	if not _controller.is_grounded():
		if _airborne_time < fall_delay:
			return "jump_start"
		# Subindo ou caindo?
		if _controller.velocity.y > 0.5:
			return "jump_loop"
		return "fall"

	var speed: float = _controller.current_speed()
	if speed < idle_threshold:
		return "idle"
	if speed < jog_threshold:
		return "walk"
	if speed < sprint_threshold:
		return "jog"
	return "sprint"


func _update_airborne(delta: float) -> void:
	var grounded: bool = _controller.is_grounded()
	if grounded:
		_airborne_time = 0.0
	else:
		_airborne_time += delta
	_last_grounded = grounded


## Entra em um estado: escolhe o clipe e faz a transição.
func _enter_state(state: String) -> void:
	_current_state = state
	var clip := PlayerAnimationLibrary.resolve(state, _available)
	if clip == &"":
		return

	if clip != _current_clip:
		_current_clip = clip
		if _player.current_animation != clip:
			_player.play(clip, blend_time)
	_current_clip = clip

	_player.speed_scale = _speed_scale_for(state)


## Sincroniza a reprodução com o deslocamento, para o pé não patinar.
func _speed_scale_for(state: String) -> float:
	match state:
		"walk":
			return clampf(_controller.current_speed() / walk_speed_reference, 0.55, 1.6)
		"jog":
			return clampf(_controller.current_speed() / run_speed_reference, 0.7, 1.5)
		"sprint":
			return clampf(_controller.current_speed() / run_speed_reference, 0.9, 1.8)
		_:
			return 1.0


## --- Consulta (usada pelos testes e pelo IK) ---

func current_state() -> String:
	return _current_state


func current_clip() -> StringName:
	return _current_clip


func available_clips() -> Array[StringName]:
	return _available


func missing_states() -> Array[String]:
	return PlayerAnimationLibrary.missing_states(_available)


func fallback_states() -> Array[String]:
	return PlayerAnimationLibrary.fallback_states(_available)
