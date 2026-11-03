class_name WebPhysics
extends RefCounted
## Matemática do balanço por teia. Não depende de nós da árvore: só calcula.
##
## Modelo: **pêndulo com corda inextensível**. A cada passo o jogador é mantido
## sobre uma esfera de raio igual ao comprimento da teia em volta da ancoragem, e
## a componente da velocidade que aponta para fora dessa esfera é removida (uma
## corda não empurra). A gravidade, aplicada pelo controlador, acelera o jogador
## ao longo do arco.
##
## Consequências físicas que saem de graça desse modelo:
## - no ponto mais baixo do arco a velocidade é máxima;
## - subindo, a altura sobe e a velocidade cai;
## - soltar a teia não altera a velocidade, então o jogador continua o arco.

## Velocidade máxima permitida, em m/s. Acima disso o passo é limitado, para o
## pêndulo não explodir em quadros longos (comum em Android modesto).
const MAX_SPEED := 60.0
## Distância mínima até a ancoragem. Evita divisão por zero e teia "colada".
const MIN_LENGTH := 1.5
## Quanto a velocidade pode crescer ao recolher a teia, por passo.
const MAX_REEL_BOOST := 1.35


## Mantém o jogador sobre a esfera de raio `length` em volta de `anchor` e
## devolve a velocidade sem a componente radial de afastamento.
static func apply_rope_constraint(player_position: Vector3, velocity: Vector3,
		anchor: Vector3, length: float) -> Array:
	var offset := player_position - anchor
	var distance := offset.length()
	if distance < 0.0001:
		# Exatamente na ancoragem: empurra para baixo e segue.
		return [player_position, Vector3(0.0, -0.1, 0.0)]

	var radial := offset / distance
	var corrected := anchor + radial * length

	var radial_speed := velocity.dot(radial)
	var constrained := velocity
	if radial_speed > 0.0:
		# Só remove o afastamento: a corda não empurra nem freia o avanço.
		constrained = velocity - radial * radial_speed
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


## Altura relativa à ancoragem: negativa abaixo dela. O ponto mais baixo do arco
## é o mais negativo, e é onde a velocidade é maior.
static func height_below_anchor(player_position: Vector3, anchor: Vector3) -> float:
	return player_position.y - anchor.y
