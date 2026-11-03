extends SceneTree
## Teste funcional do sistema de teias (MISSÃO 003, revisado).
##
## Roda no próprio motor, com a cena real. Verifica os dez pontos obrigatórios e
## termina com código 1 se algo falhar.
##
## Todas as posições usadas ficam **em ruas**, nunca dentro de um prédio: um lote
## ocupa 17,4 m de lado, então nascer sobre ele empurra o jogador para baixo. As
## coordenadas das ruas do distrito de 3×3 são -84, -28, 28 e 84.
##
## Uso: godot --headless --path . --script res://tools/tests/web_swing_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ARENA_SCENE := "res://scenes/arena/test_arena.tscn"

## Faixa livre na arena de testes (paredes em x=±5).
const ARENA_LANE := Vector3(0.0, 1.2, 8.0)
## Ponto de lançamento elevado na arena, com espaço para o arco completo.
const ARENA_LAUNCH := Vector3(0.0, 6.0, 4.0)
const ARENA_LAUNCH_PITCH := 15.0
const ARENA_LAUNCH_SPEED := 5.0

var _failures: Array[String] = []
var _checks: int = 0
var _player: Node3D
var _web: Node
var _visual: Node
var _camera: Camera3D
var _spring: SpringArm3D
var _skeleton: Skeleton3D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("=== Teste do sistema de teias (MISSAO 003) ===")
	var arena := _spawn(ARENA_SCENE, Vector3.ZERO)
	if arena == null:
		_fail("arena de teste nao pode ser instanciada")
		_finish()
		return
	_player = _spawn(PLAYER_SCENE, ARENA_LANE)
	if _player == null:
		_fail("jogador nao pode ser instanciado")
		_finish()
		return

	await physics_frame
	await physics_frame

	_web = _player.get_node_or_null("WebSwing")
	_visual = _player.get_node_or_null("WebSwing/WebVisual")
	_camera = _player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
	_spring = _player.get_node_or_null("CameraRig/SpringArm3D")
	_skeleton = _find(_player, "Skeleton3D") as Skeleton3D

	await _test_setup()
	await _test_relaxed_arms()
	await _test_fire_web()
	await _test_reject_invalid()
	await _test_swing_starts()
	await _test_speed_conservation()
	await _test_length_adjust()
	await _test_release()
	await _test_release_preserves_speed()
	await _test_visual_update()
	await _test_hold_button()
	await _test_rope_not_through_floor()
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


func _find(node: Node, class_filter: String) -> Node:
	if node.is_class(class_filter):
		return node
	for child in node.get_children():
		var found := _find(child, class_filter)
		if found != null:
			return found
	return null


## Coloca o jogador em uma posição livre e zera o estado.
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


## Mira a câmera e dispara. `pitch` positivo olha para cima.
func _aim_and_fire(pitch_degrees: float) -> bool:
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	if _spring != null:
		_spring.rotation = Vector3(deg_to_rad(pitch_degrees), 0.0, 0.0)
	await _wait(3)
	return _web.fire()


## Lançamento real: no ar, com velocidade horizontal, sob o viaduto da arena.
func _launch() -> bool:
	if _web.is_swinging():
		_web.release()
	_player.velocity = Vector3.ZERO
	_player.swing_active = false
	_player.global_position = ARENA_LAUNCH
	_player.set_move_vector(Vector2.ZERO)
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	await _wait(3)
	_player.velocity = Vector3(0.0, 0.0, -ARENA_LAUNCH_SPEED)
	return await _aim_and_fire(ARENA_LAUNCH_PITCH)


# --- 1. Estrutura ---

func _test_setup() -> void:
	print("- Estrutura do sistema")
	_check("modulo de teia presente", _web != null)
	if _web == null:
		return
	_check("detector de ancoragem presente", _player.get_node_or_null("WebSwing/WebAnchorDetector") != null)
	_check("visual da teia presente", _visual != null)
	_check("camera encontrada", _camera != null)
	_check("esqueleto encontrado", _skeleton != null)
	_check("estado inicial parado", not _web.is_swinging())


# --- Braços caídos (defeito relatado) ---

func _test_relaxed_arms() -> void:
	print("- Bracos caidos")
	if _skeleton == null:
		_fail("sem esqueleto para testar os bracos")
		return
	# O clipe precisa de alguns quadros para aplicar a pose: medir no primeiro
	# quadro devolveria a pose de repouso do rig, não a do clipe.
	await _wait(40)
	var shoulder := _skeleton.global_transform * _skeleton.get_bone_global_pose(
		_skeleton.find_bone("shoulder.r")).origin
	var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(
		_skeleton.find_bone("hand.r")).origin
	var drop := shoulder.y - hand.y
	# O repouso do rig tem os braços abertos (queda de 0,41 m). Caídos, a mão
	# fica bem abaixo do ombro.
	_check("mao abaixo do ombro (bracos caidos)", drop > 0.5,
		"(queda de %.2f m; repouso aberto era 0.41)" % drop)


# --- 2 e 3. Disparo e rejeição ---

func _test_fire_web() -> void:
	print("- Disparo e ancoragem valida")
	var fired: bool = await _launch()
	_check("teia ancorou em superficie valida", fired)
	if fired:
		var anchor: Vector3 = _web.current_anchor()
		_check("ancoragem acima do jogador", anchor.y > _player.global_position.y,
			"(ancora y=%.2f, jogador y=%.2f)" % [anchor.y, _player.global_position.y])
		_check("comprimento dentro dos limites",
			_web.rope_length() >= WebSwingController.MIN_ROPE_LENGTH
			and _web.rope_length() <= WebSwingController.MAX_ROPE_LENGTH,
			"(%.2f m)" % _web.rope_length())
		_web.release()
	await _wait(20)


func _test_reject_invalid() -> void:
	print("- Rejeicao de pontos invalidos")
	await _reset(ARENA_LANE)
	var fired_sky: bool = await _aim_and_fire(80.0)
	_check("nao ancora no ceu", not fired_sky)

	await _reset(ARENA_LANE)
	var fired_floor: bool = await _aim_and_fire(-70.0)
	_check("nao ancora no chao proximo", not fired_floor)

	var detector := _player.get_node_or_null("WebSwing/WebAnchorDetector")
	var previous_max: float = detector.max_distance
	detector.max_distance = 2.0
	await _reset(ARENA_LANE)
	var fired_far: bool = await _aim_and_fire(20.0)
	_check("nao ancora alem da distancia maxima", not fired_far, "(max=2 m)")
	detector.max_distance = previous_max

	var previous_rise: float = detector.min_rise
	detector.min_rise = 100.0
	await _reset(ARENA_LANE)
	var fired_low: bool = await _aim_and_fire(20.0)
	_check("nao ancora abaixo da altura minima", not fired_low)
	detector.min_rise = previous_rise

	var exclude: Array[RID] = [_player.get_rid()]
	var hit: Dictionary = detector.find_anchor(_camera, _player.global_position, exclude)
	_check("detector devolve motivo quando falha", hit.has("reason"))
	await _wait(20)


# --- 4 e 5. Balanço ---

func _test_swing_starts() -> void:
	print("- Inicio do balanco")
	var fired: bool = await _launch()
	_check("balanco iniciado", _web.is_swinging())
	_check("controlador marcado como em balanco", _player.swing_active)
	_check("uma ancoragem ativa", _web.anchor_count() == 1)
	_web.release()
	await _wait(20)


func _test_speed_conservation() -> void:
	print("- Conservacao de velocidade no arco")
	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar a conservacao")
		return

	var highest: float = _player.global_position.y
	var lowest: float = highest
	var fastest: float = 0.0
	for _step in 90:
		await physics_frame
		fastest = maxf(fastest, _player.velocity.length())
		highest = maxf(highest, _player.global_position.y)
		lowest = minf(lowest, _player.global_position.y)

	_check("percorreu um arco de verdade", highest - lowest > 1.0,
		"(%.2f m de variacao)" % (highest - lowest))
	_check("ganhou velocidade", fastest > ARENA_LAUNCH_SPEED + 1.0,
		"(%.2f -> %.2f m/s)" % [ARENA_LAUNCH_SPEED, fastest])
	_check("velocidade dentro do limite", fastest <= WebPhysics.MAX_SPEED + 0.01,
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
	_web.set_rope_length(initial - 2.0)
	_check("recolher encurta a teia", _web.rope_length() < initial,
		"(%.2f -> %.2f m)" % [initial, _web.rope_length()])

	_web.set_rope_length(0.0)
	_check("respeita o comprimento minimo",
		_web.rope_length() >= WebSwingController.MIN_ROPE_LENGTH,
		"(%.2f m)" % _web.rope_length())
	_web.set_rope_length(1000.0)
	_check("respeita o comprimento maximo",
		_web.rope_length() <= WebSwingController.MAX_ROPE_LENGTH,
		"(%.2f m)" % _web.rope_length())

	var before_reel: float = _web.rope_length()
	_web.set_reel_input(1.0)
	await _wait(30)
	_web.set_reel_input(0.0)
	_check("entrada de recolher encurta continuamente", _web.rope_length() < before_reel,
		"(%.2f -> %.2f m)" % [before_reel, _web.rope_length()])
	_web.release()
	await _wait(20)


# --- 7 e 8. Soltura ---

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
	_check("visual da teia escondido", not _visual.is_showing())
	await _wait(10)


func _test_release_preserves_speed() -> void:
	print("- Preservacao da velocidade ao soltar")
	var previous_boost: float = _web.release_boost
	_web.release_boost = 1.0

	var fired: bool = await _launch()
	if not fired:
		_web.release_boost = previous_boost
		_fail("nao ancorou para testar a preservacao")
		return

	await _wait(60)
	var before: float = _player.velocity.length()
	var velocity_before: Vector3 = _player.velocity
	_web.release()
	var after: float = _player.velocity.length()

	_check("velocidade preservada ao soltar", absf(after - before) < 0.01,
		"(%.3f -> %.3f m/s)" % [before, after])
	_check("direcao preservada",
		velocity_before.normalized().dot(_player.velocity.normalized()) > 0.99)

	var position_before: Vector3 = _player.global_position
	await _wait(20)
	_check("continua em movimento apos soltar",
		_player.global_position.distance_to(position_before) > 0.02,
		"(moveu %.3f m)" % _player.global_position.distance_to(position_before))
	await _wait(20)
	_web.release_boost = previous_boost


# --- 9. Visual ---

func _test_visual_update() -> void:
	print("- Atualizacao visual da teia")
	_check("no visual presente", _visual != null)
	if _visual == null:
		return

	await _reset(ARENA_LANE)
	_check("teia escondida quando parado", not _visual.is_showing())

	var fired: bool = await _launch()
	if not fired:
		_fail("nao ancorou para testar o visual")
		return
	_check("teia visivel apos disparar", _visual.is_showing())

	var anchor: Vector3 = _web.current_anchor()
	var strand := _visual.get_node_or_null("Strand") as MeshInstance3D
	_check("malha da teia existe", strand != null)

	var hand_before: Vector3 = _visual.source
	await _wait(40)
	_check("ponta acompanha o jogador", hand_before.distance_to(_visual.source) > 0.05,
		"(moveu %.3f m)" % hand_before.distance_to(_visual.source))
	_check("ponta final fixa na ancoragem", _visual.target.distance_to(anchor) < 0.01)

	if strand != null:
		var midpoint: Vector3 = (_visual.source + _visual.target) * 0.5
		_check("malha centrada entre as pontas",
			strand.global_position.distance_to(midpoint) < 0.5)

	_web.release()
	await _wait(10)
	_check("teia escondida imediatamente ao soltar", not _visual.is_showing())
	await _wait(10)


# --- 10. Um botão só, por segurar ---

func _test_hold_button() -> void:
	print("- Botao unico (segurar dispara, soltar libera)")
	await _reset(ARENA_LANE)
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	if _spring != null:
		_spring.rotation = Vector3(deg_to_rad(20.0), 0.0, 0.0)
	await _wait(3)

	_web.press()
	await _wait(6)
	_check("press() dispara a teia", _web.is_swinging())

	var anchor: Vector3 = _web.current_anchor()
	await _wait(60)
	_check("a teia continua presa enquanto o botao esta apertado", _web.is_swinging())
	_check("a ancoragem nao mudou", anchor.distance_to(_web.current_anchor()) < 0.01)

	_web.release()
	await _wait(6)
	_check("release() solta a teia", not _web.is_swinging())
	_check("o visual some ao soltar", not _visual.is_showing())

	_web.press()
	await _wait(6)
	_check("press() ancora novamente", _web.is_swinging())
	_web.release()
	await _wait(10)


# --- O arco não pode atravessar o chão (defeito relatado) ---

func _test_rope_not_through_floor() -> void:
	print("- O arco nao atravessa o chao")
	await _reset(ARENA_LANE)
	var fired: bool = await _aim_and_fire(20.0)
	if not fired:
		_fail("nao ancorou para testar o arco")
		return

	var lowest: float = _web.call("arc_lowest_point")
	var floor_height: float = _player.global_position.y
	_check("fundo do arco acima do piso", lowest > floor_height - 0.5,
		"(fundo y=%.2f, piso y=%.2f)" % [lowest, floor_height])

	# E na prática: balançando, o jogador precisa sair do chão.
	var minimum_height: float = _player.global_position.y
	for _step in 90:
		await physics_frame
		minimum_height = minf(minimum_height, _player.global_position.y)
	_check("o jogador nao e arrastado pelo chao", minimum_height > -1.0,
		"(altura minima %.2f m)" % minimum_height)
	_web.release()
	await _wait(20)


# --- Compatibilidade ---

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
	_check("botao unico de teia presente", hud.get_node_or_null("Root/Web/WebButton") != null)
	_check("ajuste de comprimento presente", hud.get_node_or_null("Root/Web/ReelSlider") != null)

	await _reset(ARENA_LANE)
	_player.set_move_vector(Vector2(0, -1))
	await _wait(120)
	_check("movimentacao no chao preservada", _player.current_speed() > 1.0,
		"(%.2f m/s)" % _player.current_speed())
	_player.set_move_vector(Vector2.ZERO)
	await _wait(60)

	# O botão da HUD precisa funcionar por segurar/soltar.
	var web_button := hud.get_node_or_null("Root/Web/WebButton") as Button
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	if _spring != null:
		_spring.rotation = Vector3(deg_to_rad(20.0), 0.0, 0.0)
	await _wait(3)
	web_button.button_down.emit()
	await _wait(6)
	_check("botao da HUD dispara ao pressionar", _web.is_swinging())
	web_button.button_up.emit()
	await _wait(6)
	_check("botao da HUD solta ao levantar", not _web.is_swinging())
	await _wait(20)


# --- Matemática da física ---

func _test_physics_math() -> void:
	print("- Matematica da fisica")
	var anchor := Vector3(0.0, 10.0, 0.0)
	# 4 m abaixo da âncora: distância 6, corda 5 → a corda está esticada.
	var player := Vector3(0.0, 4.0, 0.0)

	# Corda frouxa: dentro do raio, nada acontece.
	var inside: Array = WebPhysics.apply_rope_constraint(player, Vector3(1.0, 0.0, 0.0),
		anchor, 8.0)
	_check("corda frouxa nao altera a posicao",
		(inside[0] as Vector3).is_equal_approx(player))
	_check("corda frouxa nao altera a velocidade",
		(inside[1] as Vector3).is_equal_approx(Vector3(1.0, 0.0, 0.0)))

	# Corda esticada: posição corrigida para o raio.
	var outward := Vector3(0.0, -3.0, 4.0)
	var stretched: Array = WebPhysics.apply_rope_constraint(player, outward, anchor, 5.0)
	var corrected: Vector3 = stretched[0]
	_check("posicao corrigida para o raio da corda",
		absf(corrected.distance_to(anchor) - 5.0) < 0.001,
		"(%.4f m)" % corrected.distance_to(anchor))
	var constrained: Vector3 = stretched[1]
	_check("afastamento reduzido", absf(constrained.y) < absf(outward.y),
		"(vy %.3f -> %.3f)" % [outward.y, constrained.y])
	_check("componente tangencial preservada", absf(constrained.z - 4.0) < 0.001,
		"(vz=%.4f)" % constrained.z)

	# Aproximar-se da âncora nunca é freado.
	var inward := Vector3(0.0, 2.0, 0.0)
	var free_result: Array = WebPhysics.apply_rope_constraint(player, inward, anchor, 5.0)
	_check("aproximar-se da ancora nao freia",
		(free_result[1] as Vector3).is_equal_approx(inward))

	var boosted: Vector3 = WebPhysics.apply_length_change(Vector3(10.0, 0.0, 0.0), 10.0, 5.0)
	_check("recolher a teia acelera", boosted.x > 10.0, "(%.2f m/s)" % boosted.x)

	var clamped: Vector3 = WebPhysics.clamp_speed(Vector3(100.0, 0.0, 0.0))
	_check("velocidade limitada", absf(clamped.length() - WebPhysics.MAX_SPEED) < 0.01)

	_check("altura relativa correta",
		WebPhysics.height_below_anchor(Vector3(0.0, 3.0, 0.0), anchor) < 0.0)

	# O comprimento seguro impede o arco de descer abaixo do piso.
	var safe: float = WebPhysics.safe_length(Vector3(0.0, 10.0, 0.0), 20.0, 2.0)
	_check("comprimento seguro limita o arco", safe <= 8.0, "(%.2f m)" % safe)
	_check("fundo do arco calculado corretamente",
		absf(WebPhysics.arc_lowest_point(Vector3(0.0, 10.0, 0.0), 4.0) - 6.0) < 0.001)


func _finish() -> void:
	print("=== %d verificacoes, %d falhas ===" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("FALHA: %s" % failure)
	quit(1 if not _failures.is_empty() else 0)
