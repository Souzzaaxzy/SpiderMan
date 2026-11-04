# Sistema de teias e balanço

Documento da MISSÃO 003. Explica a física, as decisões e os limites do sistema.

## Arquitetura

```
scenes/player/web_swing.tscn          # agrupa os três nós abaixo
src/web/
├── web_swing_controller.gd           # orquestra: disparo, estado, ajuste
├── web_anchor_detector.gd            # acha e valida o ponto de ancoragem
├── web_physics.gd                    # matemática pura do pêndulo (sem nós)
└── web_visual.gd                     # desenha a linha da teia
```

O sistema é um **filho do jogador** (`Player/WebSwing`), não parte do controlador.
O `PlayerController` só recebe duas coisas: um sinalizador `swing_active` e um
`Callable` (`web_stepper`) que ele chama dentro do próprio `_physics_process`.
Assim o `move_and_slide()` continua sendo responsabilidade do controlador, e o
sistema de teia não precisa assumir o movimento do personagem.

A física fica em `web_physics.gd`, que **não depende da árvore de nós**. Isso
permite testar a matemática diretamente, sem simular o motor.

## A física do balanço

Modelo: **pêndulo com corda**, com duas correções que fazem o balanço parecer
teia em vez de haste de metal.

A cada passo de física, depois da gravidade e antes do `move_and_slide`:

1. Se o jogador está **dentro** do raio da corda (comprimento + folga), a corda
   está frouxa e **nada acontece** — só a gravidade age.
2. Ao atingir o limite, a posição é corrigida para a esfera e a componente de
   afastamento da velocidade é absorvida.

A primeira etapa é o que dá a sensação de queda livre no início do balanço. A
segunda é o que faz a corda se comportar como corda: ela **não empurra**, e a
componente que aponta para dentro é preservada.

A gravidade continua sendo aplicada pelo controlador, todo quadro. É ela que
acelera o jogador ao longo do arco. Nada disso é animação: o movimento sai
inteiramente da integração da física.

### O arco não pode atravessar o chão

O fundo do arco é `anchor.y - comprimento`. Se isso ficar abaixo do piso, o
jogador é **arrastado pelo chão** em vez de balançar — foi exatamente o defeito
relatado. `WebPhysics.safe_length()` encurta a corda para o arco caber acima do
piso, com folga de 1,6 m. O piso é medido por um raio para baixo, o que funciona
também no ar (ao disparar depois de saltar de um telhado).

### A corda gira em volta do corpo

A restrição é aplicada ao **centro do corpo**, não aos pés. Pendurar pelo pé
fazia o personagem raspar no chão durante todo o arco.

### O que decorre do modelo, sem código extra

- **Velocidade máxima no ponto mais baixo.** Ali toda a altura já virou energia
  cinética. Medido no teste: 5 m/s no lançamento chegam a 17 m/s no arco.
- **Perda de altura na subida**, pela conservação de energia.
- **Inércia preservada ao soltar.** Como a restrição só age enquanto a teia está
  presa, ao soltar a velocidade simplesmente continua a que existia. O teste
  verifica isso: 11,964 m/s antes, 11,964 m/s depois.
- **Impulso ao recolher a teia.** `apply_length_change` preserva o momento
  angular (v · r constante), então encurtar a corda acelera o balanço — o
  "bombeio" natural.

### Estabilidade

- Velocidade limitada a **60 m/s** (`MAX_SPEED`). Em quadros longos — comuns em
  Android modesto — o passo grande poderia fazer o pêndulo divergir.
- Ao recolher, o ganho de velocidade por passo é limitado (`MAX_REEL_BOOST`).
- Comprimento mínimo de 1,5 m, para não dividir por zero nem colar a teia.

## Detecção de ancoragem

Um raio parte da câmera na direção em que o jogador olha. O ponto só é aceito se
passar por quatro validações:

| Validação | Motivo |
| --- | --- |
| Superfície é `StaticBody3D` | Não ancorar em outro personagem ou objeto móvel |
| Dentro de `max_distance` (60 m) | Alcance da teia |
| Pelo menos `min_rise` (1,5 m) acima do jogador | Sem subida não há arco, e a teia nasceria esticada |
| Linha de visão livre da altura do peito | Não prender atrás de parede |

O ponto de ancoragem recua **para fora** da superfície (no sentido da normal).
Recuar para dentro deixaria o ponto dentro do prédio e a checagem de visão
barraria o próprio alvo — foi um erro real durante o desenvolvimento.

A consulta de física (`PhysicsRayQueryParameters3D`) é **criada uma vez** e
reutilizada. Criar uma por disparo geraria lixo e travadas no Android.

## Representação visual

Um único `MeshInstance3D` com `CylinderMesh`, esticado por transformação. O nó é
escondido quando não há teia, então em repouso o custo é zero. Nada é criado ou
destruído durante o balanço — a mesma malha e o mesmo material são reusados. O
cilindro tem 6 segmentos e não projeta sombra.

## Câmera

O `ThirdPersonCamera` ganhou dois comportamentos, ativos **somente durante o
balanço**:

- **Distância dinâmica**: o braço vai de 4,5 m a 6,5 m conforme a velocidade, com
  aproximação suave para não dar solavanco.
- **Alinhamento**: a câmera vira devagar para a direção do movimento
  (`swing_align_speed = 1,6`), mantendo o controle manual do jogador.

Fora do balanço, o comportamento é idêntico ao de antes. O `SpringArm3D` continua
impedindo a câmera de atravessar paredes.

## Controles

| Ação | Toque | Teclado |
| --- | --- | --- |
| Teia (segurar/soltar) | botão **TEIA** | `E` |
| Recolher / afrouxar | controle deslizante | `R` / `F` |

O botão de teia funciona por **segurar**: pressionar dispara e mantém a teia
presa; soltar libera. Um botão só.

O controle deslizante vale −1 (afrouxar), 0 (manter) e +1 (recolher).

## Animação

### Braços caídos

O rig de repouso tem os braços abertos a **~55° da vertical** — é uma pose de T,
não de pessoa parada. Os clipes agora são gerados com os braços a **~18°**, isto
é, caídos ao lado do corpo (a mão fica 0,60 m abaixo do ombro, contra 0,41 m do
repouso).

Isso é feito em `tools/build_animations.py`, movendo o alvo IK de cada mão antes
de assar. **Precisa ser assado no Blender**: mexer no controle IK em tempo de
execução não funciona na Godot, porque quem obedece ao controle são as
constraints — e constraints não existem em glTF. Foi o erro que deixou os braços
travados.

### Postura de balanço

Por cima do clipe, o sistema aplica um ajuste **discreto** de tronco inclinado
16° e pernas recolhidas, entrando e saindo suavemente. Só a **rotação** é
ajustada aqui, porque `set_bone_pose_rotation` funciona em qualquer osso; a
posição dos controles IK não. O rig não é alterado em disco.

## Preparação para uma segunda teia

As ancoragens ficam em um arranjo (`_anchors`, `_rope_lengths`) e a física é
aplicada em laço sobre `_anchor_count`. Com duas teias, a posição passa a ser a
interseção de duas esferas. Hoje `fire()` só aceita um disparo por vez; habilitar
o segundo é uma questão de permitir um segundo disparo, não de reescrever a
física.

## Ajustes de sensação (nov/2026)

Três pedidos do responsável, todos medidos:

### A teia pega sempre no ponto mais próximo

Antes, a pontuação premiava "âncora à frente e longe", e o jogador encostado na
parede ficava sem teia. Agora o `WebTargetSelector`:

- varre **9×5 = 45 raios** numa abertura de 180° (antes 5×3 = 15, em 75°);
- aceita âncora a partir de **4 m** (antes 8 m), então encostado no prédio ainda
  há pontos válidos acima e ao lado;
- **restringe a escolha** aos candidatos dentro de 15% do ponto mais próximo que
  ainda renda arco (`nearest_window_ratio`). Se nenhum render arco, usa o mais
  próximo de qualquer forma — o disparo **nunca** falha por falta de alvo.

O Web Zip usa `prefer_nearest = false`: ali o objetivo é puxar o jogador para
longe, não para a parede ao lado.

### Mais longe da parede

`_push_away_from_wall()` lança um raio na direção do movimento durante o balanço
e, se achar parede perto, soma velocidade na direção da normal (para fora).
Medido: a distância mínima à fachada subiu para **9,8 m**.

### Vai mais para cima

O impulso de soltura ganhou uma componente vertical **base** (`swing_kick_up_base
= 4,5 m/s`) além da que vem da queda. Sair do ponto baixo do arco agora lança o
jogador para cima: medido, `vy` de −1,11 → **+3,73 m/s** ao soltar.

## Limites conhecidos

- **Uma teia por vez.** O segundo disparo está preparado na física, não na
  entrada.
- **A corda é reta.** Não simula catenária nem enrola; é uma linha esticada
  entre a mão e a âncora.
- **Sem animação dedicada de arremesso.** O braço sobe no clipe de pulo, mas não
  há um gesto específico de lançar a teia.
- **Sem animação dedicada** de disparo ou balanço; o ajuste é procedural.
- **A física é um pêndulo rígido**, não uma corda com elasticidade. É estável e
  previsível, mas não simula alongamento da teia.
- **A ancoragem exige superfície estática com colisão.** Ainda não há tratamento
  para ancorar em superfícies móveis (veículos, por exemplo).
