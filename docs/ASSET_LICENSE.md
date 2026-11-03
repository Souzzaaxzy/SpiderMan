# Licença e limitações dos assets de terceiros

Registro das licenças e — mais importante — das **limitações de uso** dos assets
externos. Este documento não é parecer jurídico.

---

## 1. Modelo do personagem (MISSÃO 002)

| Campo | Valor |
| --- | --- |
| Nome | *Black Suited Spider-Man 2007 Film Character* |
| Autor | Mr-P1138 |
| Origem | CGTrader, ID **6810626** |
| URL | https://www.cgtrader.com/free-3d-models/character/fantasy-character/black-suited-spider-man-2007-film-character |
| Publicado em | 2026-02-07 |
| Preço | Gratuito |
| Licença declarada | **Royalty Free License (no AI)** |
| Espelho do mesmo autor | Sketchfab, *Black Suited Spider-Man (2007; Spider-Man 3)*, marcado **CC Attribution** |
| Arquivos recebidos | Pasta no Google Drive fornecida pelo responsável do projeto |

### Características técnicas (verificadas por inspeção dos arquivos)

| Item | Valor |
| --- | --- |
| Malha | 407.182 triângulos / 342.745 vértices, 4 malhas (Body, Frames, Logos, Webs) |
| Materiais | 8 (BlackSuit, Soles, Lens, Frames, Glass, Logos, Web, WebBlack) |
| Texturas | 30 PNG, todas 4K (4096×4096) |
| Animações | **0** no arquivo; 4 geradas por `tools/build_animations.py` (`idle`, `walk`, `run`, `jump`) |
| Altura | 2,084 m, com os pés na origem |
| `blacksuit+no rig.fbx` | 3 malhas, **sem esqueleto** |
| `blacksuit+mixamo rig.fbx` | 1 malha, **sem esqueleto** (o nome não corresponde ao conteúdo) |
| `raimisuitblender5.0.blend` | **Contém o rig**: armature "rig" com **366 ossos**, 86 grupos de vértices com peso, texturas embutidas em 4K |

> **Achado importante:** apesar do nome, **nenhum dos dois FBX contém esqueleto** —
> verificado pela ausência de nós `Deformer`/`Skin`/`Cluster` no binário FBX. O rig
> existe apenas na cena do Blender, que é do tipo *Rigify* (ossos de controle
> `c_*` dirigindo ossos de deformação) e **não traz clipes de animação**.

### ⚠️ Limitações de uso — leia antes de usar

A licença do **arquivo** não concede direitos sobre o **personagem**. O modelo é
uma réplica do traje do filme *Spider-Man 3* (2007). Spider-Man é personagem de
propriedade da Marvel / Sony Pictures, protegido por direitos autorais e marcas
registradas. O autor Mr-P1138 não é titular desses direitos e, portanto, **não
pode licenciá-los**.

Consequências práticas:

1. A licença "Royalty Free" do CGTrader cobre apenas o que o vendedor possui. Os
   Termos e Condições do próprio CGTrader transferem ao comprador a
   responsabilidade de obter as liberações de terceiros necessárias
   (seções 3.6 e 20 dos termos).
2. **Não é seguro** distribuir, publicar, vender ou lançar um jogo contendo este
   modelo. Isso vale inclusive para builds públicos de teste.
3. **Uso aceitável:** prototipagem privada e não comercial, para validar
   movimentação, câmera e pipeline de importação.
4. O mesmo autor publica o arquivo no Sketchfab sob CC Attribution, o que
   **não muda** a situação: a licença do autor continua limitada ao que ele
   criou, não ao personagem.
5. A marca "Spider-Man" e a semelhança visual do traje são protegidas
   independentemente de quem modelou o arquivo.

### Conflito com as regras do projeto

| Regra do projeto | Situação com este modelo |
| --- | --- |
| MISSÃO 001: "não utilizar modelos ou personagens protegidos de terceiros" | **Conflita** — o modelo é de um personagem protegido. |
| MISSÃO 001: "super-herói aracnídeo original" | **Conflita** — o objetivo do projeto é um herói original. |

**Decisão do responsável pelo projeto:** o modelo foi fornecido explicitamente
para uso neste protótipo privado, ciente de que não pode ser publicado nem
distribuído. Enquanto o projeto estiver em prototipagem fechada, o uso é
adequado. **Antes de qualquer publicação, o personagem precisa ser substituído
por um herói original.**

### Arquivos e versionamento

Os arquivos brutos ficam em `assets/models/player/original/` e **não são
versionados** (`.gitignore`). O que entra no Git é apenas o `.glb` convertido
(`assets/models/player/spiderman_newlife.glb`), gerado por
`tools/build_animations.py`. As texturas otimizadas (1024 px) ficam embutidas nele.

---

## 2. Assets criados no projeto

| Asset | Origem | Licença |
| --- | --- | --- |
| `icon.svg` | criado no projeto | do projeto |
| Cenário de teste (`scenes/arena/test_arena.tscn`) | criado no projeto, primitivas da Godot | do projeto |
| Godot Engine 4.7.2 | godotengine.org | MIT |

---

## 3. Política para assets futuros

1. Registrar aqui todo asset externo: origem, autor, licença e limitações.
2. Preferir assets com licença compatível com uso comercial (CC0, MIT, ou
   licença comercial explícita).
3. Tratar a licença do arquivo e os direitos sobre personagem/marca como coisas
   distintas — a segunda sempre prevalece.
4. Nunca versionar arquivos de terceiros no repositório; manter em
   `assets/models/player/original/` (ignorado pelo Git).

