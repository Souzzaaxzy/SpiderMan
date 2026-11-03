# Spider-Man: New Life

Jogo 3D de mundo aberto para Android estrelado por um **super-herói aracnídeo
original**, ambientado em uma representação de Nova York. Construído com
**Godot 4.x** e **GDScript**, mirando o renderizador **Mobile** para rodar bem
em dispositivos Android modestos.

> **Estado atual — MISSÃO 001 (preparação técnica).**
> Este repositório contém apenas a infraestrutura: projeto Godot configurado,
> cena de boot executável, arquitetura modular, exportação Android funcionando e
> automação de CI. **Nenhum sistema de gameplay foi implementado** — isso
> aguarda aprovação explícita.

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
│   └── boot/
│       └── main.tscn          # Cena inicial: Camera3D + luz + bootstrap
├── src/
│   ├── core/                  # Núcleo: bootstrap e arquitetura de módulos
│   │   ├── game_bootstrap.gd
│   │   ├── module_registry.gd
│   │   └── game_module.gd
│   └── modules/               # Um diretório por sistema de gameplay (vazio por ora)
├── assets/                    # Arte, áudio e fontes do jogo
├── docs/
│   ├── ROADMAP.md             # Etapas de desenvolvimento
│   └── ARCHITECTURE.md        # Decisões de arquitetura
├── build/android/             # Saída dos APKs (não versionada)
└── .github/workflows/         # CI: validação headless + exportação de APK
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
[bootstrap] Spider-Man: New Life v0.1.0 pronta. Modulos ativos: 0.
```

---

## Arquitetura modular

O núcleo **não conhece** nenhum sistema de gameplay concreto. Cada sistema é um
módulo autocontido:

1. Crie a pasta `src/modules/<id>/` com a cena raiz estendendo `GameModule`.
2. Registre-a em `ModuleRegistry.register_builtin_modules()`:

   ```gdscript
   static func register_builtin_modules() -> void:
       register_module("player", "res://src/modules/player/player_module.tscn")
   ```

3. O `game_bootstrap.gd` inicializa todos os módulos registrados no boot.

Adicionar um sistema novo não exige alterar os módulos existentes. A lista de
módulos está intencionalmente vazia na MISSÃO 001.

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
| `ci.yml` | push / pull request | Valida o projeto Godot em headless e faz a exportação de um APK de debug como artefato. |

Os workflows baixam o Godot 4.7.2 e os export templates automaticamente, então
não exigem nenhum binário versionado no repositório.

---

## Convenções

- **Idioma do código:** nomes de arquivos e identificadores em inglês; comentários
  e documentação em português.
- **GDScript:** estilos seguem o guia oficial da Godot (`snake_case` para
  variáveis e funções, `PascalCase` para classes).
- **Um sistema por pasta:** evite arquivos monolíticos.
- **Direitos autorais:** não incluir modelos, personagens ou marcas de terceiros.

---

## Documentos

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — etapas de desenvolvimento.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — decisões técnicas.
