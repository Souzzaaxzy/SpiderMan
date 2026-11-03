# Sistema de movimentação

Documento da MISSÃO 005. Explica o diagnóstico, a física nova, a seleção
automática de alvos e o estado real das animações.

---

## 1. Diagnóstico: por que o jogador teleportava

Medido antes de qualquer alteração:

```
distancia ate a ancora no disparo: 8.46 m
corda definida: 3.36 m
SALTO no quadro do disparo: 3.363 m   <-- teletransporte
(a 20 m/s e 60 fps, o deslocamento normal por quadro e 0.33 m)
```

**Causa exata.** A corda era definida com 92% da distância, e o passo de física
fazia:

```gdscript
_controller.global_position = anchor + radial * length   # ANTES do move_and_slide
```

Com a âncora a 8,46 m e a corda a 3,36 m, esse ajuste arrancava o personagem
**3,36 m num único quadro**, impondo a posição antes de a física do corpo ter
chance de resolver qualquer colisão. Não era um "salto suave": era um
reposicionamento instantâneo.

### Os outros problemas medidos

| # | Problema | Medição |
| --- | --- | --- |
| 2 | Alterações diretas de posição | `global_position = ...` por quadro, antes do `move_and_slide` |
| 3 | Velocidade zerada? | **Não.** Preservada (8,00 → 8,00 m/s) |
| 4/5 | Exigia mirar | Sim: **um único raio** do centro da tela. Para o lado: `nada na mira` |
| 6 | Câmera interfere na física | Indiretamente: o disparo saía de um raio da câmera |
| 7 | Conflito com `CharacterBody3D` | A posição era imposta antes do `move_and_slide` |
| 8 | Rig | Íntegro: 366 ossos, 4 malhas |
| 9 | Animações | Apenas **4 clipes**: `idle`, `walk`, `run`, `jump`. Sem `AnimationTree` |
| 10 | Conflito animação × física | Não havia: o `AnimationPlayer` só trocava de clipe |

---

## 2. A física nova

### O que mudou

A corda **não move mais o jogador**. Ela devolve a velocidade corrigida, e quem
move o corpo é o `move_and_slide`, como em qualquer outro movimento.

O ciclo passou a ter três pontos, chamados pelo `PlayerController`:

| Gancho | Quando | O que faz |
| --- | --- | --- |
| `web_velocity_stepper` | antes do `move_and_slide` | Remove a componente radial de afastamento |
| `web_position_stepper` | **depois** | Corrige a posição, de forma **limitada** |
| `web_zip_stepper` | durante o impulso | Acelera na direção do alvo |

### O teto que acabou com o teletransporte

```gdscript
const MAX_POSITION_CORRECTION := 0.35   # metros por quadro
```

Por maior que seja o erro de distância, o jogador **nunca** é movido mais que
isso num quadro. O resto é resolvido nos quadros seguintes, suavemente, e a
correção passa pelo `move_and_collide`, que respeita as colisões.

**Resultado medido:** maior salto de **0,3513 m** por quadro (era 3,363 m).

### Sem tranco ao prender

```gdscript
length := WebPhysics.length_without_snap(body_position(), anchor)
```

O comprimento nasce **igual à distância**. Prender a teia não move o jogador nem
um milímetro: não há tranco nenhum no disparo.

### A corda só puxa

Enquanto o jogador está dentro do raio + folga (1,0 m), a corda está frouxa e só
a gravidade age. É o que dá a queda livre no início do balanço. Ao atingir o
limite, a componente de afastamento é absorvida em 88% — sobra um resíduo, que é
o que dá elasticidade em vez de um corte perfeitamente rígido.

### O arco não atravessa o chão

O fundo do arco é `anchor.y - comprimento`. Se isso ficar abaixo do piso, o
jogador é arrastado pelo chão. `safe_length()` encurta a corda para o arco caber
acima do piso, medido por um raio para baixo (funciona também no ar).

---

## 3. Seleção automática de alvos

### O problema

O detector antigo disparava **um raio** do centro da tela. Sem a câmera apontada
exatamente para o prédio, não havia teia.

### A solução

`WebTargetSelector` **varre um leque** de direções (5 na horizontal × 3 na
vertical = 15 raios, custo fixo) e pontua cada candidato.

| Critério | Peso | Por quê |
| --- | --- | --- |
| **Continuidade** | 1,0 | A âncora está à frente do movimento? É o que mais pesa |
| **Comprimento** | 0,8 | Faixa ideal de 14 a 42 m: nem arco lento nem balanço apertado |
| **Altura** | 0,6 | Ponto que gera arco útil, nem rasteiro nem pendurado |
| **Ganho de altura** | 0,5 | O arco passa por baixo e sobe do outro lado? |
| **Direção da câmera** | 0,25 | **Só desempata.** A câmera não é requisito |

O disparo funciona olhando para o lado e para o céu — medido nos testes.

As consultas de física são criadas uma vez e reutilizadas, e o arranjo de
candidatos é reaproveitado entre disparos: nada é alocado por quadro.

---

## 4. Web Zip

Impulso contínuo na direção de um alvo, escolhido pelo mesmo seletor.

A velocidade é decomposta em **ao longo do alvo** e **lateral**. A puxada
acelera só a primeira; a lateral é amortecida, não zerada — é o que preserva a
inércia em vez de transformar o zip num trilho.

**Medido:** deslocamento de 10,7 → 4,3 m até o alvo, maior salto de **0,4333 m**
por quadro, pico de 26 m/s. Sem teletransporte, e sem atravessar prédio.

Pode ser interrompido a qualquer momento (`cancel_zip()`).

**Point Launch não foi implementado** — apenas a arquitetura está preparada.

---

## 5. Animações: o que existe de verdade

### Situação real

O modelo traz **quatro** clipes, gerados por nós no Blender
(`tools/build_animations.py`): `idle`, `walk`, `run`, `jump`.

**Não foi possível baixar animações do Mixamo neste ambiente.** O Mixamo exige
login e não oferece download por URL direta. Nenhum arquivo de lá existe no
projeto, e nada aqui finge o contrário.

### O que foi feito

`PlayerAnimationController` é uma **máquina de estados** com 22 estados
declarados. Cada um resolve para um clipe, com alternativa quando o ideal não
existe:

```
[anim] clipes disponiveis: [idle, jump, run, walk]
[anim] estados com clipe proprio: 2 de 22
[anim] 20 estados rodando em clipe alternativo
[anim] nenhum estado ficou sem animacao (todos usam alternativa).
```

Ou seja: **os 22 estados funcionam**, mas 20 deles rodam com o clipe errado
(por exemplo, `sprint` usa o clipe de `run`). Isso é registrado, não escondido.

### Ajustes procedurais (IK)

`PlayerAnimationIK` aplica por cima do clipe:

- **braço do lado da teia** levanta na direção da ancoragem;
- **tronco** inclina conforme a aceleração;
- **pernas** recolhem no ar e no balanço.

São ajustes de **rotação**, limitados por export. O rig em disco **não é
alterado**: tudo é escrito no `Skeleton3D` em memória.

> Limite importante: `set_bone_pose_position` nos controles IK **não funciona**
> na Godot — quem obedece ao controle são as constraints, que não existem em
> glTF. Por isso todo ajuste aqui é de rotação.

### Arquivos que faltam

Ver [`ANIMATIONS.md`](ANIMATIONS.md) para a lista exata e o pipeline de
importação.

---

## 6. Câmera

- Comprimento do braço cresce com a velocidade (4,5 → 7,0 m).
- FOV abre com a velocidade (70° → 86°).
- Inclinação lateral nas curvas (até 8°).
- Alinhamento automático **só durante o balanço**, e devagar.
- Retorno suave ao repouso ao soltar.

**A câmera não escreve na física do jogador.** O teste compara dois cenários
idênticos (girando e não girando a câmera) e confirma que a diferença é nula.

---

## 7. Limites conhecidos

- **20 dos 22 estados usam clipe alternativo.** Precisa das animações do Mixamo.
- **A corda é reta.** Não simula catenária nem enrola.
- **Uma teia por vez.** A física já suporta duas (arranjo + laço), falta liberar
  o segundo disparo na entrada.
- **Wall Run, Wall Climb e Wall Jump não existem.** Os estados estão declarados e
  usam alternativa; a mecânica em si não foi implementada.
- **Point Launch não implementado**, só preparado.
- **FPS no Galaxy A14 não medido** — não há aparelho físico neste ambiente.
