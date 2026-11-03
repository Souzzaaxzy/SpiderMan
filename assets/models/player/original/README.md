# assets/models/player/original — modelo do personagem (arquivos brutos)

Este diretório guarda o **modelo original, sem nenhuma alteração**. Os arquivos
brutos não são versionados no Git (tamanho alto e direitos de terceiros); veja
`docs/ASSET_LICENSE.md`.

## O que precisa ser colocado aqui

O modelo pedido na MISSÃO 002 ainda **não foi baixado**, porque o download do
CGTrader exige uma conta logada. Veja a limitação completa em
[`../../../docs/ASSET_LICENSE.md`](../../../docs/ASSET_LICENSE.md).

Arquivos esperados, conforme a página do modelo (ID 6810626, autor Mr-P1138):

| Arquivo | Formato | Tamanho informado |
| --- | --- | --- |
| `<personagem>_rigged.fbx` | FBX binário, com esqueleto | 25,7 MB (os dois FBX juntos) |
| `<personagem>.fbx` | FBX binário, sem rig | (idem) |
| Texturas do traje | PNG 4K | 126 MB |
| Texturas EXR | EXR 8K | 267 MB |
| Cenas do Blender | BLEND 4.2 e 5.0 | 592 MB |

Prioridade: **FBX rigged** (item 2 da ETAPA 1).

## Estrutura de diretórios

```
assets/models/player/
├── original/    # cópia intacta do que o usuário fornecer (não editar)
└── optimized/   # saída de tools/optimize_textures.py (texturas 1024 px)
```

Nunca edite os arquivos de `original/`. Toda otimização escreve em `optimized/`.
