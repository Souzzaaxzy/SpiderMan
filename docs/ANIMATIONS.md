# Animações: o que está integrado e o que falta

Estado real das animações, sem maquiagem.

---

## O que está integrado

**15 clipes**, retargeted das animações do Mixamo que o responsável subiu em
`assets/animations/mixamo/`. O retargeting é feito por
`tools/retarget_animations.py` e assado no `.glb`.

| Clipe no jogo | Origem (Mixamo) |
| --- | --- |
| `walking` | Walking.fbx |
| `jog` | Running.fbx |
| `sprint` | Running.fbx |
| `start_run` | Start Walking.fbx |
| `turn` | Walking Turn 180.fbx |
| `standing_jump` | Standing Jump.fbx |
| `falling_to_landing` | Falling To Landing.fbx |
| `land_roll` | Falling To Roll.fbx |
| `swing_start` | Start Swinging.fbx |
| `swing_loop` | Swinging.fbx |
| `swing_release` | Swing To Land.fbx |
| `swing_to_land` | Swing To Land (1).fbx |
| `swing_into_wall` | Swing Into Wall.fbx |
| `wall_run` | Wall Run.fbx |
| `low_crawl` | Low Crawl.fbx |

## Como o retargeting foi feito

O rig é *Rigify em modo IK*: os ossos que **deformam a malha** são
`thigh_stretch.l`, `leg_twist_2.l`, `foot.l`, `arm_stretch.l`,
`forearm_twist_2.l` — nenhum deles se chamaria "coxa" ou "braço". Quem manda
neles são as **279 constraints**, a partir dos alvos IK.

Duas tentativas falharam, e as duas foram medidas:

1. **Copiar rotação osso a osso.** O pé movia **0,000 m** com as constraints
   ativas: a `COPY_ROTATION` sobrescrevia o que eu escrevia.
2. **Assar sem selecionar o rig.** O `nla.bake` opera sobre o **objeto ativo**,
   que no fluxo completo é o esqueleto do Mixamo recém-importado. O clipe saía
   com 2 quadros e nenhum movimento.

O método que funciona — e que já era usado nas MISSÕES 002 e 003 — é **mover os
alvos IK** (`c_foot_ik.*`, `c_hand_ik.*`) e o quadril para as posições do Mixamo,
deixar as constraints resolverem, e assar. Medido depois: o pé move **1,34 m** no
`walking` e **1,86 m** no `swing_loop`.

**Root motion é descartado.** Os clipes do Mixamo andam sozinhos (o `Walking`
percorre 1,79 m); a missão pede animações *in-place*, porque quem move o
personagem é a física. Só a oscilação vertical do quadril é preservada, que é o
que dá peso ao passo.

## Cobertura dos estados

```
[anim] estados com clipe proprio: 12 de 21
[anim] 9 estados rodando em clipe alternativo
[anim] nenhum estado ficou sem animacao (todos usam alternativa).
```

| Estado | Situação |
| --- | --- |
| `walk`, `jog`, `sprint`, `start_run`, `turn` | ✅ clipe próprio |
| `jump_start`, `land`, `land_roll` | ✅ clipe próprio |
| `swing_start`, `swing_loop`, `swing_release` | ✅ clipe próprio |
| `wall_run` | ✅ clipe próprio |
| `idle` | ⚠️ usa `walking` |
| `jump_loop`, `fall`, `air_move` | ⚠️ usam `standing_jump` |
| `web_shoot_l`, `web_shoot_r`, `web_zip` | ⚠️ usam `swing_start` |
| `wall_climb`, `wall_jump` | ⚠️ usam `wall_run` / `standing_jump` |

Os 9 em alternativa **funcionam** — não ficam parados — mas com o clipe errado.
O console registra quais são a cada execução.

## O que ainda falta

Estes arquivos não vieram no pacote e resolveriam os 9 estados em alternativa:

| Estado | Arquivo sugerido (Mixamo) |
| --- | --- |
| `idle` | Idle |
| `jump_loop` | Falling Idle |
| `fall` | Falling |
| `air_move` | Flying / Air Move |
| `web_shoot_l`, `web_shoot_r` | Throwing (ou gravação própria) |
| `web_zip` | Pull Up / Web Zip |
| `wall_climb` | Climbing |
| `wall_jump` | Wall Jump |

Basta colocar os FBX em `assets/animations/mixamo/` e acrescentar a linha
correspondente em `CLIP_SOURCES`, dentro de `tools/retarget_animations.py`. O
sistema os encontra sem mudar mais nada.

## Nomes alternativos

O glTF traz `swing_loop`, mas o importador da Godot entrega **`swing`** —
verificado no log. A biblioteca aceita os dois, via `ALIASES`, em vez de depender
do nome exato.

## Licença

As animações vêm do **Mixamo** (Adobe). O uso é gratuito para projetos, com as
restrições da licença Adobe: não redistribuir os arquivos como asset isolado.
Os FBX originais ficam em `assets/animations/mixamo/`; o que entra no jogo é o
resultado do retargeting, assado no `.glb`.
