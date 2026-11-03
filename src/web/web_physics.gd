class_name WebPhysics
extends RefCounted
## Física da teia. Não depende de nós da árvore: só calcula.
##
## Modelo: **pêndulo com corda**, com duas correções que fazem o balanço parecer
## teia em vez de haste de metal:
##
## 1. **A corda só puxa, nunca empurra.** Enquanto o jogador está *dentro* do
##    raio da corda, ela está frouxa e não faz nada — só a gravidade age. Quando
##    ele chega ao limite, a corda trava e ele passa a girar no arco. É isso que
##    dá a sensação de queda livre no início do balanço.
## 2. **A corda absorve o tranco radial**, como uma corda de verdade esticando,
##    em vez de cortar a velocidade de forma perfeitamente rígida.
##
## Atenção à nomenclatura da Godot: `get_bone_global_pose` é relativo ao
## **esqueleto**, não ao mundo. O que este arquivo recebe já é posição de mundo.

## Velocidade máxima permitida, em m/s. Acima disso o passo é limitado, para o
## pêndulo não explodir em quadros longos (comum em Android modesto).
const MAX_SPEED := 60.0
## Distância mínima até a ancoragem. Evita divisão por zero e teia "colada".
const MIN_LENGTH := 2.0
## Quanto a velocidade pode crescer ao recolher a teia, por passo.
const MAX_REEL_BOOST := 1.35
## Fração da velocidade de afastamento que a corda absorve. Abaixo de 1.0 sobra
## um resíduo, que é o que dá a sensação de elasticidade no tranco.
const SNAP_DAMPING := 0.85


## Restringe o jogador à corda. Só age quando a corda está esticada.
##
## Devolve `[posição_corrigida, velocidade]`. Se o jogador está dentro do raio, a
## posição e a velocidade voltam intactas — a corda está frouxa e não interfere.
static func apply_rope_constraint(player_position: Vector3, velocity: Vector3,
		anchor: Vector3, length: float, slack: float = 0.0) -> Array:
	var offset := player_position - anchor
	var distance := offset.length()
	if distance < 0.0001:
		return [player_position, velocity]

	var limit := length + slack
	if distance <= limit:
		# Corda frouxa: não puxa nem empurra.
		return [player_position, velocity]

	var radial := offset / distance
	var corrected := anchor + radial * limit

	var radial_speed := velocity.dot(radial)
	var constrained := velocity
	if radial_speed > 0.0:
		constrained = velocity - radial * radial_speed * SNAP_DAMPING
	return [corrected, constrained]


## Ao mudar o comprimento, preserva o momento angular (v · r constante), que é o
## que dá o "impulso" de velocidade ao recolher a teia no meio do balanço.
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


## Velocidade tangencial (sem a componente radial), útil para medir o quanto o
## balanço está rendendo.
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
## altura mínima.
##
## O fundo do arco é `anchor.y - length`. Se isso ficar abaixo do chão, o jogador
## é arrastado por ele em vez de balançar — foi exatamente o defeito relatado.
## Esta função encurta a corda para o arco caber acima do piso.
static func safe_length(anchor: Vector3, desired_length: float,
		minimum_height: float) -> float:
	var available := anchor.y - minimum_height
	if available <= MIN_LENGTH:
		return MIN_LENGTH
	return clampf(minf(desired_length, available), MIN_LENGTH, available)


## Altura do ponto mais baixo que o arco alcança com esta corda.
static func arc_lowest_point(anchor: Vector3, length: float) -> float:
	return anchor.y - length
