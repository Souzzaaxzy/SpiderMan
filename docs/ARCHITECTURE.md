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
