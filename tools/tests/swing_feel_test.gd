extends SceneTree
## Testa o balanço de verdade: solta a teia no ponto baixo do arco e mede para
## onde o jogador vai. O defeito relatado era ser "puxado para o prédio" ao
## soltar, em vez de seguir em frente como no Spider-Man 2.
##
## Uso: godot --headless --path . --script res://tools/tests/swing_feel_test.gd

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DISTRICT_SCENE := "res://scenes/world/manhattan_district.tscn"
## Rua ao lado do prédio mais alto, com espaço para o arco.
const STREET_X := -28.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var district := (load(DISTRICT_SCENE) as PackedScene).instantiate()
	root.add_child(district)
	await physics_frame
	await physics_frame
	var city: CityGenerator = district.call("city")
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(player)
	await physics_frame
	await physics_frame

	var web := player.get_node_or_null("WebSwing")
	var camera := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	var spring := player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	var rig := player.get_node_or_null("CameraRig")

	print("############ SENSACAO DO BALANCO ############")

	# Lança em direção ao prédio mais alto, de cima, com velocidade horizontal.
	var lots: Array = city.lots()
	var tallest: CityLayout.Lot = lots[0]
	for lot: CityLayout.Lot in lots:
		if lot.height > tallest.height:
			tallest = lot

	# Corre para o norte (-Z), com o prédio à frente.
	var start := Vector3(STREET_X, 22.0, tallest.center.z + 30.0)
	player.global_position = start
	player.velocity = Vector3(0.0, 0.0, -9.0)
	player.swing_active = false
	if rig != null:
		rig.set_yaw(0.0)
	if spring != null:
		spring.rotation = Vector3(deg_to_rad(12.0), 0.0, 0.0)
	for _i in 3:
		await physics_frame

	var fired: bool = web.fire()
	print("disparou: %s" % fired)
	if not fired:
		print("nao ancorou; abortando")
		quit(1)
		return

	var anchor: Vector3 = web.current_anchor()
	print("ancora: %s  (jogador em %s)" % [anchor, player.global_position])
	var forward := Vector3(0.0, 0.0, -1.0)
	var to_anchor: Vector3 = anchor - player.global_position
	print("ancora esta a frente do movimento? %.2f (>0 = sim)" % forward.dot(
		Vector3(to_anchor.x, 0.0, to_anchor.z).normalized()))

	# Balança até o ponto mais baixo e solta ali.
	var lowest_y: float = player.global_position.y
	var release_at_lowest: bool = false
	var speed_at_lowest: float = 0.0
	for step in 200:
		await physics_frame
		if player.global_position.y < lowest_y - 0.01:
			lowest_y = player.global_position.y
			speed_at_lowest = player.velocity.length()
		# Solta quando começa a subir depois de ter descido bem.
		if lowest_y < start.y - 3.0 and player.velocity.y > 0.5:
			release_at_lowest = true
			break

	print()
	print("=== SOLTURA NO PONTO BAIXO DO ARCO ===")
	print("  desceu %.1f m  velocidade no ponto baixo: %.1f m/s" % [
		start.y - lowest_y, speed_at_lowest])

	var before: Vector3 = player.velocity
	var before_pos: Vector3 = player.global_position
	web.release()
	var after: Vector3 = player.velocity
	print("  velocidade antes:  (%.1f, %.1f, %.1f)  |%.1f|" % [before.x, before.y, before.z, before.length()])
	print("  velocidade depois: (%.1f, %.1f, %.1f)  |%.1f|" % [after.x, after.y, after.z, after.length()])

	# Para onde ele vai depois de soltar? Deveria ser para FRENTE (-Z), não para
	# o prédio.
	for _i in 60:
		await physics_frame
	var moved: Vector3 = player.global_position - before_pos
	print()
	print("=== TRAJETORIA APOS SOLTAR (1 s) ===")
	print("  deslocamento: (%.1f, %.1f, %.1f)" % [moved.x, moved.y, moved.z])
	var horizontal: Vector3 = Vector3(moved.x, 0.0, moved.z)
	if horizontal.length() > 0.1:
		var direction := horizontal.normalized()
		var toward_anchor := Vector3(to_anchor.x, 0.0, to_anchor.z).normalized()
		print("  seguiu %.1f graus na direcao da ancora (0 = direto para ela)" % rad_to_deg(
			direction.angle_to(toward_anchor)))
		print("  avancou no eixo Z: %.1f m (negativo = para frente)" % moved.z)
		print("  VEREDITO: %s" % ("segue em frente" if moved.z < -3.0 else "puxado para o predio"))

	quit(0)
