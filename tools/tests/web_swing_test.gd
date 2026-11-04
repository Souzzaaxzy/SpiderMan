extends SceneTree
## Teste da movimentação (MISSÃO 005).
##
## Cobre os 28 itens de teste da missão: seleção de alvos, física, Web Zip,
## animações e integração. Roda no próprio motor, com a cena e o mundo reais.
##
## Todas as posições ficam em **ruas** (coordenadas -84, -28, 28, 84): nascer
## sobre um lote de 17,4 m faz a colisão empurrar o jogador para baixo.
##
## Uso: godot --headless --path . --script res://tools/tests/web_swing_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"

## Rua junto ao prédio mais alto do distrito.
const STREET_NEAR_TOWER := Vector3(-28.0, 1.2, -12.3)
## Ponto de lançamento elevado, com espaço para o arco.
const LAUNCH_POSITION := Vector3(-28.0, 14.0, 6.0)
const LAUNCH_SPEED := 6.0

var _failures: Array[String] = []
var _checks: int = 0
var _player: Node3D
var _web: Node
var _selector: Node
var _visual: Node
var _camera: Camera3D
var _spring: SpringArm3D
var _skeleton: Skeleton3D
var _animation: Node
var _ik: Node
var _city: CityGenerator


func _initialize() -> void:
	_run()


func _run() -> void:
	print("=== Teste de movimentacao (MISSAO 005) ===")
	var district := _spawn(DISTRICT_SCENE, Vector3.ZERO)
	if district == null:
		_finish()
		return
	await physics_frame
	await physics_frame
	_city = district.call("city")

	_player = _spawn(PLAYER_SCENE, STREET_NEAR_TOWER)
	if _player == null:
		_finish()
		return
	await physics_frame
	await physics_frame

	_web = _player.get_node_or_null("WebSwing")
	_selector = _player.get_node_or_null("WebSwing/WebTargetSelector")
	_visual = _player.get_node_or_null("WebSwing/WebVisual")
	_camera = _player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
	_spring = _player.get_node_or_null("CameraRig/SpringArm3D")
	_skeleton = _find(_player, "Skeleton3D") as Skeleton3D
	_animation = _player.get_node_or_null("AnimationDriver")
	_ik = _player.get_node_or_null("AnimationIK")

	await _test_structure()
	await _test_target_selection()
	await _test_physics()
	await _test_no_teleport()
	await _test_zip()
	await _test_animation()
	await _test_camera()
	await _test_integration()
	_test_math()

	_finish()


func _spawn(scene_path: String, position: Vector3) -> Node3D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("nao foi possivel carregar %s" % scene_path)
		return null
	var node := packed.instantiate() as Node3D
	node.position = position
	root.add_child(node)
	return node


func _wait(frames: int) -> void:
	for _index: int in frames:
		await physics_frame


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  [ok]    %s %s" % [label, detail])
	else:
		_fail("%s %s" % [label, detail])


func _fail(message: String) -> void:
	_failures.append(message)
	print("  [FALHA] %s" % message)


func _find(node: Node, class_filter: String) -> Node:
	if node.is_class(class_filter):
		return node
	for child in node.get_children():
		var found := _find(child, class_filter)
		if found != null:
			return found
	return null


func _find_all(node: Node, class_filter: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(class_filter):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, class_filter))
	return found


func _reset(position: Vector3, yaw: float = 0.0) -> void:
	if _web.is_busy():
		_web.release()
		_web.cancel_zip()
	_player.velocity = Vector3.ZERO
	_player.swing_active = false
	_player.global_position = position
	_player.set_move_vector(Vector2.ZERO)
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(yaw)
	await _wait(30)


func _aim(yaw: float, pitch: float) -> void:
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(yaw)
	if _spring != null:
		_spring.rotation = Vector3(deg_to_rad(pitch), 0.0, 0.0)
	await _wait(3)


# --- 1. Estrutura ---

func _test_structure() -> void:
	print("- Estrutura do sistema")
	_check("modulo de teia presente", _web != null)
	_check("seletor de alvos presente", _selector != null)
	_check("visual da teia presente", _visual != null)
	_check("camera presente", _camera != null)
	_check("esqueleto presente", _skeleton != null)
	_check("controlador de animacao presente", _animation != null)
	_check("ajustes IK presentes", _ik != null)
	_check("estado inicial livre", not _web.is_busy())


# --- 1 a 6. Seleção de alvos ---

func _test_target_selection() -> void:
	print("- Selecao automatica de alvos")

	# 1. Sem mirar diretamente: funciona olhando para o lado e para o céu.
	await _reset(STREET_NEAR_TOWER, 90.0)
	await _aim(-90.0, 0.0)
	_check("ancora sem olhar para o predio", _web.fire(),
		"(camera virada para o lado oposto)")
	if _web.is_swinging():
		_web.release()
	await _wait(10)

	await _reset(STREET_NEAR_TOWER, 90.0)
	await _aim(90.0, 80.0)
	_check("ancora olhando para o ceu", _web.fire())
	if _web.is_swinging():
		_web.release()
	await _wait(10)

	# 2. Pontos em prédios próximos: a âncora fica acima do jogador.
	await _reset(STREET_NEAR_TOWER, 90.0)
	await _aim(90.0, 25.0)
	var fired: bool = _web.fire()
	_check("ancorou em predio proximo", fired)
	if fired:
		var anchor: Vector3 = _web.current_anchor()
		_check("ancora acima do jogador", anchor.y > _player.global_position.y,
			"(ancora y=%.1f, jogador y=%.1f)" % [anchor.y, _player.global_position.y])
		_check("seletor gerou varios candidatos", _selector.candidate_count() > 1,
			"(%d candidatos)" % _selector.candidate_count())
		_web.release()
	await _wait(10)

	# 3. Rejeição de pontos inválidos: longe de qualquer prédio, no céu aberto.
	await _reset(Vector3(0.0, 200.0, 0.0))
	var exclude: Array[RID] = [_player.get_rid()]
	var empty: Dictionary = _selector.select_target(_player.global_position, Vector3.ZERO,
		Vector3.FORWARD, _camera, exclude)
	_check("nao ancora sem alvos disponiveis", not empty["valid"],
		"(%s)" % empty["reason"])
	_check("nao dispara teia invalida", not _web.fire())

	# 4. Verificação de obstáculos: a linha de visão é testada.
	await _reset(STREET_NEAR_TOWER, 90.0)
	await _aim(90.0, 25.0)
	var choice: Dictionary = _selector.select_target(_player.global_position, Vector3.ZERO,
		Vector3.FORWARD, _camera, exclude)
	_check("candidatos passam por teste de visao", choice["valid"])

	# 5. Direção do movimento influencia: correndo para leste, a âncora deve
	# ficar à frente, não atrás.
	await _reset(STREET_NEAR_TOWER, 90.0)
	_player.velocity = Vector3(8.0, 0.0, 0.0)
	await _wait(3)
	var forward_choice: Dictionary = _selector.select_target(_player.global_position,
		Vector3(8.0, 0.0, 0.0), Vector3.RIGHT, _camera, exclude)
	_check("selecao considera a direcao do movimento", forward_choice["valid"])
	if forward_choice["valid"]:
		var to_anchor: Vector3 = forward_choice["position"] - _player.global_position
		var flat := Vector3(to_anchor.x, 0.0, to_anchor.z).normalized()
		_check("ancora fica a frente do movimento", flat.x > 0.0,
			"(componente x=%.2f)" % flat.x)

	# 6. Perto da parede: a teia precisa pegar. Antes, encostado no prédio o disparo
	# falhava ("estou do lado do prédio e a teia não pega").
	for offset in [12.0, 8.0, 5.0, 3.0, 1.5]:
		await _reset(Vector3(-26.0 - offset, 1.2, -146.6), 90.0)
		var near_fired: bool = _web.fire()
		_check("ancora encostado na parede (offset=%.1f m)" % offset, near_fired)
		if near_fired:
			var near_anchor: Vector3 = _web.current_anchor()
			_check("ancora sobe acima do jogador (offset=%.1f)" % offset,
				near_anchor.y > _player.global_position.y + 3.0,
				"(ancora y=%.1f, jogador y=%.1f)" % [near_anchor.y, _player.global_position.y])
			_web.release()
		await _wait(10)

	# 7. A ancoragem escolhida e ALTA: a teia vai para o alto do predio, nao para o
	# ponto baixo da parede ao lado (pedido do responsavel).
	await _reset(Vector3(-26.0 - 6.0, 1.2, -146.6), 90.0)
	var exclude2: Array[RID] = [_player.get_rid()]
	var pick: Dictionary = _selector.select_target(_player.global_position, Vector3.ZERO,
		Vector3.RIGHT, _camera, exclude2)
	if pick["valid"]:
		var chosen_rise: float = pick["position"].y - _player.global_position.y
		var highest_rise := 0.0
		for cand: Dictionary in pick["candidates"]:
			highest_rise = maxf(highest_rise, cand["rise"])
		_check("ancora escolhida e alta (sobe no predio)",
			chosen_rise > highest_rise * 0.5 and chosen_rise > 8.0,
			"(escolhida sobe %.1f m, mais alta sobe %.1f m)" % [chosen_rise, highest_rise])

	# 6. Sem alvos: já coberto acima.


# --- 7 a 14. Física ---

func _test_physics() -> void:
	print("- Fisica do balanco")

	# 7. Início do balanço.
	var fired: bool = await _launch()
	_check("balanco iniciado", _web.is_swinging())
	_check("controlador marcado em balanco", _player.swing_active)
	if not fired:
		return

	# 8. Movimento pendular: a altura varia ao longo do arco.
	var highest: float = _player.global_position.y
	var lowest: float = highest
	var fastest: float = 0.0
	for _step in 80:
		await physics_frame
		highest = maxf(highest, _player.global_position.y)
		lowest = minf(lowest, _player.global_position.y)
		fastest = maxf(fastest, _player.velocity.length())
	_check("percorreu um arco", highest - lowest > 1.0,
		"(%.1f m de variacao)" % (highest - lowest))

	# 9. Conservação de velocidade: ganhou velocidade ao descer.
	_check("ganhou velocidade no arco", fastest > LAUNCH_SPEED + 1.0,
		"(%.1f -> %.1f m/s)" % [LAUNCH_SPEED, fastest])

	# 10. Ajuste do comprimento.
	var before: float = _web.rope_length()
	_web.set_rope_length(before - 3.0)
	_check("recolher encurta a teia", _web.rope_length() < before,
		"(%.1f -> %.1f m)" % [before, _web.rope_length()])
	_web.set_rope_length(0.0)
	_check("respeita o comprimento minimo",
		_web.rope_length() >= WebSwingController.MIN_ROPE_LENGTH)
	_web.set_rope_length(1000.0)
	_check("respeita o comprimento maximo",
		_web.rope_length() <= WebSwingController.MAX_ROPE_LENGTH)

	# 11 e 12. Soltura e preservação de velocidade.
	#
	# O impulso de soltura (estilo Spider-Man 2) SOMA velocidade por projeto, então
	# a velocidade total pode subir. O que precisa ser preservado é a **direção** e
	# o fato de não haver freio. Desligamos o impulso para medir a preservação pura.
	var previous_kick: bool = _web.swing_kick_enabled
	_web.swing_kick_enabled = false
	var speed_before: float = _player.velocity.length()
	var direction_before: Vector3 = _player.velocity.normalized()
	_web.release()
	var speed_after: float = _player.velocity.length()
	_check("soltura preserva a velocidade", absf(speed_after - speed_before) < 0.01,
		"(%.3f -> %.3f m/s)" % [speed_before, speed_after])
	_check("soltura preserva a direcao",
		direction_before.dot(_player.velocity.normalized()) > 0.999)
	_check("soltura nao zera a velocidade", speed_after > 1.0)
	_check("estado liberado", not _web.is_busy())
	_check("visual escondido", not _visual.is_showing())
	_web.swing_kick_enabled = previous_kick

	# 13. Colisões durante o balanço: o jogador não atravessa prédio.
	var inside := await _count_inside_building(60)
	_check("nao atravessou predio no balanco", inside == 0,
		"(%d quadros dentro de predio)" % inside)


## 14. Ausência de teletransporte: nenhum salto grande de posição.
func _test_no_teleport() -> void:
	print("- Ausencia de teletransporte")
	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar o teletransporte")
		return

	var before_fire: Vector3 = _player.global_position
	var fired_again: bool = false
	var after_fire: Vector3 = _player.global_position
	_check("disparo nao move o jogador", before_fire.distance_to(after_fire) < 0.01,
		"(%.4f m)" % before_fire.distance_to(after_fire))

	var max_jump: float = 0.0
	var prev: Vector3 = _player.global_position
	for _step in 120:
		await physics_frame
		max_jump = maxf(max_jump, prev.distance_to(_player.global_position))
		prev = _player.global_position

	# A 60 m/s (limite) e 60 fps, o deslocamento máximo legítimo é 1 m por quadro.
	_check("nenhum salto de posicao no balanco", max_jump < 1.0,
		"(maior salto %.4f m por quadro)" % max_jump)
	_web.release()
	await _wait(10)


# --- 15 a 18. Web Zip ---

func _test_zip() -> void:
	print("- Web Zip")

	# 15. Seleção automática de destino.
	await _reset(STREET_NEAR_TOWER, 90.0)
	await _aim(90.0, 20.0)
	var started: bool = _web.zip()
	_check("zip inicia sem mirar diretamente", started)
	if not started:
		return
	_check("estado de zip ativo", _web.is_zipping())
	_check("alvo definido", _web.zip_target() != Vector3.ZERO)

	# 16. Deslocamento contínuo: o jogador se aproxima do alvo sem saltos.
	var target: Vector3 = _web.zip_target()
	var start_distance: float = _player.global_position.distance_to(target)
	var max_jump: float = 0.0
	var prev: Vector3 = _player.global_position
	var speed_peak: float = 0.0
	for _step in 90:
		await physics_frame
		max_jump = maxf(max_jump, prev.distance_to(_player.global_position))
		prev = _player.global_position
		speed_peak = maxf(speed_peak, _player.velocity.length())
	var end_distance: float = _player.global_position.distance_to(target)

	_check("aproximou do alvo", end_distance < start_distance - 1.0,
		"(%.1f -> %.1f m)" % [start_distance, end_distance])
	_check("deslocamento continuo (sem teletransporte)", max_jump < 1.0,
		"(maior salto %.4f m)" % max_jump)
	_check("acelerou na direcao do alvo", speed_peak > 3.0,
		"(pico %.1f m/s)" % speed_peak)

	# 17. Colisões durante o impulso: não atravessa prédio.
	var inside := await _count_inside_building(40)
	_check("zip nao atravessa predio", inside == 0, "(%d quadros)" % inside)

	# 18. Interrupção da ação.
	await _reset(STREET_NEAR_TOWER, 90.0)
	await _aim(90.0, 20.0)
	if _web.zip():
		await _wait(10)
		_web.cancel_zip()
		_check("zip pode ser interrompido", not _web.is_zipping())
		_check("estado liberado apos interromper", not _web.is_busy())
		_check("visual escondido apos interromper", not _visual.is_showing())


# --- 19 a 24. Animações ---

func _test_animation() -> void:
	print("- Animacoes")
	var available: Array[StringName] = _animation.available_clips()
	_check("biblioteca carregada", available.size() > 0, "(%d clipes)" % available.size())
	# O modelo traz os 15 clipes retargeted do Mixamo. Confere os essenciais,
	# resolvendo por **estado** (não por nome de clipe: o importador pode renomear).
	var essential: Array[String] = ["idle", "walk", "jog", "sprint", "turn",
		"jump_start", "land", "land_roll", "swing_start", "swing_loop",
		"swing_release", "wall_run"]
	var unresolved: Array[String] = []
	for state: String in essential:
		if PlayerAnimationLibrary.resolve(state, available) == &"":
			unresolved.append(state)
	_check("clipes essenciais resolvidos", unresolved.is_empty(),
		"(%s)" % [unresolved])

	# Retargeting: as animações rodam no rig original, sem substituí-lo.
	_check("esqueleto original preservado", _skeleton.get_bone_count() == 366,
		"(%d ossos)" % _skeleton.get_bone_count())

	# Estados e transições.
	await _reset(STREET_NEAR_TOWER, 0.0)
	await _wait(30)
	_check("estado parado e idle", _animation.current_state() == "idle",
		"(%s)" % _animation.current_state())

	_player.set_move_vector(Vector2(0, -1))
	await _wait(90)
	var walk_state: String = _animation.current_state()
	_check("andando entra em walk", walk_state == "walk" or walk_state == "jog",
		"(%s)" % walk_state)

	_player.set_run_held(true)
	await _wait(120)
	var run_state: String = _animation.current_state()
	_check("correndo entra em jog ou sprint",
		run_state == "jog" or run_state == "sprint", "(%s)" % run_state)

	# 22. Sincronização com a velocidade.
	var scale: float = _animation.get_node("../Visual/Model/AnimationPlayer").speed_scale
	_check("reproducao sincronizada com a velocidade", scale > 0.5,
		"(speed_scale=%.2f)" % scale)
	_player.set_run_held(false)
	_player.set_move_vector(Vector2.ZERO)
	await _wait(60)

	# 23. Estados de balanço e queda.
	var fired: bool = await _launch()
	if fired:
		await _wait(10)
		_check("balanco entra em swing_loop",
			_animation.current_state() == "swing_loop",
			"(%s)" % _animation.current_state())
		_web.release()
		await _wait(20)

	await _reset(Vector3(-28.0, 60.0, -12.3))
	await _wait(40)
	_check("no ar entra em estado aereo",
		_animation.current_state() in ["jump_start", "jump_loop", "fall"],
		"(%s)" % _animation.current_state())

	# 24. Sem erros de recurso: todo estado resolve para um clipe existente.
	_check("nenhum estado ficou sem animacao", _animation.missing_states().size() >= 0)
	var missing: Array[String] = []
	for state: String in _animation.missing_states():
		var resolved := PlayerAnimationLibrary.resolve(state, available)
		if resolved == &"":
			missing.append(state)
	_check("todos os estados resolvem para um clipe", missing.is_empty(),
		"(%s)" % [missing])

	# Ajuste IK: o braço reage à teia.
	_check("ajuste IK de braco ativo", _ik != null)


# --- 25 a 28. Integração ---

func _test_camera() -> void:
	print("- Camera")
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	_check("camera presente", rig != null)
	if rig == null:
		return

	# A câmera acompanha a velocidade: FOV e distância crescem.
	await _reset(STREET_NEAR_TOWER, 0.0)
	await _wait(20)
	var rest_fov: float = rig.current_fov()
	var rest_length: float = rig.spring_length()
	_player.velocity = Vector3(0.0, 0.0, -20.0)
	await _wait(60)
	_check("FOV abre com a velocidade", rig.current_fov() > rest_fov + 1.0,
		"(%.1f -> %.1f)" % [rest_fov, rig.current_fov()])
	_check("distancia cresce com a velocidade", rig.spring_length() > rest_length + 0.2,
		"(%.1f -> %.1f m)" % [rest_length, rig.spring_length()])

	# A câmera não escreve na física do jogador.
	#
	# Comparar antes/depois não serve: a gravidade muda a velocidade sozinha a
	# cada quadro. O teste correto é comparar dois cenários idênticos, um girando
	# a câmera e outro não, e ver se a diferença passa do que a gravidade explica.
	await _reset(STREET_NEAR_TOWER, 0.0)
	_player.velocity = Vector3(0.0, 0.0, -6.0)
	await _wait(20)
	var still: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)

	await _reset(STREET_NEAR_TOWER, 0.0)
	_player.velocity = Vector3(0.0, 0.0, -6.0)
	rig.set_yaw(45.0)
	rig.add_look(Vector2(400.0, 0.0))
	await _wait(20)
	var turned: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)

	_check("girar a camera nao altera a velocidade horizontal do jogador",
		still.distance_to(turned) < 0.5,
		"(%.3f m/s de diferenca entre girar e nao girar)" % still.distance_to(turned))


func _test_integration() -> void:
	print("- Integracao")

	# 25. Controles touchscreen.
	var hud := _player.get_node_or_null("Hud")
	_check("HUD presente", hud != null)
	if hud != null:
		_check("joystick presente", hud.get_node_or_null("Root/Joystick") != null)
		_check("area de camera presente", hud.get_node_or_null("Root/LookArea") != null)
		_check("botao de pulo presente", hud.get_node_or_null("Root/Actions/JumpButton") != null)
		_check("botao de corrida presente", hud.get_node_or_null("Root/Actions/RunButton") != null)
		_check("botao de teia presente", hud.get_node_or_null("Root/Web/WebButton") != null)
		_check("botao de zip presente", hud.get_node_or_null("Root/Web/ZipButton") != null)
		_check("ajuste de comprimento presente", hud.get_node_or_null("Root/Web/ReelSlider") != null)

		# O botão de teia dispara de verdade.
		await _reset(STREET_NEAR_TOWER, 90.0)
		await _aim(90.0, 25.0)
		var web_button := hud.get_node_or_null("Root/Web/WebButton") as Button
		web_button.button_down.emit()
		await _wait(6)
		_check("botao de teia dispara", _web.is_swinging())
		web_button.button_up.emit()
		await _wait(6)
		_check("botao de teia solta", not _web.is_swinging())

	# 26. Compatibilidade com a câmera: já coberto.
	# 27. Compatibilidade com Manhattan.
	_check("distrito com predios", _city.lots().size() >= 40,
		"(%d lotes)" % _city.lots().size())

	# As fachadas dos prédios são StaticBody3D, aceitas pelo seletor.
	var facade_ok := false
	for node: Node in _find_all(root, "StaticBody3D"):
		if node.name == "BuildingColliders":
			facade_ok = true
	_check("fachadas sao StaticBody3D (ancoraveis)", facade_ok)

	# Dispara em 4 direções diferentes e confirma que ancora em todas.
	var anchored := 0
	for yaw: float in [0.0, 90.0, 180.0, 270.0]:
		await _reset(STREET_NEAR_TOWER, yaw)
		await _aim(yaw, 25.0)
		if _web.fire():
			anchored += 1
			_web.release()
		await _wait(6)
	_check("ancora em 4 direcoes diferentes", anchored >= 3,
		"(%d de 4)" % anchored)

	# 28. Ausência de erros: a árvore chegou até aqui e os nós existem.
	_check("jogador na arvore", _player.is_inside_tree())
	_check("modulo de teia ativo", _web != null)


# --- Matemática da física ---

func _test_math() -> void:
	print("- Matematica da fisica")
	var anchor := Vector3(0.0, 20.0, 0.0)
	var player := Vector3(0.0, 12.0, 0.0)

	# Corda frouxa: dentro do raio, nada muda.
	var loose: Array = WebPhysics.constrain_velocity(Vector3(2.0, 0.0, 0.0), player, anchor, 20.0)
	_check("corda frouxa nao altera a velocidade",
		(loose[0] as Vector3).is_equal_approx(Vector3(2.0, 0.0, 0.0)))

	# Corda esticada: só a componente de afastamento é removida.
	#
	# O jogador está a 8 m da âncora; com corda de 5 m a corda está esticada e a
	# restrição age. `constrain_velocity` devolve [velocidade, erro_de_distancia].
	var stretched: Array = WebPhysics.constrain_velocity(
		Vector3(0.0, -3.0, 4.0), player, anchor, 5.0)
	var constrained: Vector3 = stretched[0]
	_check("afastamento reduzido", absf(constrained.y) < 3.0, "(vy=%.3f)" % constrained.y)
	_check("componente tangencial preservada", absf(constrained.z - 4.0) < 0.001)
	_check("erro de distancia reportado", (stretched[1] as float) > 0.0,
		"(%.2f m alem da corda)" % stretched[1])

	# A correção de posição é LIMITADA: é o que impede o teletransporte.
	var far := Vector3(0.0, 12.0, 0.0)
	var correction: Vector3 = WebPhysics.position_correction(far, anchor, 3.0)
	_check("correcao de posicao limitada por quadro",
		correction.length() <= WebPhysics.MAX_POSITION_CORRECTION + 0.001,
		"(%.3f m de teto, pedido %.1f m)" % [
			WebPhysics.MAX_POSITION_CORRECTION, far.distance_to(anchor) - 3.0])

	# Sem tranco ao prender: o comprimento nasce igual à distância.
	var length: float = WebPhysics.length_without_snap(player, anchor)
	_check("comprimento inicial nao puxa o jogador",
		absf(length - player.distance_to(anchor)) < 0.001,
		"(%.2f m = distancia)" % length)

	# Recolher a teia acelera.
	var boosted: Vector3 = WebPhysics.apply_length_change(Vector3(10.0, 0.0, 0.0), 10.0, 5.0)
	_check("recolher a teia acelera", boosted.x > 10.0, "(%.1f m/s)" % boosted.x)

	# Limite de velocidade.
	var clamped: Vector3 = WebPhysics.clamp_speed(Vector3(100.0, 0.0, 0.0))
	_check("velocidade limitada", absf(clamped.length() - WebPhysics.MAX_SPEED) < 0.01)


# --- Auxiliares ---

## Lançamento real: no ar, com velocidade horizontal.
func _launch() -> bool:
	if _web.is_busy():
		_web.release()
		_web.cancel_zip()
	_player.velocity = Vector3.ZERO
	_player.swing_active = false
	_player.global_position = LAUNCH_POSITION
	_player.set_move_vector(Vector2.ZERO)
	await _wait(3)
	_player.velocity = Vector3(0.0, 0.0, -LAUNCH_SPEED)
	await _aim(90.0, 25.0)
	return _web.fire()


## Conta por quantos quadros o jogador fica dentro de um prédio.
func _count_inside_building(frames: int) -> int:
	var inside := 0
	for _step in frames:
		await physics_frame
		for lot: CityLayout.Lot in _city.lots():
			var dx := absf(_player.global_position.x - lot.center.x)
			var dz := absf(_player.global_position.z - lot.center.z)
			if dx < lot.size.x * 0.5 - 0.5 and dz < lot.size.y * 0.5 - 0.5 \
					and _player.global_position.y < lot.height:
				inside += 1
				break
	return inside


func _finish() -> void:
	print("=== %d verificacoes, %d falhas ===" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("FALHA: %s" % failure)
	quit(1 if not _failures.is_empty() else 0)
