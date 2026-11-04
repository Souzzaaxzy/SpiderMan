class_name PlayerAnimationController
extends Node
## Locomoção com `AnimationTree` e `BlendSpace1D`, para transições fluidas.
##
## ## Por que AnimationTree, e não AnimationPlayer.play()
##
## A versão anterior trocava de clipe com `play(clip, blend_time)`. Isso funciona,
## mas produz **cortes secos**: cada troca de estado reinicia a pose e a mistura é
## um cruzamento simples entre dois clipes. O resultado é a sensação de "boneco
## rígido trocando de pose" em vez de corpo em movimento.
##
## Aqui a locomoção terrestre passa por um **BlendSpace1D** com os clipes
## ordenados por velocidade (parado → andar → trote → corrida). O parâmetro é a
## velocidade real do jogador, então a mistura entre clipes é contínua: correr
## devagar e correr rápido não são estados diferentes, são pontos diferentes do
## mesmo eixo.
##
## ## O que fica fora do BlendSpace
##
## Aéreo e teia são estados discretos (não interpolam com a velocidade), então
## usam `AnimationNodeStateMachine` com transições de 0,15 a 0,25 s. Assim:
##
## - chão → ar: transição curta no pulo;
## - ar → chão: transição um pouco maior na aterrissagem;
## - qualquer → teia: rápida, porque o jogador apertou o botão.
##
## Tudo é montado em código a partir dos clipes que existirem: se um clipe não
## estiver no modelo, ele simplesmente não entra no BlendSpace, sem quebrar.

@export_group("Referências")
@export var controller_path: NodePath = ^".."
@export var animation_player_path: NodePath = ^"../Visual/Model/AnimationPlayer"
@export var web_path: NodePath = ^"../WebSwing"

@export_group("Velocidades de referência")
@export var idle_threshold: float = 0.25
@export var jog_threshold: float = 5.0
@export var sprint_threshold: float = 9.5
## Velocidade máxima considerada pelo BlendSpace, em m/s.
@export var max_blend_speed: float = 12.0
@export var walk_speed_reference: float = 3.2
@export var run_speed_reference: float = 7.0

@export_group("Transições")
@export var fall_delay: float = 0.25
## Suavização do parâmetro do BlendSpace. Baixo = transição mais fluida.
@export var blend_smoothing: float = 6.0

var _controller: Node
var _player: AnimationPlayer
var _web: Node
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _machine: AnimationNodeStateMachine
var _available: Array[StringName] = []
var _current_state: String = ""
var _airborne_time: float = 0.0
var _speed_parameter: float = 0.0


func _ready() -> void:
	_controller = get_node_or_null(controller_path)
	_player = get_node_or_null(animation_player_path)
	_web = get_node_or_null(web_path)
	if _player == null:
		push_warning("PlayerAnimationController: AnimationPlayer nao encontrado em '%s'." % animation_player_path)
		return

	_available = PlayerAnimationLibrary.detect_available(_player)
	_configure_loops()
	_build_tree()
	_report_asset_status()


## O glTF não guarda informação de loop: o importador deixa tudo em "tocar uma
## vez". Os ciclos precisam repetir.
func _configure_loops() -> void:
	for clip: StringName in _available:
		var animation := _player.get_animation(clip)
		if clip == &"standing_jump" or clip == &"falling_to_landing" or clip == &"land_roll":
			animation.loop_mode = Animation.LOOP_NONE
		else:
			animation.loop_mode = Animation.LOOP_LINEAR


## Monta o AnimationTree inteiro em código.
##
## Feito em código, e não num recurso `.tres`, para o sistema se adaptar aos
## clipes que realmente existem: um clipe ausente é simplesmente ignorado.
func _build_tree() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	# O nó precisa estar na árvore antes de `get_path_to` resolver o caminho.
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)

	var root := AnimationNodeStateMachine.new()

	# --- Locomoção: um BlendSpace1D com o eixo na velocidade ---
	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = max_blend_speed
	# `resolve` recebe o **estado**, nao o clipe: "walk", nao "walking". Passar o
	# nome do clipe aqui fazia o ponto do meio ser silenciosamente descartado (o
	# blend ficava so com idle/jog/sprint) e o andar virava uma mistura instavel
	# entre idle e jog — o personagem "tremia" andando.
	_add_blend_point(locomotion, "idle", 0.0)
	_add_blend_point(locomotion, "walk", walk_speed_reference)
	_add_blend_point(locomotion, "jog", run_speed_reference)
	_add_blend_point(locomotion, "sprint", max_blend_speed)
	if locomotion.get_blend_point_count() == 0:
		push_warning("PlayerAnimationController: nenhum clipe de locomocao disponivel.")

	# --- Estados discretos ---
	var states := {
		"Locomotion": locomotion,
	}
	for state_name in ["jump_start", "jump_loop", "fall", "land", "land_roll",
			"swing_loop", "swing_start", "swing_release", "web_zip", "wall_run"]:
		var clip := PlayerAnimationLibrary.resolve(state_name, _available)
		if clip == &"":
			continue
		states[_state_key(state_name)] = _single_clip(clip)

	for key: String in states:
		root.add_node(key, states[key])

	var first_key: String = states.keys()[0]

	# --- Transições: curtas para resposta, maiores para peso ---
	for key: String in states:
		if key == first_key:
			continue
		root.add_transition(first_key, key, _transition(0.20))
		root.add_transition(key, first_key, _transition(0.20))
	for key: String in states:
		for other: String in states:
			if key == other or key == first_key or other == first_key:
				continue
			root.add_transition(key, other, _transition(0.15))

	_tree.tree_root = root
	_machine = root
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback != null:
		_playback.start(first_key)
	_tree.set("parameters/Locomotion/blend_position", 0.0)


func _add_blend_point(space: AnimationNodeBlendSpace1D, state_name: String, position: float) -> void:
	var clip := PlayerAnimationLibrary.resolve(state_name, _available)
	if clip == &"":
		return
	# Nome explícito: sem ele a Godot usa "índice seguro" como referência e avisa
	# que nomes vazios serão removidos — e a interpolação entre os pontos fica
	# instável, produzindo saltos de pose (medido: mão pulando 0,59 m por quadro).
	space.add_blend_point(_single_clip(clip), position, -1, String(clip))


func _single_clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node


func _transition(seconds: float) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = seconds
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
	return transition


func _state_key(state_name: String) -> String:
	return state_name.capitalize().replace(" ", "")


func _process(delta: float) -> void:
	if _controller == null or _player == null or _playback == null:
		return
	_update_airborne(delta)
	_update_blend(delta)
	var state := _resolve_state()
	if state != _current_state:
		_enter_state(state)


## Atualiza o parâmetro do BlendSpace com a velocidade real, suavizado.
func _update_blend(delta: float) -> void:
	var target: float = minf(_controller.current_speed(), max_blend_speed)
	_speed_parameter = lerpf(_speed_parameter, target, clampf(blend_smoothing * delta, 0.0, 1.0))
	_tree.set("parameters/Locomotion/blend_position", _speed_parameter)


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
	if _controller.is_grounded():
		_airborne_time = 0.0
	else:
		_airborne_time += delta


## Entra em um estado: pede a transição ao AnimationTree.
func _enter_state(state: String) -> void:
	_current_state = state
	# A locomoção é resolvida pelo BlendSpace, então o estado "viaja" para ele.
	if _state_key(state) in ["Idle", "Walk", "Jog", "Sprint"]:
		if _playback.get_current_node() != "Locomotion":
			_playback.travel("Locomotion")
		return
	var key := _state_key(state)
	if _machine != null and _machine.has_node(key):
		_playback.travel(key)


## --- Consulta (usada pelos testes e pelo IK) ---

func current_state() -> String:
	return _current_state


func current_clip() -> StringName:
	if _playback == null:
		return &""
	var node := _playback.get_current_node()
	return StringName(node)


func blend_position() -> float:
	return _speed_parameter


func available_clips() -> Array[StringName]:
	return _available


func missing_states() -> Array[String]:
	return PlayerAnimationLibrary.missing_states(_available)


func fallback_states() -> Array[String]:
	return PlayerAnimationLibrary.fallback_states(_available)


## Registra no console o que existe e o que falta.
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
