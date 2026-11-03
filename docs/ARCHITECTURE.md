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
- Planejamento de cena por chunks e `MultiMeshInstance3D` (MISSÃO 003) para
  reduzir draw calls.
- Nenhuma dependência além da própria Godot.

---

## Personagem e movimentação (MISSÃO 002)

### Divisão de responsabilidades

| Script | Papel |
| --- | --- |
| `src/player/player_controller.gd` | `CharacterBody3D`: velocidade, gravidade, pulo, rotação. |
| `src/player/player_animation.gd` | Escolhe a animação pela velocidade; modo procedural quando não há clipes. |
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

### Pendência do modelo

O modelo pedido é de um personagem protegido (ver `ASSET_LICENSE.md`) e o download
exige conta no CGTrader. O personagem em execução usa um bloco neutro criado no
projeto. `player_animation.gd` já detecta um `AnimationPlayer` com clipes: ao
importar o modelo, basta adicionar o nó com as animações nomeadas para o modo de
animação real entrar em uso, sem mudar o controlador.
