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

## Como o retargeting foi feito (reescrito em nov/2026)

O rig é *Rigify*: os ossos que **deformam a malha** são `thigh_stretch.l`,
`leg_stretch.l`, `foot.l`, `arm_stretch.l`, `forearm_stretch.l` — nenhum deles se
chamaria "coxa" ou "braço". Quem manda neles são as **279 constraints**, a partir
dos controles.

### Por que as versões anteriores deixavam o corpo dobrado

1. **Hierarquia partida.** No rig, os ossos de deformação **não são filhos uns
   dos outros**: `leg_stretch.l` é filho de `c_traj` (a raiz do rig), não de
   `thigh_stretch.l`. Sem as constraints, girar a coxa **não movia a perna**.
   Medido: o pé ia parar na **altura do peito** (z = 1,15 a 1,39 m no `walking`;
   1,6 a 2,3 m no `jog`). Era esse o "personagem todo bugado" — pernas dentro da
   barriga, braços na altura da cabeça, corpo flutuando.
2. **Espaço de coordenadas.** O armature do Mixamo está rotacionado 90° em X e
   com escala 0,01.

### O método que funciona

1. **Reconstruir a hierarquia** de deformação como uma cadeia humana limpa
   (`root → spine → shoulder → arm → forearm → hand`; `root → thigh → leg → foot
   → toes`). O reparenting **não altera** o `matrix_local`, então o bind da malha
   continua correto.
2. Copiar a **diferença de orientação** do Mixamo sobre o nosso repouso:
   `delta = pose_mixamo · repouso_mixamo⁻¹` e `alvo = delta · repouso_nosso`.
   Nessa forma as matrizes de espaço se cancelam.
3. Assar a pose avaliada em chaves.

Medido com o método novo (`walking`): pé alternando **0,09 a 0,39 m** do chão,
mãos caídas a ~1,1 m, cabeça estável a 1,85 m, corpo com 2,07 m de altura.

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

## Correção do "personagem tremendo" (nov/2026)

Dois defeitos faziam o corpo parecer "bugado", e os dois foram medidos e
corrigidos.

### 1. Quaternions com sinal trocado

O export do Blender grava `rotation_quaternion` quadro a quadro e pode gravar
`q` num quadro e `-q` no seguinte — mesma rotação, sinal oposto. A Godot importa
rotações de glTF como track de **valor bruto**, sem corrigir a continuidade, e o
osso interpola pelo **caminho longo** (~180°). Resultado: o membro "pula" de um
quadro para o outro.

Medido no canal `forearm.r`: **4 trocas de sinal** no `jog`, 4 no `swing_loop`;
**15.706 no total**, somando todos os clipes e canais.

Correção: `tools/fix_glb_quaternions.py` percorre cada canal de rotação e troca o
sinal quando `dot(anterior, atual) < 0`. Como `q` e `-q` são a mesma rotação,
**nenhuma pose muda** — só o caminho da interpolação. O `retarget_animations.py`
já chama o helper ao final do export.

### 2. O ponto de "walk" sumia do BlendSpace

O driver montava o BlendSpace passando o **nome do clipe** (`"walking"`) onde a
função esperava o **estado** (`"walk"`). O ponto do meio era descartado em
silêncio: o blend ficava só com `idle`/`jog`/`sprint`, e o andar virava uma
mistura instável entre idle e jog.

Medido: a mão direita dava saltos de **0,63 m por quadro** andando (a esquerda,
0,08 m). Depois da correção: **0,08 m nas duas**, simétrico. Há um teste de
regressão em `player_smoke_test.gd`.

## Cobertura dos estados

```
[anim] estados com clipe proprio: 13 de 21
[anim] 8 estados rodando em clipe alternativo
```

| Estado | Situação |
| --- | --- |
| `walk`, `jog`, `sprint`, `start_run`, `turn` | ✅ clipe próprio |
| `jump_start`, `land`, `land_roll` | ✅ clipe próprio |
| `swing_start`, `swing_loop`, `swing_release` | ✅ clipe próprio |
| `wall_run` | ✅ clipe próprio |
| `idle` | ✅ clipe próprio (gerado da pose neutra) |
| `jump_loop`, `fall`, `air_move` | ⚠️ usam `standing_jump` |
| `web_shoot_l`, `web_shoot_r`, `web_zip` | ⚠️ usam `swing_start` |
| `wall_climb`, `wall_jump` | ⚠️ usam `wall_run` / `standing_jump` |

Os 8 em alternativa **funcionam** — não ficam parados — mas com o clipe errado.
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

## Clipes gerados (nov/2026)

O pacote do Mixamo não trouxe `fall`, `jump_loop`, `air_move`, `wall_climb` nem
`wall_jump`. Eles são gerados por **pose procedural**
(`tools/add_generated_clips.py`) e adicionados ao `.glb` sem mexer nos outros.

Isso resolveu o defeito de o personagem abrir as pernas "como prancha" no ar: o
estado aéreo caía no `standing_jump`, que tem pose de agachamento com as pernas
afastadas. Medido: a abertura entre os pés chegava a **0,87 m**; agora é
**0,20 m** (e o pico é só a pose de impulso).

Cobertura: **18 de 21** estados com clipe próprio (antes 13).

## Escalada, corrida na parede e zip (nov/2026)

Três clipes refeitos/gerei por **pose procedural** (`tools/add_generated_clips.py`),
usando os eixos medidos no rig (o corpo encara -Y):

- **`wall_climb`** — membros alternando contra a fachada: o braço que alcança vai
  mais alto e mais esticado, a perna oposta dobra. Antes as pernas mal se moviam
  (amplitude ~0,02 m); agora alternam de verdade.
- **`wall_jump`** — sai do apoio e abre para a pose de salto no ar.
- **`web_zip`** — os dois braços à frente, corpo esticado na direção do voo
  (antes caía no `swing_start`).

Cobertura: **19 de 21** estados com clipe próprio (faltam só `web_shoot_l/r`).
