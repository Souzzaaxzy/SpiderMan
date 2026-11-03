extends SceneTree
## Teste funcional da MISSÃO 002, executado no próprio motor.
##
## Não usa mocks: instancia a cena real do personagem e o cenário real, deixa a
## física rodar por vários frames e verifica o comportamento observado. Termina
## com código de saída 1 se qualquer verificação falhar.
##
## Uso: godot --headless --path . --script res://tools/tests/player_smoke_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ARENA_SCENE := "res://scenes/arena/test_arena.tscn"
const FALL_LIMIT := -25.0

## Faixa livre de obstáculos, entre as paredes em x=5 e x=-5.
const LANE_FREE := Vector3(0.0, 1.2, 8.0)
## Ponto de partida da rota de colisão: o prédio A ocupa z de -15 a -9 em x=-12.
const LANE_COLLISION := Vector3(-12.0, 1.2, -4.0)

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_run_tests()


func _run_tests() -> void:
	print("=== Teste funcional do personagem (MISSAO 002) ===")
	var arena := _spawn(ARENA_SCENE, Vector3.ZERO)
	var player := _spawn(PLAYER_SCENE, LANE_FREE)
	if player == null or arena == null:
		_fail("cenario ou personagem nao puderam ser instanciados")
		_finish()
		return

	await physics_frame
	await physics_frame

	await _test_gravity_and_landing(player)
	await _test_walk(player)
	await _test_run(player)
	await _test_jump(player)
	await _test_rotation(player)
	await _test_camera(player)
	await _test_collision(player)
	_test_arena_blocks(arena)
	await _test_hud(player)
	await _test_model(player)

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


## Avança N frames de física. Em headless a física roda em tempo real, então o
## progresso é contado em frames, não em segundos de parede.
func _wait_physics(frames: int) -> void:
	for _index: int in frames:
		await physics_frame


## Reposiciona o personagem na faixa livre e zera o estado, para cada teste
## começar do mesmo ponto sem depender do anterior. O yaw da câmera também volta
## a zero, porque o movimento é relativo à câmera.
func _reset(player: Node3D, position: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = position
	player.set_move_vector(Vector2.ZERO)
	player.set_run_held(false)
	var rig := player.get_node_or_null("CameraRig") as ThirdPersonCamera
	if rig != null:
		rig.set_yaw(0.0)
	await _wait_physics(45)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  [ok]    %s %s" % [label, detail])
	else:
		_fail("%s %s" % [label, detail])


func _fail(message: String) -> void:
	_failures.append(message)
	print("  [FALHA] %s" % message)


func _test_gravity_and_landing(player: Node3D) -> void:
	print("- Gravidade e aterrissagem")
	await _wait_physics(180)
	_check("personagem esta no chao", player.is_on_floor(), "(y=%.2f)" % player.position.y)
	_check("nao atravessou o chao", player.position.y > FALL_LIMIT)


func _test_walk(player: Node3D) -> void:
	print("- Caminhada")
	await _reset(player, LANE_FREE)
	player.set_move_vector(Vector2(0, -1))
	await _wait_physics(150)
	var speed: float = player.current_speed()
	_check("andando na velocidade configurada", absf(speed - player.walk_speed) < 0.8, "(%.2f m/s)" % speed)
	_check("avancou no eixo Z", player.velocity.z < -1.0, "(vz=%.2f)" % player.velocity.z)
	player.set_move_vector(Vector2.ZERO)


func _test_run(player: Node3D) -> void:
	print("- Corrida")
	await _reset(player, LANE_FREE)
	player.set_move_vector(Vector2(0, -1))
	player.set_run_held(true)
	await _wait_physics(150)
	var speed: float = player.current_speed()
	_check("correndo mais rapido que andando", speed > player.walk_speed + 0.5, "(%.2f m/s)" % speed)
	player.set_run_held(false)
	player.set_move_vector(Vector2.ZERO)
	await _wait_physics(90)
	_check("parou apos soltar o controle", player.current_speed() < 0.4, "(%.2f m/s)" % player.current_speed())


func _test_jump(player: Node3D) -> void:
	print("- Pulo")
	await _reset(player, LANE_FREE)
	var ground_y := player.position.y
	player.set_jump_requested()
	await _wait_physics(12)
	_check("subiu depois do pulo", player.position.y > ground_y + 0.2, "(dy=%.2f)" % (player.position.y - ground_y))
	_check("esta no ar", not player.is_on_floor())
	await _wait_physics(150)
	_check("voltou ao chao", player.is_on_floor(), "(y=%.2f)" % player.position.y)


func _test_rotation(player: Node3D) -> void:
	print("- Rotacao suave")
	await _reset(player, LANE_FREE)
	var visual := player.get_node_or_null("Visual") as Node3D
	_check("no Visual existe", visual != null)
	if visual == null:
		return
	visual.rotation.y = 0.0
	player.set_move_vector(Vector2(0, -1))
	await _wait_physics(60)
	_check("encarou a direcao do movimento", absf(visual.rotation.y) < 0.35, "(%.3f rad)" % visual.rotation.y)
	player.set_move_vector(Vector2.ZERO)
	await _wait_physics(60)


func _test_camera(player: Node3D) -> void:
	print("- Camera em terceira pessoa")
	var rig := player.get_node_or_null("CameraRig")
	var spring := player.get_node_or_null("CameraRig/SpringArm3D")
	var camera := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	_check("CameraRig existe", rig != null)
	_check("SpringArm3D existe", spring != null)
	_check("Camera3D existe e esta ativa", camera != null and camera.current)
	if rig == null:
		return
	var before: float = rig.rotation.y
	rig.add_look(Vector2(200, 0))
	await _wait_physics(5)
	_check("arrasto girou a camera", absf(rig.rotation.y - before) > 0.1, "(%.3f -> %.3f)" % [before, rig.rotation.y])
	_check("camera acompanha o personagem", rig.global_position.distance_to(player.global_position) < 2.0)


func _test_collision(player: Node3D) -> void:
	print("- Colisoes")
	await _reset(player, LANE_COLLISION)
	var start_z := player.position.z
	player.set_move_vector(Vector2(0, -1))
	await _wait_physics(240)
	_check("avancou em direcao ao predio", player.position.z < start_z - 2.0, "(%.1f -> %.1f)" % [start_z, player.position.z])
	_check("nao atravessou o predio A", player.position.z > -9.5, "(z=%.2f)" % player.position.z)
	_check("nao caiu do mundo", player.position.y > FALL_LIMIT)
	player.set_move_vector(Vector2.ZERO)
	await _reset(player, LANE_FREE)


func _test_arena_blocks(arena: Node3D) -> void:
	print("- Cenario de teste")
	var builder := arena.get_node_or_null("Layout")
	_check("construtor do cenario existe", builder != null)
	if builder == null:
		return
	_check("blocos declarados", builder.block_count() >= 10, "(%d)" % builder.block_count())
	var colliders := arena.get_node_or_null("Layout/Colliders")
	_check("colisoes criadas para os blocos", colliders != null and colliders.get_child_count() == builder.block_count())
	var visuals := arena.get_node_or_null("Layout/Blocks") as MultiMeshInstance3D
	_check("visuais em uma unica draw call", visuals != null and visuals.multimesh.instance_count == builder.block_count())
	_check("chao tem colisao", arena.get_node_or_null("Ground/Shape") != null)


func _test_hud(player: Node3D) -> void:
	print("- Controles touchscreen")
	var hud := player.get_node_or_null("Hud")
	_check("HUD existe", hud != null)
	if hud == null:
		return
	var joystick := hud.get_node_or_null("Root/Joystick") as TouchJoystick
	var look_area := hud.get_node_or_null("Root/LookArea") as TouchLookArea
	var jump := hud.get_node_or_null("Root/Actions/JumpButton") as Button
	var run := hud.get_node_or_null("Root/Actions/RunButton") as Button
	_check("joystick virtual existe", joystick != null)
	_check("area de toque da camera existe", look_area != null)
	_check("botao de pulo existe", jump != null)
	_check("botao de corrida existe", run != null)
	if joystick == null or look_area == null or jump == null or run == null:
		return

	# Tamanho fixo para o teste ser determinístico, independente do layout.
	joystick.size = Vector2(200, 200)

	# Toque para cima no joystick deve mover o personagem para frente.
	await _reset(player, LANE_FREE)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(100, 20)
	joystick._gui_input(touch)
	await _wait_physics(120)
	_check("toque no joystick moveu o personagem", player.current_speed() > 1.0, "(%.2f m/s)" % player.current_speed())

	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = Vector2(100, 100)
	joystick._gui_input(release)
	await _wait_physics(90)
	_check("soltar o joystick parou o personagem", player.current_speed() < 0.4)

	# A area de toque da camera deve repassar o arrasto para o CameraRig.
	# A sequência completa (toque, arrasto, soltar) é enviada como no aparelho.
	var rig := player.get_node_or_null("CameraRig")
	var before: float = rig.rotation.y
	var down := InputEventScreenTouch.new()
	down.index = 1
	down.pressed = true
	down.position = Vector2(200, 200)
	look_area._gui_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(280, 200)
	look_area._gui_input(drag)
	await _wait_physics(5)
	_check("arrasto na area de toque girou a camera", absf(rig.rotation.y - before) > 0.01, "(%.3f -> %.3f)" % [before, rig.rotation.y])
	var up := InputEventScreenTouch.new()
	up.index = 1
	up.pressed = false
	up.position = Vector2(280, 200)
	look_area._gui_input(up)

	# O botao de corrida deve acelerar o personagem.
	await _reset(player, LANE_FREE)
	run.toggled.emit(true)
	player.set_move_vector(Vector2(0, -1))
	await _wait_physics(150)
	_check("botao de corrida acelera o personagem", player.current_speed() > player.walk_speed + 0.5, "(%.2f m/s)" % player.current_speed())
	run.toggled.emit(false)
	player.set_move_vector(Vector2.ZERO)

	# Botao de pulo deve propagar para o controlador.
	await _reset(player, LANE_FREE)
	var ground_y := player.position.y
	jump.pressed.emit()
	await _wait_physics(12)
	_check("botao de pulo faz o personagem pular", player.position.y > ground_y + 0.2, "(dy=%.2f)" % (player.position.y - ground_y))


func _test_model(player: Node3D) -> void:
	print("- Modelo do personagem e esqueleto")
	var visual := player.get_node_or_null("Visual")
	_check("no Visual existe", visual != null)
	if visual == null:
		return

	var skeleton: Skeleton3D = null
	for node in _all(visual):
		if node is Skeleton3D:
			skeleton = node
			break
	_check("esqueleto importado", skeleton != null)
	if skeleton == null:
		return
	_check("esqueleto tem ossos", skeleton.get_bone_count() > 100, "(%d ossos)" % skeleton.get_bone_count())

	var meshes: Array[Node] = []
	for node in _all(visual):
		if node is MeshInstance3D:
			meshes.append(node)
	_check("malhas do personagem presentes", meshes.size() >= 1, "(%d malhas)" % meshes.size())

	var triangles := 0
	for node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var index_len: int = mesh.surface_get_array_index_len(surface)
			triangles += (index_len if index_len > 0 else mesh.surface_get_array_len(surface)) / 3
	_check("malha tem geometria", triangles > 1000, "(%d triangulos)" % triangles)

	# O modelo precisa encarar -Z (frente da Godot), senão anda de costas.
	# As lentes da máscara ficam na frente do rosto, então devem estar em -Z.
	var lens_z := _lens_forward_offset(player)
	_check("modelo virado para a frente (-Z)", lens_z < 0.0, "(lente em z=%.3f)" % lens_z)

	# Os clipes assados no .glb devem estar disponíveis e tocar conforme a ação.
	var animator := visual.get_node_or_null("Model/AnimationPlayer") as AnimationPlayer
	_check("AnimationPlayer importado", animator != null)
	if animator == null:
		return
	var clips := animator.get_animation_list()
	for expected: StringName in [&"idle", &"walk", &"run", &"jump"]:
		_check("clipe '%s' presente" % expected, clips.has(expected))

	# Parado: idle.
	await _reset(player, LANE_FREE)
	await _wait_physics(20)
	_check("parado toca 'idle'", animator.current_animation == &"idle", "(%s)" % animator.current_animation)

	# Andando: walk.
	player.set_move_vector(Vector2(0, -1))
	await _wait_physics(90)
	_check("andando toca 'walk'", animator.current_animation == &"walk", "(%s)" % animator.current_animation)

	# Correndo: run.
	player.set_run_held(true)
	await _wait_physics(120)
	_check("correndo toca 'run'", animator.current_animation == &"run", "(%s)" % animator.current_animation)
	player.set_run_held(false)
	player.set_move_vector(Vector2.ZERO)

	# Os ossos devem mudar de posição ao longo do clipe de caminhada.
	await _reset(player, LANE_FREE)
	player.set_move_vector(Vector2(0, -1))
	await _wait_physics(40)
	var foot := skeleton.find_bone("foot.l")
	_check("osso do pe existe", foot >= 0)
	var samples: Array[float] = []
	for _step in 12:
		samples.append(skeleton.get_bone_global_pose(foot).origin.z)
		await _wait_physics(6)
	player.set_move_vector(Vector2.ZERO)
	var smallest := samples[0]
	var largest := samples[0]
	for value in samples:
		smallest = minf(smallest, value)
		largest = maxf(largest, value)
	_check("pe se move ao andar", largest - smallest > 0.05, "(%.3f m de amplitude)" % (largest - smallest))


## Posição Z das lentes da máscara no espaço do jogador. Fica negativo quando o
## modelo encara -Z (frente na Godot).
func _lens_forward_offset(player: Node3D) -> float:
	var model := player.get_node_or_null("Visual/Model") as Node3D
	if model == null:
		return 0.0
	for node in _all(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var material_name := material.resource_name if material != null else ""
			if not material_name.begins_with("Lens"):
				continue
			# A malha do rig não tem transform próprio; a cadeia do modelo é que
			# posiciona tudo. Usa o centro da caixa delimitadora como referência.
			var local_center := mesh.get_aabb().get_center()
			return (model.global_transform * local_center).z - player.global_position.z
	return 0.0


func _all(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_all(child))
	return result


func _finish() -> void:
	print("=== %d verificacoes, %d falhas ===" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("FALHA: %s" % failure)
	quit(1 if not _failures.is_empty() else 0)
