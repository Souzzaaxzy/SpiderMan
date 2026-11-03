# Animações: o que falta e como importar

Documento honesto sobre o estado das animações. **Nada aqui foi integrado ainda**
além dos quatro clipes que o próprio projeto gera.

---

## O que existe hoje

Quatro clipes, gerados por `tools/build_animations.py` e assados no `.glb`:

| Clipe | Uso |
| --- | --- |
| `idle` | Parado |
| `walk` | Caminhada |
| `run` | Corrida |
| `jump` | Pulo |

Esses quatro foram feitos por nós porque o rig é *Rigify em modo IK* e depende de
279 constraints que **não existem em glTF** — animar os ossos direto na Godot não
funciona. Ver `docs/WEB_SWING.md` para o detalhe.

---

## O que falta

A MISSÃO 005 pede 22 estados. **Dois têm clipe próprio; vinte rodam em
alternativa.** Os arquivos abaixo precisam ser fornecidos:

### Locomoção terrestre

| Estado | Arquivo esperado | Situação |
| --- | --- | --- |
| `idle` | — | ✅ próprio |
| `walk` | — | ✅ próprio |
| `jog` | `jog.fbx` | ⚠️ usa `run` |
| `sprint` | `sprint.fbx` | ⚠️ usa `run` |
| `start_run` | `start_run.fbx` | ⚠️ usa `walk` |
| `stop_run` | `stop_run.fbx` | ⚠️ usa `walk` |
| `turn` | `turn.fbx` | ⚠️ usa `walk` |

### Movimentação aérea

| Estado | Arquivo esperado | Situação |
| --- | --- | --- |
| `jump_start` | `jump_start.fbx` | ⚠️ usa `jump` |
| `jump_loop` | `jump_loop.fbx` | ⚠️ usa `jump` |
| `fall` | `fall.fbx` | ⚠️ usa `jump` |
| `land` | `land.fbx` | ⚠️ usa `jump` |
| `land_roll` | `land_roll.fbx` | ⚠️ usa `jump` |
| `air_move` | `air_move.fbx` | ⚠️ usa `jump` |

### Movimentação com teias

| Estado | Arquivo esperado | Situação |
| --- | --- | --- |
| `web_shoot_l` | `web_shoot_l.fbx` | ⚠️ usa `idle` |
| `web_shoot_r` | `web_shoot_r.fbx` | ⚠️ usa `idle` |
| `swing_start` | `swing_start.fbx` | ⚠️ usa `jump` |
| `swing_loop` | `swing_loop.fbx` | ⚠️ usa `jump` |
| `swing_release` | `swing_release.fbx` | ⚠️ usa `jump` |
| `web_zip` | `web_zip.fbx` | ⚠️ usa `jump` |

### Estruturas

| Estado | Arquivo esperado | Situação |
| --- | --- | --- |
| `wall_run` | `wall_run.fbx` | ⚠️ usa `run` (mecânica não implementada) |
| `wall_climb` | `wall_climb.fbx` | ⚠️ usa `walk` (mecânica não implementada) |
| `wall_jump` | `wall_jump.fbx` | ⚠️ usa `jump` (mecânica não implementada) |

---

## Por que o Mixamo não foi usado

A missão sugere o Mixamo como fonte principal. **Não foi possível baixar nada de
lá neste ambiente:**

- o Mixamo exige **login autenticado**;
- não oferece download por URL direta — o arquivo sai por um botão na interface,
  depois de escolher o formato;
- criar conta é uma ação que exige uma pessoa.

Nenhum arquivo do Mixamo existe no projeto, e o relatório não declara esses
estados como integrados.

---

## Como importar (pipeline pronto)

1. Baixe os FBX do Mixamo, escolhendo **FBX Binary** e **Without Skin**.
2. Coloque em `assets/animations/mixamo/`.
3. Nomeie cada arquivo conforme a coluna "Arquivo esperado" acima.
4. O `PlayerAnimationLibrary.detect_available()` passa a encontrá-los e o
   sistema os usa automaticamente — **nenhum código precisa mudar**.
5. Para o retargeting, o rig do modelo é o que vale: as animações do Mixamo usam
   esqueleto Mixamo, e o `SkeletonProfileHumanoid` da Godot resolve a
   correspondência. O mapeamento precisa ser conferido no editor.

> O rig do personagem **não deve ser substituído**. A missão proíbe isso, e o
> esqueleto de 366 ossos é o que sustenta os clipes já assados.

---

## O que o sistema faz enquanto isso

Os 22 estados **funcionam**: cada um resolve para um clipe existente via
`PlayerAnimationLibrary.resolve()`. A alternativa é declarada em `FALLBACKS` e
fica visível no console a cada execução:

```
[anim] estados com clipe proprio: 2 de 22
[anim] 20 estados rodando em clipe alternativo
```

Isso é melhor do que um estado que não toca nada, e deixa claro no relatório
exatamente o que falta.
