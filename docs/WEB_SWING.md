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

Modelo: **pêndulo com corda inextensível**.

A cada passo de física, depois da gravidade e antes do `move_and_slide`:

1. O jogador é reposicionado sobre uma esfera de raio igual ao comprimento da
   teia em volta da ancoragem.
2. A componente da velocidade que aponta **para fora** dessa esfera é removida.

A segunda etapa é o que faz a corda se comportar como corda: ela **não empurra**.
A componente que aponta para dentro da esfera é preservada, então o jogador pode
cair e balançar livremente na direção da ancoragem.

A gravidade continua sendo aplicada pelo controlador, todo quadro. É ela que
acelera o jogador ao longo do arco. Nada disso é animação: o movimento sai
inteiramente da integração da física.

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
| Disparar teia | botão **Teia** | `E` |
| Soltar teia | botão **Soltar** | `Q` |
| Recolher / afrouxar | controle deslizante | `R` / `F` |

O controle deslizante vale −1 (afrouxar), 0 (manter) e +1 (recolher).

## Animação

O rig não tem clipes de disparo ou balanço. Em vez de inventar animação, o
sistema aplica um **ajuste procedural discreto** por cima do clipe em execução:
tronco inclinado 14° e pernas levemente recolhidas, entrando e saindo suavemente
(`swing_pose_blend_speed`). Os valores são baixos de propósito.

O rig **não é alterado em disco** — a pose é escrita em memória, no
`Skeleton3D`, a cada quadro. Quando existirem clipes de balanço de verdade,
basta trocá-los aqui.

## Preparação para uma segunda teia

As ancoragens ficam em um arranjo (`_anchors`, `_rope_lengths`) e a física é
aplicada em laço sobre `_anchor_count`. Com duas teias, a posição passa a ser a
interseção de duas esferas. Hoje `fire()` só aceita um disparo por vez; habilitar
o segundo é uma questão de permitir um segundo disparo, não de reescrever a
física.

## Limites conhecidos

- **Uma teia por vez.** O segundo disparo está preparado na física, não na
  entrada.
- **Sem animação dedicada** de disparo ou balanço; o ajuste é procedural.
- **A física é um pêndulo rígido**, não uma corda com elasticidade. É estável e
  previsível, mas não simula alongamento da teia.
- **A ancoragem exige superfície estática com colisão.** Ainda não há tratamento
  para ancorar em superfícies móveis (veículos, por exemplo).
