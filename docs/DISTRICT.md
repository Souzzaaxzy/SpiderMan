# Distrito de Manhattan

Documento da MISSÃO 004: a primeira região urbana explorável.

## Arquitetura

```
scenes/world/manhattan_district.tscn   # ponto de entrada da região
src/world/
├── world_manager.gd       # ambiente, luz, organização; expõe spawn_position()
├── city_generator.gd      # orquestra os geradores e cria as colisões
├── city_layout.gd         # planta: só calcula posições, não cria nós
├── road_generator.gd      # ruas, calçadas, faixas de pedestres, limites
├── building_generator.gd  # corpos, telhados, detalhes de cobertura
├── street_furniture.gd    # postes, semáforos, placas, hidrantes
└── facade.gdshader        # janelas procedurais em espaço de mundo
```

A separação principal é entre **dados** (`city_layout.gd`) e **montagem**. A
planta não conhece nós, então a malha urbana pode ser testada e ampliada sem
instanciar geometria — e o gerador decide livremente como desenhar cada peça.

## Dimensões

| Medida | Valor |
| --- | --- |
| Quarteirões | 3 × 3 = **9** |
| Prédios | **72** (8 por quarteirão) |
| Quarteirão | 42 × 42 m |
| Rua | 14 m de largura |
| Calçada | 3 m |
| Passo entre quarteirões | 56 m |
| Extensão do distrito | **182 m** |
| Piso total (com margem) | 302 m |
| Altura dos prédios | **12 m a 78 m** |

As alturas crescem em direção ao centro (expoente 1,6 sobre a centralidade), com
variação de ±22% por lote. Isso dá uma silhueta de Manhattan em vez de um platô.

## Otimização

O custo de renderização foi o critério principal das decisões.

| Técnica | Onde | Resultado |
| --- | --- | --- |
| MultiMesh | corpos, lajes, parapeitos, detalhes, calçadas, marcas, mobiliário | **12 MultiMesh** para 1248 objetos |
| Material único | corpos dos prédios | 1 material para 72 prédios |
| Shader procedural | fachadas | janelas sem nenhuma textura |
| Sem textura 4K | toda a cidade | só cores e material padrão |
| Sem colisão em decoração | postes, placas, hidrantes, marcas | física só nos prédios e no piso |
| Sombras curtas | luz solar | alcance de 90 m, ortogonal |
| Névoa | ambiente | esconde o limite do distrito |

**Uma única `MeshInstance3D` solta** em todo o distrito (o piso). Todo o resto é
MultiMesh ou nó vazio. Os 72 corpos de prédio saem em **1 draw call**.

### O shader de fachada

As janelas são calculadas no fragmento, a partir da **posição de mundo**:

```glsl
vec2 plane = mix(vec2(world_position.x, world_position.z),
        vec2(world_position.x + world_position.z, world_position.y), vertical);
```

Isso resolve dois problemas de uma vez: a mesma malha de caixa serve para as
quatro faces de prédios de qualquer tamanho, e não há UV para gerar nem textura
para amostrar. O custo por fragmento não depende do tamanho do prédio.

Um hash barato decide quais janelas ficam acesas, com resultado **estável** —
sem cintilação entre quadros.

## Colisões

- **Piso**: uma caixa grossa de 20 m, cobrindo o distrito mais 60 m de margem.
- **Prédios**: um `StaticBody3D` com uma caixa por prédio, do chão ao topo.
- **Limites do mundo**: quatro paredes invisíveis de 400 m na borda da região.
- **Decoração**: nenhuma colisão.

Os prédios são `StaticBody3D` de propósito: é o tipo que o `WebAnchorDetector`
aceita, então **as fachadas e os telhados são superfícies válidas de ancoragem**.

### Duas armadilhas encontradas

1. **Meio-fio com colisão trava o jogador.** Um degrau de 15 cm na guia da
   calçada deixa o `CharacterBody3D` preso, porque ele não sobe degraus sozinho.
   A calçada virou faixa visual sem colisão, e o piso ficou todo nivelado em y=0.
   A diferença rua/calçada é lida pelo material.
2. **Piso fino sofre tunneling.** Uma caixa de 1 m é atravessada a 7 m/s antes de
   a colisão ser detectada, e o jogador cai pelo chão. Daí a espessura de 20 m.

## Iluminação e atmosfera

Céu procedural, luz solar em 48° com sombras ortogonais de alcance curto,
ambiente vindo do céu e névoa leve. A base está pronta para um ciclo de dia/noite
— bastaria animar a rotação do sol e as cores do céu — mas **não há sistema de
clima nem ciclo implementado** nesta missão.

## Métricas medidas

| Métrica | Valor |
| --- | --- |
| Tempo de geração | **6–7 ms** |
| MultiMeshInstance3D | 12 |
| Instâncias totais | 1248 |
| MeshInstance3D soltas | 1 |
| StaticBody3D | 3 |
| Colisores de prédio | 72 |

> **FPS e memória no Galaxy A14 não foram medidos.** Não há aparelho físico neste
> ambiente. Os números acima são de geometria e tempo de geração, que são
> mensuráveis aqui. Qualquer valor de FPS seria inventado.

## Como ampliar

`city_layout.generate_lots(n)` já escala: com 5×5 são 200 lotes, sem alterar
código. Para uma região maior, basta aumentar `blocks_per_side` no
`world_manager.gd`. A organização por geradores separados permite trocar as ruas
ou os prédios isoladamente.

## Limites conhecidos

- **Sem LOD.** Todos os prédios são desenhados sempre. Com 72 prédios em um
  distrito pequeno o custo é aceitável; em uma região grande, será necessário.
- **Sem occlusion culling.** A névoa disfarça, mas a geometria atrás do jogador
  continua sendo processada.
- **Sem carregamento por região.** Tudo é gerado de uma vez no boot. A
  organização em `District` prepara o terreno, mas o streaming não existe.
- **Colisão de prédio é uma caixa simples.** Detalhes de cobertura não têm
  colisão, então o jogador anda por cima deles.
- **Fachada é um shader, não arte.** Não há vitrines, letreiros ou variação real
  de material entre prédios — só cor e padrão de janela.
