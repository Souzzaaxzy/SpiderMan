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

### Características técnicas (verificadas nas páginas públicas)

| Item | Valor |
| --- | --- |
| Formatos | 2 × BLEND (4.2 e 5.0), 2 × FBX (um **rigged**, um sem rig), PNG 4K, EXR 8K |
| Tamanho | BLEND 592 MB · FBX 25,7 MB · PNG 126 MB · EXR 267 MB |
| Rig | Esqueleto baseado em **Mixamo**, com pesos ajustados e ossos de torção extras |
| Animações | **Nenhuma** (0 animações) |
| Malha | ~407.182 faces / ~209.205 vértices |
| Texturas | PBR: Base Color, Roughness, Metalness, Normal |
| Verificação | "Verified by CGTrader" no FBX (sem N-gons, geometria manifold, UV sem sobreposição) |

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
| MISSÃO 002: "não utilizar modelos substitutos" | Respeitada — nenhum substituto foi usado. |

**Decisão pendente do responsável pelo projeto.** Enquanto isso, o personagem em
execução usa um bloco de teste neutro, criado no projeto, que não deriva de
nenhum asset de terceiros.

### Situação do download

O download no CGTrader **exige conta autenticada**; não é acessível por link
direto a partir deste ambiente. Por isso os arquivos originais **não estão no
repositório**. Para prosseguir, é preciso que o responsável forneça o pacote
baixado e coloque em `assets/models/player/original/`.

---

## 2. Assets criados no projeto

| Asset | Origem | Licença |
| --- | --- | --- |
| `icon.svg` | criado no projeto | do projeto |
| Bloco de teste do personagem (`scenes/player/player.tscn`) | criado no projeto, primitivas da Godot | do projeto |
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
