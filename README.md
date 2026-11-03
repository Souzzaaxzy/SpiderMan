# Spider-Man: New Life

Jogo 3D de mundo aberto para Android estrelado por um **super-herói aracnídeo
original**, ambientado em uma representação de Nova York. Construído com
**Godot 4.x** e **GDScript**, mirando o renderizador **Mobile** para rodar bem
em dispositivos Android modestos.

> **Estado atual — MISSÃO 003 (teias e balanço).**
> O personagem 3D está **importado, com esqueleto de 366 ossos e quatro
> animações** (`idle`, `walk`, `run`, `jump`), movimentação em terceira pessoa,
> controles touchscreen, câmera, pulo e um cenário de teste. Os clipes são
> gerados no Blender e assados no `.glb`, porque o rig depende de constraints
> que não existem em glTF.
>
> A **MISSÃO 003** acrescentou o sistema de teias: disparo com validação de
> ancoragem, balanço por pêndulo físico, soltura preservando a velocidade,
> linha visual da teia, câmera dinâmica e controles de toque. Veja
> [`docs/WEB_SWING.md`](docs/WEB_SWING.md).
>
> A **MISSÃO 004** substituiu a arena de testes por um **distrito urbano**:
> 9 quarteirões, 72 prédios de 12 a 78 m, ruas, calçadas, faixas de pedestres,
> telhados acessíveis e mobiliário urbano. Veja
> [`docs/DISTRICT.md`](docs/DISTRICT.md).
>
> A **MISSÃO 005** reformulou a movimentação: **fim do teletransporte** (salto
> por quadro caiu de 3,363 m para 0,351 m), **seleção automática de alvos** sem
> exigir mira, **Web Zip** por impulso contínuo, câmera com FOV e inclinação
> dinâmicos e uma máquina de 22 estados de animação. Veja
> [`docs/MOVEMENT.md`](docs/MOVEMENT.md).
>
> ⚠️ O modelo é uma réplica de personagem protegido (Marvel/Sony), fornecido para
> protótipo privado. **Não publicar nem distribuir.** Veja
> [`docs/ASSET_LICENSE.md`](docs/ASSET_LICENSE.md).

---

## Sumário

- [Requisitos](#requisitos)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Como executar](#como-executar)
- [Arquitetura modular](#arquitetura-modular)
- [Exportação Android (APK)](#exportação-android-apk)
- [Integração contínua (GitHub Actions)](#integração-contínua-github-actions)
- [Convenções](#convenções)
- [Documentos](#documentos)

---

## Requisitos

| Ferramenta | Versão usada na MISSÃO 001 | Observação |
| --- | --- | --- |
| Godot Engine | **4.7.2.stable** | Binário padrão (não Mono). |
| Export Templates | **4.7.2.stable** | Inclui `android_debug.apk` / `android_release.apk`. |
| JDK | **21** (OpenJDK 21.0.12.1) | Obrigatório para assinar o APK. |
| Android SDK | `platforms;android-34`, `build-tools;34.0.0` | `platform-tools` incluído. |
| Android NDK | `27.2.12479018` | Necessário apenas para build Gradle. |
| Git | qualquer versão recente | — |

Configuração de variáveis de ambiente para exportação:

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/caminho/para/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
```

---

## Estrutura do projeto

```
.
├── project.godot              # Configuração do projeto (Mobile, paisagem 1280x720)
├── export_presets.cfg         # Preset "Android" pronto para exportar APK
├── icon.svg                   # Emblema original do projeto
├── scenes/
│   ├── boot/
│   │   └── main.tscn          # Cena inicial: câmera + luz + bootstrap
│   ├── player/
│   │   └── player.tscn        # Personagem jogável (corpo, câmera, HUD de toque)
│   ├── world/
│   │   └── manhattan_district.tscn  # Primeira região urbana
│   └── arena/
│       └── test_arena.tscn    # Arena de testes (mantida para testes isolados)
├── src/
│   ├── core/                  # Núcleo: bootstrap, arquitetura de módulos, cenário
│   │   ├── game_bootstrap.gd
│   │   ├── module_registry.gd
│   │   ├── game_module.gd
│   │   └── arena_builder.gd
│   ├── player/                # Controlador e animação do personagem
│   │   ├── player_controller.gd
│   │   ├── player_animation.gd
│   │   └── player_input.gd
│   ├── camera/
│   │   └── third_person_camera.gd
│   ├── ui/                    # Controles touchscreen
│   │   ├── player_hud.gd
│   │   ├── touch_joystick.gd
│   │   └── touch_look_area.gd
│   ├── web/                   # Sistema de teias e balanço
│   │   ├── web_swing_controller.gd
│   │   ├── web_anchor_detector.gd
│   │   ├── web_physics.gd
│   │   └── web_visual.gd
│   ├── animation/             # Estados e ajustes procedurais
│   │   ├── player_animation_controller.gd
│   │   ├── player_animation_ik.gd
│   │   └── player_animation_library.gd
│   ├── world/                 # Região urbana
│   │   ├── world_manager.gd
│   │   ├── city_generator.gd
│   │   ├── city_layout.gd
│   │   ├── road_generator.gd
│   │   ├── building_generator.gd
│   │   ├── street_furniture.gd
│   │   └── facade.gdshader
│   └── modules/               # Um diretório por sistema de gameplay
│       └── gameplay/          # Instancia cenário + personagem no boot
├── assets/
│   └── models/player/
│       ├── spiderman_newlife.glb   # Personagem convertido (rig + malhas)
│       ├── original/               # Arquivos brutos recebidos (não versionados)
│       └── optimized/textures/     # Texturas reduzidas para 1024 px
├── tools/
│   ├── optimize_textures.py   # Reduz texturas para Android sem tocar no original
│   ├── build_animations.py    # Gera clipes no Blender e exporta o .glb
│   └── tests/                 # Teste funcional e inspeção, rodados pelo motor
├── docs/
│   ├── MOVEMENT.md            # Física, seleção de alvos e animações
│   ├── ANIMATIONS.md          # O que falta de animação e como importar
│   ├── ROADMAP.md
│   ├── ARCHITECTURE.md
│   ├── WEB_SWING.md           # Física e decisões do sistema de teias
│   ├── DISTRICT.md            # Dimensões e otimização da região urbana
│   └── ASSET_LICENSE.md       # Licenças e limitações dos assets externos
├── build/android/             # Saída dos APKs (não versionada)
└── .github/workflows/         # CI: headless + teste funcional + exportação de APK
```

---

## Como executar

Importar e abrir o projeto no editor:

```bash
godot --path .
```

Executar em modo **headless** (sem janela — usado pela CI):

```bash
godot --headless --path . --quit-after 10
```

Saída esperada:

```
Godot Engine v4.7.2.stable.official...
[gameplay] Personagem e cenario de teste carregados.
[bootstrap] Spider-Man: New Life v0.1.0 pronta. Modulos ativos: 1.
```

Rodar o teste funcional do personagem (física, movimentação, pulo, colisões e
controles de toque, no próprio motor):

```bash
godot --headless --path . --script res://tools/tests/player_smoke_test.gd
godot --headless --path . --script res://tools/tests/web_swing_test.gd
godot --headless --path . --script res://tools/tests/city_test.gd
```

Cada teste imprime suas verificações e termina com código de saída 1 se alguma
falhar. Hoje são 50 verificações do personagem, 82 da movimentação e 42 do
distrito urbano.

## Controles

| Ação | Touchscreen | Teclado (testes em desktop) |
| --- | --- | --- |
| Mover | joystick virtual (canto inferior esquerdo) | `W A S D` / setas |
| Girar a câmera | arrastar na metade direita da tela | botão direito do mouse |
| Pular | botão **Pular** | `Espaço` |
| Correr | botão **Correr** | `Shift` |
| Teia (segurar/soltar) | botão **TEIA** | `E` |
| Web Zip | botão **ZIP** | `C` |
| Ajustar comprimento | controle deslizante | `R` recolhe / `F` afrouxa |

## Otimização de texturas

```bash
python3 tools/optimize_textures.py plan  assets/models/player/original assets/models/player/optimized
python3 tools/optimize_textures.py apply assets/models/player/original assets/models/player/optimized
```

`plan` só relata; `apply` grava em `optimized/`. Os arquivos de `original/` nunca
são alterados. Texturas EXR são sinalizadas para conversão manual (o motor não
processa EXR 8K em tempo de execução no Android).

## Conversão e animação do modelo

O rig está na cena do Blender (os FBX fornecidos não têm esqueleto). Um único
script gera as animações e exporta o `.glb`:

```bash
python3 tools/build_animations.py <caminho>/raimisuitblender5.0.blend \
    assets/models/player/optimized/textures \
    assets/models/player/spiderman_newlife.glb
```

Requisitos: `pip install bpy` (o Blender como módulo Python). O script reponta as
texturas embutidas para as versões otimizadas, cria os clipes `idle`, `walk`,
`run` e `jump`, e assa a pose de todos os 366 ossos antes de exportar.

### Por que a animação é assada no Blender

O rig é *Rigify* em modo IK: os ossos que deformam a malha recebem a pose de
controles (`c_foot_ik.*`, `c_hand_ik.*`) através de **279 constraints**. Constraints
não existem em glTF, então na Godot esses ossos ficavam presos — os braços não
respondiam a nenhum comando. A solução é animar os controles no Blender, onde as
constraints funcionam, e **assar** o resultado em chaves de todos os ossos. Na
Godot só tocamos os clipes.

O `AnimationPlayer` do `.glb` fica em `Visual/Model/AnimationPlayer`.

---

## Arquitetura modular

O núcleo **não conhece** nenhum sistema de gameplay concreto. Cada sistema é um
módulo autocontido:

1. Crie a pasta `src/modules/<id>/` com a cena raiz estendendo `GameModule`.
2. Registre-a em `ModuleRegistry.register_builtin_modules()`:

   ```gdscript
   static func register_builtin_modules() -> void:
       register_module("gameplay", "res://src/modules/gameplay/gameplay_module.tscn")
   ```

3. O `game_bootstrap.gd` inicializa todos os módulos registrados no boot.

O módulo `gameplay` (MISSÃO 002) instancia o cenário de teste e o personagem.
Adicionar um sistema novo não exige alterar os módulos existentes.

Detalhes das decisões estão em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Exportação Android (APK)

O preset `Android` já está configurado com:

- **Orientação:** paisagem (`window/handheld/orientation=0`).
- **Renderizador:** Mobile (`renderer/rendering_method="mobile"`), nunca Forward+.
- **Arquiteturas:** `armeabi-v7a` e `arm64-v8a`.
- **minSdk:** 24 (Android 7.0) — amplia a compatibilidade com aparelhos modestos.
- **Pacote:** `com.yazzoki.spidermannewlife`.

Gerar o APK de debug:

```bash
godot --headless --path . --export-debug "Android" build/android/SpiderManNewLife.apk
```

> Para release, crie um keystore próprio e configure-o em
> **Editor → Editor Settings → Export → Android** antes de usar `--export-release`.

---

## Integração contínua (GitHub Actions)

| Workflow | Gatilho | O que faz |
| --- | --- | --- |
| `ci.yml` | push / pull request | Importa o projeto, valida execução headless, roda os testes do personagem, das teias e do distrito, e exporta um APK de debug como artefato. |

Os workflows baixam o Godot 4.7.2 e os export templates automaticamente, então
não exigem nenhum binário versionado no repositório.

---

## Convenções

- **Idioma do código:** nomes de arquivos e identificadores em inglês; comentários
  e documentação em português.
- **GDScript:** estilos seguem o guia oficial da Godot (`snake_case` para
  variáveis e funções, `PascalCase` para classes).
- **Um sistema por pasta:** evite arquivos monolíticos.
- **Assets de terceiros:** registrar licença e limitações em
  [`docs/ASSET_LICENSE.md`](docs/ASSET_LICENSE.md) antes de usar.

---

## Documentos

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — etapas de desenvolvimento.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — decisões técnicas.
- [`docs/WEB_SWING.md`](docs/WEB_SWING.md) — física do balanço e sistema de teias.
- [`docs/DISTRICT.md`](docs/DISTRICT.md) — dimensões e otimização do distrito urbano.
- [`docs/MOVEMENT.md`](docs/MOVEMENT.md) — física, seleção de alvos e animações.
- [`docs/ANIMATIONS.md`](docs/ANIMATIONS.md) — animações que faltam e como importar.
- [`docs/ASSET_LICENSE.md`](docs/ASSET_LICENSE.md) — licenças e limitações de uso.
