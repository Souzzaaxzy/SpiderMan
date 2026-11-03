# Arquitetura — Spider-Man: New Life

Documento curto sobre as decisões técnicas da MISSÃO 001.

## Renderizador: Mobile, não Forward+

O projeto usa `renderer/rendering_method="mobile"` e importa texturas em
**ETC2/ASTC**. Motivos:

- Roda em GPUs móveis modestas sem exigir Vulkan de última geração.
- Menor consumo de memória de vídeo.
- Forward+ exige recursos que aparelhos de entrada não oferecem com folga.

## Resolução e orientação

- Viewport base **1280x720** com `stretch/mode="canvas_items"` e
  `stretch/aspect="expand"`, o que adapta a UI a diferentes proporções de tela.
- Orientação **paisagem** (`window/handheld/orientation=0`), confirmada no
  manifesto do APK (`android:screenOrientation="0"`).

## Arquitetura de módulos

```
GameBootstrap (scenes/boot/main.tscn)
   └── ModuleRegistry.register_builtin_modules()   # lista de módulos
   └── ModuleRegistry.boot_all(root)               # instancia cada módulo
          └── GameModule (classe base)             # um por sistema de gameplay
```

- `GameModule` é a classe base; cada módulo tem cena raiz própria.
- `ModuleRegistry` é o único ponto que conhece a lista de módulos. O núcleo não
  referencia tipos concretos de gameplay.
- Módulos são independentes: um sistema novo não altera os existentes.

Essa separação evita um único arquivo monolítico e permite desenvolver,
testar e desligar sistemas isoladamente.

## Estrutura de pastas

| Pasta | Responsabilidade |
| --- | --- |
| `scenes/boot/` | Cena inicial e cenas de nível. |
| `src/core/` | Núcleo: bootstrap e registro de módulos. |
| `src/modules/<id>/` | Um sistema de gameplay autocontido por pasta. |
| `assets/` | Arte, áudio, fontes. |
| `docs/` | Documentação. |
| `build/android/` | Saída de exportação (não versionada). |

## Exportação Android

- Sem `gradle_build` por padrão: usa os export templates prontos, mais rápido e
  sem exigir NDK na máquina.
- Arquiteturas `armeabi-v7a` + `arm64-v8a` cobrem a maioria dos aparelhos.
- `minSdk 24` (Android 7.0) para alcançar dispositivos mais antigos.
- Keystore de debug fica fora do repositório (`~/.android/debug.keystore`).

## Compatibilidade com dispositivos modestos

- Renderizador Mobile e texturas comprimidas.
- Planejamento de cena por chunks e `MultiMeshInstance3D` (MISSÃO 004) para
  reduzir draw calls.
- Nenhuma dependência além da própria Godot.

---

## Distrito urbano (MISSÃO 004)

Ver [`DISTRICT.md`](DISTRICT.md) para dimensões e números. Decisões de
arquitetura:

- **Dados separados da montagem.** `city_layout.gd` só calcula posições; não
  conhece nós. Isso permite testar a malha urbana sem instanciar geometria e
  deixa cada gerador livre para decidir como desenhar.
- **Um gerador por responsabilidade.** Ruas, prédios e mobiliário são nós
  independentes sob o distrito, então qualquer um pode ser trocado isoladamente.
- **O mundo expõe `spawn_position()`.** O módulo de gameplay não precisa saber
  como o distrito é construído para posicionar o jogador.
- **A arena de testes foi mantida.** `gameplay_module.gd` troca de região por
  `world_scene`, então sistemas isolados continuam testáveis na arena simples.
- **Prédios são `StaticBody3D`** porque é o tipo que o detector de teias aceita —
  a integração com a MISSÃO 003 é por tipo de colisão, não por código.

## Sistema de teias (MISSÃO 003)

Ver [`WEB_SWING.md`](WEB_SWING.md) para a física em detalhe. Resumo das decisões
que afetam a arquitetura:

- **A física é separada dos nós.** `web_physics.gd` só faz contas, então a
  matemática do pêndulo é testável sem simular o motor.
- **O controlador não foi reescrito.** O sistema de teia entra por dois pontos:
  um sinalizador `swing_active` e um `Callable` (`web_stepper`) chamado dentro do
  `_physics_process` do jogador. O `move_and_slide()` continua sendo dele.
- **Nada é alocado durante o balanço.** A consulta de física é criada uma vez e
  a malha da teia é reusada; em repouso o nó fica escondido, custo zero.
- **A câmera só muda durante o balanço.** Fora dele, o comportamento é idêntico
  ao da MISSÃO 002.

## Personagem e movimentação (MISSÃO 002)

### Divisão de responsabilidades

| Script | Papel |
| --- | --- |
| `src/player/player_controller.gd` | `CharacterBody3D`: velocidade, gravidade, pulo, rotação. |
| `src/player/player_animation.gd` | Escolhe o clipe pela velocidade e sincroniza a reprodução; modo procedural se não houver clipes. |
| `src/player/player_input.gd` | Registra as ações de teclado em tempo de execução. |
| `src/camera/third_person_camera.gd` | Pivô da câmera: yaw/pitch, limites e arrasto. |
| `src/ui/player_hud.gd` | Liga os controles de tela ao controlador e à câmera. |
| `src/ui/touch_joystick.gd` | Joystick virtual multitoque. |
| `src/ui/touch_look_area.gd` | Área de arrasto da câmera (metade direita). |

Nenhum script acumula dois sistemas: o controlador não sabe de UI, a UI não sabe
de física, e a câmera não conhece o modelo.

### Decisões que valem registrar

- **Movimento relativo à câmera.** A direção é calculada com o yaw do `CameraRig`,
  então "para frente" é sempre o que o jogador vê. Por isso a câmera fica como
  filha do corpo e o **corpo não gira** — só o nó `Visual` gira. Se o corpo
  girasse, a câmera giraria junto e o controle ficaria imprevisível.
- **Gravidade própria** (22 m/s²), maior que a da física. O pulo é resolvido por
  `v = sqrt(2 · g · h)`, o que dá altura previsível em vez de "empurrar" o
  personagem para cima.
- **`SpringArm3D`** cuida da colisão da câmera e da suavização, evitando escrever
  raycast manual.
- **HUD ancorado** (`anchor_*`), não posicionado em pixels: a interface se adapta
  à resolução e proporção da tela.
- **Cenário declarativo.** `arena_builder.gd` lê uma lista de blocos e gera um
  `MultiMeshInstance3D` (1 draw call para 14 blocos) mais um `StaticBody3D` com
  uma forma por bloco. É cenário de teste, não um sistema de mundo.
- **Otimização de texturas fora do motor.** `tools/optimize_textures.py` reduz
  para 1024 px e nunca escreve nos arquivos originais. EXR 8K é sinalizado para
  conversão manual, em vez de ser processado em tempo de execução no aparelho.
- **Animação assada no Blender, não por script.** O rig é *Rigify* em modo IK:
  os ossos que deformam a malha copiam a pose de controles (`c_foot_ik.*`,
  `c_hand_ik.*`, `c_root.x`) por **279 constraints**. Constraints não existem em
  glTF — ao importar, os braços e as pernas ficavam presos e nenhum comando os
  movia. Por isso `tools/build_animations.py` anima os controles no Blender (onde
  as constraints funcionam), assa o resultado em chaves dos 366 ossos e exporta
  quatro clipes. Na Godot apenas tocamos os clipes; nada de constraints.
- **Deslocamento em espaço mundial.** Os eixos locais dos controles IK estão
  rotacionados em relação ao mundo, então o script converte cada deslocamento com
  `matrix_local⁻¹ · delta` antes de aplicar. Sem isso, "mover o pé para frente"
  virava um movimento lateral.
- **Orientação do modelo.** O arquivo encara +Z no Blender→Godot, mas a frente na
  Godot é −Z. O nó `Visual/Model` recebe rotação de 180° em Y, e o teste funcional
  confere isso medindo a posição das lentes da máscara.
- **Loop dos clipes.** O glTF não guarda informação de repetição: o importador
  deixa tudo em "tocar uma vez". `player_animation.gd` marca os ciclos como
  `LOOP_LINEAR` e o pulo como `LOOP_NONE` na inicialização.
- **Conversão fora do Git.** Os brutos (FBX sem rig, `.blend` de 321 MB) não são
  versionados. `tools/build_animations.py` produz um `.glb` de 41 MB com as
  texturas otimizadas e as animações embutidas.

### Pendência do modelo

O modelo é uma réplica de personagem protegido (Marvel/Sony). Antes de publicar o
jogo, o personagem precisa ser substituído por um herói original — ver
`ASSET_LICENSE.md`.

`player_animation.gd` procura os clipes no `AnimationPlayer` do modelo e cai em
animação procedural se não os encontrar, então trocar o modelo não exige mexer no
controlador.
