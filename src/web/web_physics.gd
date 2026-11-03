class_name WebPhysics
extends RefCounted
## Física da corda. Não depende de nós da árvore: só calcula.
##
## ## Por que a versão anterior teleportava
##
## A versão anterior fazia `player.global_position = anchor + radial * length`
## **antes** do `move_and_slide`. Quando a corda era definida com 3,36 m e o
## jogador estava a 8,46 m da âncora, esse ajuste arrancava o personagem 3,36 m
## de uma vez, num único quadro, sem que a física do corpo pudesse interferir.
## Medido: salto de **3,363 m por quadro** (o normal a 20 m/s é 0,33 m).
##
## ## O que esta versão faz em vez disso
##
## A restrição não move mais o jogador. Ela só **devolve a velocidade corrigida**:
## a componente que aponta para fora da esfera é removida (uma corda não empurra).
## Quem move o jogador é o `move_and_slide`, como em qualquer outro movimento.
## A posição só é corrigida por último recurso, quando o erro já é grande, e
## mesmo aí por um deslocamento pequeno e limitado por quadro.
##
## Consequência: o arco é resultado da integração da física, não de um
## reposicionamento. É o que dá a sensação de peso em vez de "deslizar no trilho".

## Velocidade máxima permitida, em m/s. Acima disso o passo é limitado, para a
## simulação não divergir em quadros longos (comum em Android modesto).
const MAX_SPEED := 60.0
## Distância mínima até a ancoragem. Evita divisão por zero e teia "colada".
const MIN_LENGTH := 2.0
## Quanto a velocidade pode crescer ao recolher a teia, por quadro.
const MAX_REEL_BOOST := 1.35
## Fração da velocidade de afastamento que a corda absorve no tranco. Abaixo de
## 1.0 sobra um resíduo, que é o que dá elasticidade em vez de corte rígido.
const SNAP_DAMPING := 0.88
## Correção máxima de posição por quadro, em metros. É o teto que impede o
## teletransporte: nenhum ajuste pode mover o jogador mais que isto de uma vez.
const MAX_POSITION_CORRECTION := 0.35
## A partir de quanto erro de distância a posição precisa ser corrigida.
const POSITION_TOLERANCE := 0.25


## Restringe o jogador à corda **sem mover a posição**.
##
## Devolve `[velocidade_corrigida, erro_de_distancia]`. O erro é positivo quando
## o jogador está além do alcance da corda. Quem decide o que fazer com o erro é
## o controlador: a posição é corrigida à parte, e sempre limitada.
##
## Enquanto o jogador está dentro do raio, nada é alterado: a corda está frouxa.
static func constrain_velocity(velocity: Vector3, player_position: Vector3,
		anchor: Vector3, length: float, slack: float = 0.0) -> Array:
	var offset := player_position - anchor
	var distance := offset.length()
	if distance < 0.0001:
		return [velocity, 0.0]

	var limit := length + slack
	var overshoot := distance - limit
	if overshoot <= 0.0:
		# Corda frouxa: não puxa nem empurra.
		return [velocity, overshoot]

	var radial := offset / distance
	var radial_speed := velocity.dot(radial)
	var constrained := velocity
	if radial_speed > 0.0:
		constrained = velocity - radial * radial_speed * SNAP_DAMPING
	return [constrained, overshoot]


## Correção de posição para trazer o jogador de volta ao alcance da corda.
##
## Devolve um deslocamento **limitado** por `MAX_POSITION_CORRECTION`. É o que
## impede o salto: por maior que seja o erro, o jogador nunca é movido mais que
## isso num quadro. O resto é resolvido nos quadros seguintes, suavemente.
static func position_correction(player_position: Vector3, anchor: Vector3,
		length: float, slack: float = 0.0) -> Vector3:
	var offset := player_position - anchor
	var distance := offset.length()
	if distance < 0.0001:
		return Vector3.ZERO

	var limit := length + slack
	var overshoot := distance - limit
	if overshoot <= POSITION_TOLERANCE:
		return Vector3.ZERO

	var radial := offset / distance
	var correction := -radial * minf(overshoot, MAX_POSITION_CORRECTION)
	return correction


## Ao mudar o comprimento, preserva o momento angular (v · r constante), que é o
## que dá o impulso de velocidade ao recolher a teia no meio do balanço.
static func apply_length_change(velocity: Vector3, old_length: float,
		new_length: float) -> Vector3:
	if new_length <= 0.0001 or is_equal_approx(old_length, new_length):
		return velocity
	var ratio := clampf(old_length / new_length, 1.0 / MAX_REEL_BOOST, MAX_REEL_BOOST)
	return velocity * ratio


## Limita a velocidade total para manter a simulação estável.
static func clamp_speed(velocity: Vector3, maximum: float = MAX_SPEED) -> Vector3:
	var speed := velocity.length()
	if speed > maximum:
		return velocity * (maximum / speed)
	return velocity


## Velocidade tangencial (sem a componente radial). É o que o balanço rende.
static func tangential_speed(velocity: Vector3, player_position: Vector3,
		anchor: Vector3) -> float:
	var offset := player_position - anchor
	if offset.length() < 0.0001:
		return velocity.length()
	var radial := offset.normalized()
	return (velocity - radial * velocity.dot(radial)).length()


## Altura relativa à ancoragem: negativa abaixo dela.
static func height_below_anchor(player_position: Vector3, anchor: Vector3) -> float:
	return player_position.y - anchor.y


## Comprimento de corda que faz o ponto mais baixo do arco ficar acima de uma
## altura mínima. Sem isto o arco desce abaixo do piso e o jogador é arrastado.
static func safe_length(anchor: Vector3, desired_length: float,
		minimum_height: float) -> float:
	var available := anchor.y - minimum_height
	if available <= MIN_LENGTH:
		return MIN_LENGTH
	return clampf(minf(desired_length, available), MIN_LENGTH, available)


## Altura do ponto mais baixo que o arco alcança com esta corda.
static func arc_lowest_point(anchor: Vector3, length: float) -> float:
	return anchor.y - length


## Comprimento de corda que faz o arco passar pela posição atual do jogador, sem
## puxá-lo. Usado ao prender a teia: o comprimento nasce igual à distância, então
## **não há tranco nenhum** no momento do disparo.
static func length_without_snap(player_position: Vector3, anchor: Vector3,
		minimum: float = MIN_LENGTH) -> float:
	return maxf(player_position.distance_to(anchor), minimum)


## Altura de recuperação: quanto o jogador subiria ao percorrer o arco até o
## outro lado. Serve para pontuar se a ancoragem vai render deslocamento.
static func potential_height_gain(player_position: Vector3, anchor: Vector3,
		length: float) -> float:
	var lowest := arc_lowest_point(anchor, length)
	return maxf(0.0, lowest - player_position.y)
