extends SceneTree
## Teste funcional do sistema de teias e balanço (MISSÃO 003).
##
## Roda no próprio motor, com a cena real do jogador e o cenário real. Verifica
## os dez pontos obrigatórios da missão e termina com código 1 se algo falhar.
##
## Uso: godot --headless --path . --script res://tools/tests/web_swing_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ARENA_SCENE := "res://scenes/arena/test_arena.tscn"
## Faixa livre, entre as paredes em x=±5.
const LANE_FREE := Vector3(0.0, 1.2, 8.0)
## Ponto de lançamento elevado, à frente do viaduto, com espaço livre para o
## arco completo. O balanço real começa no ar e com velocidade horizontal: largar
## o jogador parado embaixo da ancoragem o deixaria já no ponto mais baixo, sem
## arco para percorrer.
const LAUNCH_POSITION := Vector3(0.0, 6.0, 4.0)
## Inclinação da câmera que encontra o tabuleiro do viaduto a partir do lançamento.
const LAUNCH_PITCH := 15.0
## Velocidade horizontal inicial do lançamento, em m/s.
const LAUNCH_SPEED := 5.0

var _failures: Array[String] = []
var _checks: int = 0
var _player: Node3D
var _web: Node
var _camera: Camera3D
var _skeleton: Skeleton3D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("=== Teste do sistema de teias (MISSAO 003) ===")
	var arena := _spawn(ARENA_SCENE, Vector3.ZERO)
	_player = _spawn(PLAYER_SCENE, LANE_FREE)
	if arena == null or _player == null:
		_fail("cenario ou jogador nao puderam ser instanciados")
		_finish()
		return

	await physics_frame
	await physics_frame

	_web = _player.get_node_or_null("WebSwing")
	_camera = _player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
	_skeleton = _find_first(_player, "Skeleton3D")

	await _test_setup()
	await _test_fire_web()
	await _test_reject_invalid()
	await _test_swing_starts()
	await _test_speed_conservation()
	await _test_length_adjust()
	await _test_release()
	await _test_release_preserves_speed()
	await _test_visual_update()
	await _test_existing_controls()
	await _test_physics_math()

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


func _find_first(node: Node, class_filter: String) -> Node:
	if node.is_class(class_filter):
		return node
	for child in node.get_children():
		var found := _find_first(child, class_filter)
		if found != null:
			return found
	return null


## Coloca o jogador em uma posição previsível e limpa o estado do balanço.
func _reset(position: Vector3, yaw: float = 0.0) -> void:
	if _web.is_swinging():
		_web.release()
	_player.velocity = Vector3.ZERO
	_player.swing_active = false
	_player.global_position = position
	_player.set_move_vector(Vector2.ZERO)
	_player.set_run_held(false)
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(yaw)
	await _wait(40)


## Prepara um balanço real: posiciona o jogador no ar, dá velocidade horizontal e
## dispara a teia. A espera é curta de propósito, para o jogador não cair antes de
## a teia prender.
func _launch() -> bool:
	if _web.is_swinging():
		_web.release()
	_player.velocity = Vector3.ZERO
	_player.swing_active = false
	_player.global_position = LAUNCH_POSITION
	_player.set_move_vector(Vector2.ZERO)
	_player.set_run_held(false)
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	await _wait(3)
	_player.velocity = Vector3(0.0, 0.0, -LAUNCH_SPEED)
	return await _aim_and_fire(LAUNCH_PITCH)


## Aponta a câmera para uma direção e dispara a teia.
func _aim_and_fire(pitch_degrees: float) -> bool:
	var rig := _player.get_node_or_null("CameraRig")
	var spring := _player.get_node_or_null("CameraRig/SpringArm3D")
	if rig != null:
		rig.set_yaw(0.0)
	if spring != null:
		spring.rotation = Vector3(deg_to_rad(pitch_degrees), 0.0, 0.0)
	await _wait(2)
	return _web.fire()


# --- 1. Configuração do sistema ---

func _test_setup() -> void:
	print("- Estrutura do sistema")
	_check("modulo de teia presente", _web != null)
	if _web == null:
		return
	_check("detector de ancoragem presente", _player.get_node_or_null("WebSwing/WebAnchorDetector") != null)
	_check("visual da teia presente", _player.get_node_or_null("WebSwing/WebVisual") != null)
	_check("camera encontrada", _camera != null)
	_check("esqueleto encontrado", _skeleton != null)
	_check("estado inicial parado", not _web.is_swinging())
	_check("nenhuma ancoragem ativa", _web.anchor_count() == 0)


# --- 2 e 3. Disparo, ancoragem válida e rejeição ---

func _test_fire_web() -> void:
	print("- Disparo e ancoragem valida")
	var fired: bool = await _launch()
	_check("teia ancorou em superficie valida", fired)
	if fired:
		var anchor: Vector3 = _web.current_anchor()
		_check("ancoragem acima do jogador", anchor.y > _player.global_position.y,
			"(ancora y=%.2f, jogador y=%.2f)" % [anchor.y, _player.global_position.y])
		_check("comprimento dentro dos limites", _web.rope_length() >= WebSwingController.MIN_ROPE_LENGTH
			and _web.rope_length() <= WebSwingController.MAX_ROPE_LENGTH,
			"(%.2f m)" % _web.rope_length())
		_web.release()
	await _wait(20)


func _test_reject_invalid() -> void:
	print("- Rejeicao de pontos invalidos")
	# 1) Sem ancoragem na mira: apontando quase na vertical, para o céu.
	await _reset(LANE_FREE)
	var fired_sky: bool = await _aim_and_fire(80.0)
	_check("nao ancora no ceu", not fired_sky)

	# 2) Ancoragem baixa demais: olhando para o chão à frente.
	await _reset(LANE_FREE)
	var fired_floor: bool = await _aim_and_fire(-70.0)
	_check("nao ancora no chao proximo", not fired_floor)

	# 3) Distância máxima: apontando para um alvo muito distante.
	var detector := _player.get_node_or_null("WebSwing/WebAnchorDetector")
	var previous_max: float = detector.max_distance
	detector.max_distance = 2.0
	await _reset(LANE_FREE)
	var fired_far: bool = await _aim_and_fire(20.0)
	_check("nao ancora alem da distancia maxima", not fired_far, "(max=2 m)")
	detector.max_distance = previous_max

	# 4) Altura mínima: exige subida, então um alvo quase nivelado é rejeitado.
	var previous_rise: float = detector.min_rise
	detector.min_rise = 100.0
	await _reset(LANE_FREE)
	var fired_low: bool = await _aim_and_fire(20.0)
	_check("nao ancora abaixo da altura minima", not fired_low)
	detector.min_rise = previous_rise

	# 5) Superfície inválida: a própria cápsula do jogador é excluída do raio.
	await _reset(LANE_FREE)
	var hit: Dictionary = detector.find_anchor(_camera, _player.global_position, [])
	_check("detector devolve motivo quando falha", hit.has("reason"),
		"(%s)" % str(hit.get("reason", "")))
	await _wait(20)


# --- 4 e 5. Balanço e conservação de velocidade ---

func _test_swing_starts() -> void:
	print("- Inicio do balanco")
	var fired: bool = await _launch()
	_check("balanco iniciado", _web.is_swinging())
	_check("controlador marcado como em balanco", _player.swing_active)
	_check("uma ancoragem ativa", _web.anchor_count() == 1)

	# Com a teia presa, o jogador não deve cair livremente: a distância à
	# ancoragem fica limitada ao comprimento da corda.
	var anchor: Vector3 = _web.current_anchor()
	var length: float = _web.rope_length()
	await _wait(60)
	var distance := _player.global_position.distance_to(anchor)
	_check("distancia a ancoragem respeita a corda", distance <= length + 0.6,
		"(dist=%.2f, corda=%.2f)" % [distance, length])
	_web.release()
	await _wait(20)


func _test_speed_conservation() -> void:
	print("- Conservacao de velocidade no arco")
	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar a conservacao")
		return

	# Amostra o arco inteiro: o pêndulo converte altura em velocidade ao descer.
	# Medir em quadros fixos seria frágil, porque o instante exato do ponto mais
	# baixo depende do comprimento da corda.
	var highest_y := _player.global_position.y
	var lowest_y := highest_y
	var fastest := 0.0
	var speed_at_lowest := 0.0
	var lowest_recorded := false
	for _step in 70:
		await physics_frame
		var speed: float = _player.velocity.length()
		var height: float = _player.global_position.y
		fastest = maxf(fastest, speed)
		if height < lowest_y:
			lowest_y = height
			speed_at_lowest = speed
			lowest_recorded = true
		highest_y = maxf(highest_y, height)

	_check("balanco desceu pelo arco", lowest_y < highest_y - 1.0,
		"(y %.2f -> %.2f)" % [highest_y, lowest_y])
	_check("ganhou velocidade ao descer", fastest > LAUNCH_SPEED + 1.0,
		"(%.2f -> %.2f m/s, inicio %.1f)" % [LAUNCH_SPEED, fastest, LAUNCH_SPEED])
	_check("velocidade maxima no ponto mais baixo",
		not lowest_recorded or speed_at_lowest > LAUNCH_SPEED,
		"(%.2f m/s no ponto baixo)" % speed_at_lowest)
	_check("velocidade dentro do limite", fastest <= WebPhysics.MAX_SPEED + 0.01,
		"(%.2f m/s)" % fastest)
	_check("balanco segue rendendo velocidade", fastest > 8.0,
		"(%.2f m/s)" % fastest)

	_web.release()
	await _wait(20)


# --- 6. Ajuste de comprimento ---

func _test_length_adjust() -> void:
	print("- Ajuste do comprimento da teia")
	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar o ajuste")
		return

	var initial: float = _web.rope_length()
	_web.set_rope_length(initial - 3.0)
	_check("recolher encurta a teia", _web.rope_length() < initial,
		"(%.2f -> %.2f m)" % [initial, _web.rope_length()])

	var shortened: float = _web.rope_length()
	_web.set_rope_length(shortened + 2.0)
	_check("afrouxar alonga a teia", _web.rope_length() > shortened,
		"(%.2f -> %.2f m)" % [shortened, _web.rope_length()])

	# Limites precisam ser respeitados.
	_web.set_rope_length(0.0)
	_check("respeita o comprimento minimo", _web.rope_length() >= WebSwingController.MIN_ROPE_LENGTH,
		"(%.2f m)" % _web.rope_length())
	_web.set_rope_length(1000.0)
	_check("respeita o comprimento maximo", _web.rope_length() <= WebSwingController.MAX_ROPE_LENGTH,
		"(%.2f m)" % _web.rope_length())

	# A entrada contínua deve mover o comprimento.
	_web.set_rope_length(20.0)
	var before_reel: float = _web.rope_length()
	_web.set_reel_input(1.0)
	await _wait(30)
	_web.set_reel_input(0.0)
	_check("entrada de recolher encurta continuamente", _web.rope_length() < before_reel,
		"(%.2f -> %.2f m)" % [before_reel, _web.rope_length()])

	_web.release()
	await _wait(20)


# --- 7 e 8. Soltura e preservação de velocidade ---

func _test_release() -> void:
	print("- Soltura da teia")
	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar a soltura")
		return
	await _wait(40)
	_web.release()
	_check("estado volta a parado", not _web.is_swinging())
	_check("ancoragens limpas", _web.anchor_count() == 0)
	_check("controlador liberado do balanco", not _player.swing_active)
	_check("visual da teia escondido", not _web.get_node("WebVisual").is_showing())
	await _wait(10)


func _test_release_preserves_speed() -> void:
	print("- Preservacao da velocidade ao soltar")
	# Este teste mede a preservação pura: o impulso opcional de soltura é
	# desligado para isolar o comportamento da física.
	var previous_boost: float = _web.release_boost
	_web.release_boost = 1.0

	var fired: bool = await _launch()
	if not fired:
		_web.release_boost = previous_boost
		_fail("nao ancorou para testar a preservacao")
		return

	# Espera ganhar velocidade no arco, então solta e mede imediatamente.
	await _wait(60)
	var before: float = _player.velocity.length()
	var velocity_before: Vector3 = _player.velocity
	_web.release()
	var after: float = _player.velocity.length()

	_check("velocidade preservada ao soltar", absf(after - before) < 0.01,
		"(%.3f -> %.3f m/s)" % [before, after])
	_check("direcao preservada", velocity_before.normalized().dot(_player.velocity.normalized()) > 0.99,
		"(dot=%.4f)" % velocity_before.normalized().dot(_player.velocity.normalized()))
	_check("soltura nao freia o jogador", after >= before * 0.99)

	# Depois de soltar, o jogador segue em trajetória balística: a posição
	# continua mudando (não trava no ar).
	var position_before: Vector3 = _player.global_position
	await _wait(20)
	_check("continua em movimento apos soltar",
		_player.global_position.distance_to(position_before) > 0.02,
		"(moveu %.3f m)" % _player.global_position.distance_to(position_before))
	await _wait(20)
	_web.release_boost = previous_boost


# --- 9. Atualização visual ---

func _test_visual_update() -> void:
	print("- Atualizacao visual da teia")
	var visual := _player.get_node_or_null("WebSwing/WebVisual")
	_check("no visual presente", visual != null)
	if visual == null:
		return

	await _reset(LANE_FREE)
	_check("teia escondida quando parado", not visual.is_showing())

	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar o visual")
		return
	_check("teia visivel apos disparar", visual.is_showing())

	var anchor: Vector3 = _web.current_anchor()
	var strand := visual.get_node_or_null("Strand") as MeshInstance3D
	_check("malha da teia existe", strand != null)

	# A ponta da teia precisa acompanhar a mão do jogador a cada quadro.
	var hand_before: Vector3 = visual.source
	await _wait(40)
	var hand_after: Vector3 = visual.source
	_check("ponta acompanha o jogador", hand_before.distance_to(hand_after) > 0.05,
		"(moveu %.3f m)" % hand_before.distance_to(hand_after))
	_check("ponta final fixa na ancoragem", visual.target.distance_to(anchor) < 0.01,
		"(%.4f m)" % visual.target.distance_to(anchor))

	# A malha deve estar entre as duas pontas.
	if strand != null:
		var midpoint: Vector3 = (visual.source + visual.target) * 0.5
		_check("malha centrada entre as pontas",
			strand.global_position.distance_to(midpoint) < 0.5,
			"(%.3f m)" % strand.global_position.distance_to(midpoint))

	_web.release()
	await _wait(10)
	_check("teia escondida imediatamente ao soltar", not visual.is_showing())
	await _wait(10)


# --- 10. Compatibilidade com os controles existentes ---

func _test_existing_controls() -> void:
	print("- Compatibilidade com os controles existentes")
	var hud := _player.get_node_or_null("Hud")
	_check("HUD preservada", hud != null)
	if hud == null:
		return

	_check("joystick preservado", hud.get_node_or_null("Root/Joystick") != null)
	_check("area de camera preservada", hud.get_node_or_null("Root/LookArea") != null)
	_check("botao de pulo preservado", hud.get_node_or_null("Root/Actions/JumpButton") != null)
	_check("botao de corrida preservado", hud.get_node_or_null("Root/Actions/RunButton") != null)
	_check("botao de teia presente", hud.get_node_or_null("Root/Web/FireButton") != null)
	_check("botao de soltar presente", hud.get_node_or_null("Root/Web/ReleaseButton") != null)
	_check("ajuste de comprimento presente", hud.get_node_or_null("Root/Web/ReelSlider") != null)

	# O botão de teia precisa disparar de verdade, e o de soltar precisa soltar.
	await _reset(LANE_FREE)
	var fire_button := hud.get_node_or_null("Root/Web/FireButton") as Button
	var release_button := hud.get_node_or_null("Root/Web/ReleaseButton") as Button
	if fire_button == null or release_button == null:
		return

	var rig := _player.get_node_or_null("CameraRig")
	var spring := _player.get_node_or_null("CameraRig/SpringArm3D")
	if rig != null:
		rig.set_yaw(0.0)
	if spring != null:
		spring.rotation = Vector3(deg_to_rad(20.0), 0.0, 0.0)
	await _wait(2)

	fire_button.pressed.emit()
	await _wait(6)
	_check("botao de teia dispara", _web.is_swinging())

	release_button.pressed.emit()
	await _wait(6)
	_check("botao de soltar solta", not _web.is_swinging())

	# O movimento no chão continua funcionando com o sistema de teia presente.
	await _reset(LANE_FREE)
	_player.set_move_vector(Vector2(0, -1))
	await _wait(120)
	_check("movimentacao no chao preservada", _player.current_speed() > 1.0,
		"(%.2f m/s)" % _player.current_speed())
	_player.set_move_vector(Vector2.ZERO)
	await _wait(60)

	# Ajuste de comprimento pela HUD.
	var fired: bool = await _aim_and_fire(20.0)
	if fired:
		var slider := hud.get_node_or_null("Root/Web/ReelSlider") as HSlider
		var before: float = _web.rope_length()
		slider.value = 1.0
		await _wait(30)
		slider.value = 0.0
		_check("controle deslizante ajusta o comprimento", _web.rope_length() < before,
			"(%.2f -> %.2f m)" % [before, _web.rope_length()])
		_web.release()
	await _wait(20)


# --- Matemática da física, sem depender da árvore ---

func _test_physics_math() -> void:
	print("- Matematica da fisica")
	# A corda não empurra: velocidade apontando para fora é removida.
	var anchor := Vector3(0.0, 10.0, 0.0)
	var player := Vector3(0.0, 5.0, 0.0)
	var outward := Vector3(0.0, -3.0, 4.0)
	var result: Array = WebPhysics.apply_rope_constraint(player, outward, anchor, 5.0)
	var constrained: Vector3 = result[1]
	_check("componente radial de afastamento removida", absf(constrained.y) < 0.001,
		"(vy=%.4f)" % constrained.y)
	_check("componente tangencial preservada", absf(constrained.z - 4.0) < 0.001,
		"(vz=%.4f)" % constrained.z)

	# A posição é corrigida para a esfera da corda.
	var corrected: Vector3 = result[0]
	_check("posicao corrigida para o raio da corda",
		absf(corrected.distance_to(anchor) - 5.0) < 0.001,
		"(%.4f m)" % corrected.distance_to(anchor))

	# Velocidade apontando para dentro não é alterada.
	var inward := Vector3(0.0, 2.0, 0.0)
	var free_result: Array = WebPhysics.apply_rope_constraint(player, inward, anchor, 5.0)
	var free_velocity: Vector3 = free_result[1]
	_check("aproximar-se da ancora nao freia", free_velocity.distance_to(inward) < 0.001)

	# Recolher a teia acelera (momento angular).
	var boosted: Vector3 = WebPhysics.apply_length_change(Vector3(10.0, 0.0, 0.0), 10.0, 5.0)
	_check("recolher a teia acelera", boosted.x > 10.0, "(%.2f m/s)" % boosted.x)

	# O limite de velocidade funciona.
	var clamped: Vector3 = WebPhysics.clamp_speed(Vector3(100.0, 0.0, 0.0))
	_check("velocidade limitada", absf(clamped.length() - WebPhysics.MAX_SPEED) < 0.01,
		"(%.2f m/s)" % clamped.length())

	# A altura relativa é negativa abaixo da ancoragem.
	_check("altura relativa correta",
		WebPhysics.height_below_anchor(Vector3(0.0, 3.0, 0.0), anchor) < 0.0)


func _finish() -> void:
	print("=== %d verificacoes, %d falhas ===" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("FALHA: %s" % failure)
	quit(1 if not _failures.is_empty() else 0)
