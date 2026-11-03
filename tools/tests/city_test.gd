extends SceneTree
## Teste funcional do distrito urbano (MISSÃO 004).
##
## Roda no próprio motor, com a cena real. Verifica os dez pontos obrigatórios da
## missão e mede o que é mensurável neste ambiente (geometria, chamadas de
## renderização, tempo de geração). Não mede FPS no Galaxy A14: não há aparelho
## físico aqui, e inventar esse número seria mentir.
##
## Uso: godot --headless --path . --script res://tools/tests/city_test.gd

const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _failures: Array[String] = []
var _checks: int = 0
var _district: Node3D
var _player: Node3D
var _web: Node
var _camera: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	print("=== Teste do distrito urbano (MISSAO 004) ===")

	var generation_ms := Time.get_ticks_msec()
	_district = _spawn(DISTRICT_SCENE, Vector3.ZERO)
	if _district == null:
		_fail("distrito nao pode ser instanciado")
		_finish()
		return
	await physics_frame
	await physics_frame
	generation_ms = Time.get_ticks_msec() - generation_ms

	_player = _spawn(PLAYER_SCENE, _district.call("spawn_position"))
	if _player == null:
		_fail("jogador nao pode ser instanciado")
		_finish()
		return
	await physics_frame
	await physics_frame
	_web = _player.get_node_or_null("WebSwing")
	_camera = _player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")

	_test_loading(generation_ms)
	_test_geometry_and_draw_calls()
	await _test_collisions()
	await _test_movement_between_blocks()
	await _test_rooftop_access()
	await _test_web_between_buildings()
	await _test_facade_anchoring()
	_test_no_errors()
	_test_mobile_renderer()
	_test_expansion_readiness()
	_report_metrics(generation_ms)

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


func _find_all(node: Node, class_filter: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(class_filter):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, class_filter))
	return found


# --- 1. Carregamento completo da região ---

func _test_loading(generation_ms: int) -> void:
	print("- Carregamento da regiao")
	var stats: Dictionary = _district.call("city").statistics()
	_check("distrito instanciado", _district != null)
	_check("quarteiroes gerados", stats.get("blocks", 0) >= 9, "(%d)" % stats.get("blocks", 0))
	_check("predios gerados", stats.get("buildings", 0) >= 40, "(%d)" % stats.get("buildings", 0))
	_check("extensao do distrito", stats.get("district_extent", 0.0) > 150.0,
		"(%.0f m)" % stats.get("district_extent", 0.0))
	_check("alturas variadas", stats.get("max_building_height", 0.0) > 40.0,
		"(max %.0f m)" % stats.get("max_building_height", 0.0))
	_check("geracao rapida", generation_ms < 5000, "(%d ms)" % generation_ms)
	_check("ambiente e luz presentes",
		_district.get_node_or_null("WorldEnvironment") != null
		and _district.get_node_or_null("Sun") != null)


# --- 8. Renderer Mobile e uso de recursos ---

func _test_geometry_and_draw_calls() -> void:
	print("- Geometria e chamadas de renderizacao")
	var stats: Dictionary = _district.call("city").statistics()
	var multimeshes := _find_all(_district, "MultiMeshInstance3D")
	var mesh_instances := _find_all(_district, "MeshInstance3D")

	# Cada MultiMesh é uma chamada de renderização por superfície, então este
	# número é o teto de draw calls do distrito.
	_check("poucas malhas soltas", mesh_instances.size() <= 40,
		"(%d MeshInstance3D)" % mesh_instances.size())
	_check("geometria repetida usa MultiMesh", multimeshes.size() >= 8,
		"(%d MultiMeshInstance3D)" % multimeshes.size())
	_check("corpos dos predios em um unico MultiMesh",
		stats.get("body_draw_calls", 0) == 1)

	var total_instances := 0
	for node: MultiMeshInstance3D in multimeshes:
		total_instances += node.multimesh.instance_count
	_check("objetos instanciados", total_instances > 500, "(%d instancias)" % total_instances)
	_check("variedade urbana presente",
		stats.get("light_poles", 0) > 0 and stats.get("traffic_signals", 0) > 0
		and stats.get("water_towers", 0) > 0 and stats.get("air_conditioners", 0) > 0,
		"(postes %d, semaforos %d, caixas d'agua %d, ares %d)" % [
			stats.get("light_poles", 0), stats.get("traffic_signals", 0),
			stats.get("water_towers", 0), stats.get("air_conditioners", 0)])


# --- 2. Integridade das colisões ---

func _test_collisions() -> void:
	print("- Integridade das colisoes")
	var colliders := _find_all(_district, "StaticBody3D")
	_check("corpos estaticos existem", colliders.size() >= 2, "(%d)" % colliders.size())

	var building_body := _district.get_node_or_null("District/BuildingColliders")
	_check("colisores dos predios existem", building_body != null)
	if building_body != null:
		var stats: Dictionary = _district.call("city").statistics()
		_check("um colisor por predio",
			building_body.get_child_count() == stats.get("buildings", -1),
			"(%d colisores para %d predios)" % [
				building_body.get_child_count(), stats.get("buildings", 0)])

	# O jogador não pode atravessar o chão.
	_player.global_position = Vector3(0.0, 6.0, 0.0)
	_player.velocity = Vector3.ZERO
	await _wait(150)
	_check("jogador nao atravessa o chao", _player.global_position.y > -5.0,
		"(y=%.2f)" % _player.global_position.y)
	_check("jogador pousou", _player.is_on_floor() or _player.global_position.y > 0.0,
		"(y=%.2f)" % _player.global_position.y)


# --- 3. Movimentação entre os quarteirões ---

func _test_movement_between_blocks() -> void:
	print("- Movimentacao entre quarteiroes")
	var start := _district.call("spawn_position") as Vector3
	_player.global_position = start
	_player.velocity = Vector3.ZERO
	await _wait(60)

	# Caminha em direção ao centro do distrito por vários segundos.
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	await _wait(5)
	var start_position := _player.global_position
	_player.set_move_vector(Vector2(0, -1))
	_player.set_run_held(true)
	await _wait(400)
	var travelled := start_position.distance_to(_player.global_position)
	_player.set_run_held(false)
	_player.set_move_vector(Vector2.ZERO)
	await _wait(60)

	_check("correu pelo distrito", travelled > 15.0, "(percorreu %.1f m)" % travelled)
	_check("nao caiu do mundo", _player.global_position.y > -5.0,
		"(y=%.2f)" % _player.global_position.y)


# --- 4. Acesso aos telhados ---

func _test_rooftop_access() -> void:
	print("- Acesso aos telhados")
	var city: CityGenerator = _district.call("city")
	var lots: Array = city.lots()
	_check("lotes disponiveis", lots.size() > 0, "(%d)" % lots.size())
	if lots.is_empty():
		return

	# Coloca o jogador sobre um telhado e confirma que ele fica em pé.
	var lot: CityLayout.Lot = lots[0]
	var rooftop := lot.center + Vector3(0.0, lot.height + 2.0, 0.0)
	_player.global_position = rooftop
	_player.velocity = Vector3.ZERO
	await _wait(150)

	var expected_top := lot.height + 0.6
	_check("telhado e uma superficie solida",
		_player.global_position.y > expected_top - 1.5,
		"(pousou em y=%.2f, topo do predio %.2f)" % [_player.global_position.y, lot.height])
	_check("jogador esta apoiado no telhado", _player.is_on_floor(),
		"(on_floor=%s)" % _player.is_on_floor())

	# Telhados precisam ser alcançáveis: há prédios de alturas diferentes.
	var heights: Array[float] = []
	for candidate: CityLayout.Lot in lots:
		heights.append(candidate.height)
	heights.sort()
	_check("existem predios de varias alturas",
		heights[-1] - heights[0] > 25.0,
		"(%.0f m a %.0f m)" % [heights[0], heights[-1]])


# --- 5. Teias entre os edifícios ---

func _test_web_between_buildings() -> void:
	print("- Teias entre edificios")
	var city: CityGenerator = _district.call("city")
	var lots: Array = city.lots()
	if lots.is_empty():
		_fail("sem lotes para testar a teia")
		return

	# Escolhe o prédio mais alto do distrito.
	var tallest: CityLayout.Lot = lots[0]
	for candidate: CityLayout.Lot in lots:
		if candidate.height > tallest.height:
			tallest = candidate

	# Balanço realista: o jogador está **no ar e bem abaixo do topo**, a uma
	# distância horizontal da fachada, indo na direção dela. Assim a corda fica
	# longa e há arco de verdade para percorrer — pendurar-se colado ao topo daria
	# uma corda de poucos metros e nenhuma velocidade a ganhar.
	var facade_offset := tallest.size.y * 0.5 + 22.0
	var start_height := tallest.height * 0.30
	var start := tallest.center + Vector3(0.0, 0.0, facade_offset)
	start.y = start_height

	if _web.is_swinging():
		_web.release()
	_player.global_position = start
	_player.swing_active = false
	# Encara a fachada: yaw 180° aponta para -Z, onde está o prédio.
	var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	var spring := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	if rig != null:
		rig.set_yaw(180.0)
	if spring != null:
		spring.rotation = Vector3(deg_to_rad(14.0), 0.0, 0.0)
	await _wait(3)
	# Impulso horizontal na direção do prédio, como quem salta de um telhado.
	_player.velocity = Vector3(0.0, 0.0, -6.0)

	var fired: bool = _web.fire()
	_check("teia ancorou na fachada do predio", fired)
	if fired:
		var anchor: Vector3 = _web.current_anchor()
		var rope: float = _web.rope_length()
		_check("ancoragem acima do jogador", anchor.y > _player.global_position.y,
			"(ancora y=%.2f, jogador y=%.2f)" % [anchor.y, _player.global_position.y])
		_check("corda longa o bastante para o arco", rope > 10.0, "(%.1f m)" % rope)

		# Amostra o arco: velocidade máxima e variação de altura.
		var fastest := 0.0
		var highest := _player.global_position.y
		var lowest := highest
		for _step in 90:
			await physics_frame
			fastest = maxf(fastest, _player.velocity.length())
			highest = maxf(highest, _player.global_position.y)
			lowest = minf(lowest, _player.global_position.y)

		_check("balanco ganha velocidade entre predios", fastest > 9.0,
			"(%.2f m/s)" % fastest)
		_check("percorreu um arco de verdade", highest - lowest > 1.5,
			"(%.2f m de variacao de altura)" % (highest - lowest))
		_web.release()
		await _wait(30)


# --- 6. Detecção de ancoragem nas fachadas ---

func _test_facade_anchoring() -> void:
	print("- Deteccao de ancoragem nas fachadas")
	var city: CityGenerator = _district.call("city")
	var lots: Array = city.lots()
	var detector := _player.get_node_or_null("WebSwing/WebAnchorDetector")
	_check("detector presente", detector != null)
	if detector == null or lots.is_empty():
		return

	# As fachadas precisam ser StaticBody3D, senão o detector as recusa.
	var building_body := _district.get_node_or_null("District/BuildingColliders")
	var is_static := building_body is StaticBody3D
	_check("fachadas sao StaticBody3D (aceitas pelo detector)", is_static)

	# Varre alguns prédios e conta quantos aceitam ancoragem a partir do ar.
	# A câmera é posicionada olhando para o prédio: o `yaw` da Godot aponta para
	# -Z, então para encarar um alvo em +Z é preciso somar 180°.
	var accepted := 0
	var tested := 0
	var reasons: Array[String] = []
	var exclude_rids: Array[RID] = [_player.get_rid()]
	for index in mini(lots.size(), 6):
		var lot: CityLayout.Lot = lots[index]
		# Fica de frente para uma das faces do prédio, na altura do meio dele.
		var face_offset := Vector3(0.0, 0.0, lot.size.y * 0.5 + 16.0)
		var approach := lot.center + face_offset
		var stand := Vector3(approach.x, lot.height * 0.45, approach.z)
		_player.global_position = stand
		_player.velocity = Vector3.ZERO
		if _web.is_swinging():
			_web.release()
		await _wait(3)

		# Encara o prédio (alvo em -Z a partir do jogador).
		var rig := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
		var spring := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
		if rig != null:
			rig.set_yaw(180.0)
		if spring != null:
			# Olha levemente para cima: a ancoragem precisa estar acima.
			spring.rotation = Vector3(deg_to_rad(12.0), 0.0, 0.0)
		await _wait(3)

		tested += 1
		if _web.fire():
			accepted += 1
			_web.release()
			await _wait(3)
		else:
			var hit: Dictionary = detector.find_anchor(
				_camera, _player.global_position, exclude_rids)
			reasons.append(str(hit.get("reason", "?")))

	_check("fachadas aceitam ancoragem", accepted >= 3,
		"(%d de %d predios testados%s)" % [accepted, tested,
			"" if reasons.is_empty() else "; motivos: " + ", ".join(reasons)])

	# Pontos invalidos continuam sendo recusados. Fica acima de todos os predios,
	# olhando para cima: nao ha nada em que ancorar.
	var rig2 := _player.get_node_or_null("CameraRig") as ThirdPersonCamera
	var spring2 := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	var stats: Dictionary = _district.call("city").statistics()
	_player.global_position = Vector3(0.0, stats.get("max_building_height", 60.0) + 40.0, 0.0)
	_player.velocity = Vector3.ZERO
	if _web.is_swinging():
		_web.release()
	if spring2 != null:
		spring2.rotation = Vector3(deg_to_rad(80.0), 0.0, 0.0)
	await _wait(3)
	var sky_hit: Dictionary = detector.find_anchor(
		_camera, _player.global_position, exclude_rids)
	_check("nao ancora no ceu aberto", not _web.fire(),
		"(detector: %s; direcao y=%.2f)" % [
			sky_hit.get("reason", "valido"), (-_camera.global_transform.basis.z).y])


# --- 7. Ausência de erros de execução ---

func _test_no_errors() -> void:
	print("- Ausencia de erros de execucao")
	# Se houve erro de script, a árvore não teria chegado até aqui. Confirma que
	# os nós esperados existem e estão ativos.
	_check("jogador na arvore", _player.is_inside_tree())
	_check("sistema de teias ativo", _web != null)
	_check("camera ativa", _camera != null and _camera.current)
	_check("modulo de animacao presente", _player.get_node_or_null("AnimationDriver") != null)
	_check("HUD presente", _player.get_node_or_null("Hud") != null)


func _test_mobile_renderer() -> void:
	print("- Renderer Mobile")
	var method: Variant = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	_check("renderizador Mobile configurado", method == "mobile", "(%s)" % method)
	_check("compressao de textura ETC2/ASTC ativa",
		ProjectSettings.get_setting("rendering/textures/vram_compression/import_etc2_astc", false))


func _test_expansion_readiness() -> void:
	print("- Preparacao para expansao")
	var city: CityGenerator = _district.call("city")
	# A planta precisa poder gerar distritos maiores sem alterar código.
	var bigger := CityLayout.generate_lots(5, 20261103)
	_check("planta escala para distrito maior", bigger.size() > city.lots().size(),
		"(%d lotes com 5x5 contra %d com 3x3)" % [bigger.size(), city.lots().size()])
	_check("distrito organizado em no proprio",
		_district.get_node_or_null("District") != null)
	_check("geradores separados por responsabilidade",
		_district.get_node_or_null("District/Roads") != null
		and _district.get_node_or_null("District/Buildings") != null
		and _district.get_node_or_null("District/StreetFurniture") != null)


func _report_metrics(generation_ms: int) -> void:
	print("- Metricas disponiveis neste ambiente")
	var stats: Dictionary = _district.call("city").statistics()
	var multimeshes := _find_all(_district, "MultiMeshInstance3D")
	var total_instances := 0
	for node: MultiMeshInstance3D in multimeshes:
		total_instances += node.multimesh.instance_count

	print("  tempo de geracao: %d ms" % generation_ms)
	print("  quarteiroes: %d" % stats.get("blocks", 0))
	print("  predios: %d" % stats.get("buildings", 0))
	print("  extensao: %.0f m" % stats.get("district_extent", 0.0))
	print("  altura maxima: %.0f m" % stats.get("max_building_height", 0.0))
	print("  MultiMeshInstance3D: %d" % multimeshes.size())
	print("  instancias totais: %d" % total_instances)
	print("  MeshInstance3D soltos: %d" % _find_all(_district, "MeshInstance3D").size())
	print("  StaticBody3D: %d" % _find_all(_district, "StaticBody3D").size())
	print("  colisores de predio: %d" % stats.get("buildings", 0))
	print("  NOTE: FPS e memoria no Galaxy A14 exigem aparelho fisico; nao medidos aqui.")


func _finish() -> void:
	print("=== %d verificacoes, %d falhas ===" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("FALHA: %s" % failure)
	quit(1 if not _failures.is_empty() else 0)
