# Roadmap — Spider-Man: New Life

Etapas planejadas. Cada etapa só começa após aprovação da anterior. A
**MISSÃO 001** é a única concluída até agora.

Legenda: ✅ concluído · ⏳ aguardando aprovação · ⬜ não iniciado

---

## MISSÃO 001 — Preparação técnica ✅

- [x] Inspeção do ambiente (CPU, RAM, disco, SO).
- [x] Verificação de Godot 4, export templates, JDK e Android SDK.
- [x] Estrutura de diretórios organizada.
- [x] Repositório Git e remoto configurados.
- [x] `README.md` documentando o projeto.
- [x] Projeto Godot configurado para paisagem e renderizador Mobile.
- [x] Cena inicial vazia, funcional e executável (headless confirmado).
- [x] Arquitetura modular preparada (`ModuleRegistry` + `GameModule`).
- [x] `docs/ROADMAP.md`.
- [x] Exportação de APK de debug funcionando.
- [x] GitHub Actions para validação e exportação.

---

## MISSÃO 002 — Personagem 3D e movimentação ✅

- [x] Verificação de disponibilidade e licença do modelo (ver `ASSET_LICENSE.md`).
- [x] Importação do modelo: rig de 366 ossos, 407.182 triângulos, 8 materiais.
- [x] Otimizador de texturas para Android: 30 texturas 4K → 1024 px (126 MB → 14 MB).
- [x] Conversão reproduzível da cena do Blender em `.glb` (`tools/build_animations.py`).
- [x] Quatro clipes de animação assados (`idle`, `walk`, `run`, `jump`).
- [x] Personagem jogável com `CharacterBody3D`: caminhada, corrida, pulo,
      gravidade, colisões e rotação suave.
- [x] Animação escolhida pela velocidade, tocando os clipes assados.
- [x] Câmera em terceira pessoa com `SpringArm3D` e controle por toque.
- [x] Controles touchscreen: joystick, área de câmera, botões de pulo e corrida.
- [x] Cenário de teste: chão, prédios, plataformas, obstáculos, iluminação.
- [x] Teste funcional automatizado (42 verificações) e APK de debug.
- [ ] **Substituir o personagem por um herói original** antes de qualquer
      publicação (o modelo atual é protegido — ver `ASSET_LICENSE.md`).

## MISSÃO 003 — Sistema de teias e balanço ✅

- [x] Módulo independente em `src/web/` (física, detector, visual, controlador).
- [x] Disparo pela mira da câmera, com validação de superfície, distância,
      altura mínima e linha de visão.
- [x] Balanço por pêndulo físico: gravidade, conservação de velocidade, tensão
      da corda e comprimento ajustável.
- [x] Soltura preservando a velocidade e a inércia.
- [x] Representação visual da teia, atualizada sem alocação por quadro.
- [x] Câmera dinâmica durante o balanço, preservando o controle manual.
- [x] Controles de toque (disparar, soltar, ajustar) e teclado para testes.
- [x] Postura de balanço procedural discreta, sem alterar o rig original.
- [x] Teste automatizado com 63 verificações; APK e CI verdes.

## MISSÃO 004 — Distrito de Manhattan ✅

- [x] Geração de quarteirões, ruas, calçadas e faixas de pedestres em grade.
- [x] Prédios de alturas variadas (12–78 m) com fachadas de janelas.
- [x] Telhados acessíveis, com parapeito, caixa d'água, ar-condicionado e antena.
- [x] Mobiliário urbano: postes, semáforos, placas e hidrantes.
- [x] Colisões de prédio compatíveis com o detector de teias.
- [x] Otimização: MultiMesh, material único, shader procedural, sem textura 4K.
- [x] Iluminação e névoa para Mobile; base pronta para ciclo de dia/noite.
- [x] Teste automatizado com 42 verificações; APK e CI verdes.
- [ ] **Próximo:** LOD, occlusion culling e carregamento por região — necessários
      antes de aumentar o distrito.

## MISSÃO 005 — Sistemas de mundo ⏳

- [ ] Ciclo dia/noite.
- [ ] Colisão e navegação em superfície.
- [ ] Pontos de interesse e objetivos simples.
- [ ] HUD mínimo (objetivo atual, minimapa).

## MISSÃO 006 — Conteúdo e polimento ⏳

- [ ] Missões curtas e missões secundárias.
- [ ] Efeitos visuais e sonoros.
- [ ] Ajuste de desempenho em aparelhos modestos.
- [ ] Build de release assinada e publicação.

---

## Critérios de qualidade por etapa

- O projeto deve continuar **executável em modo headless**.
- O renderizador permanece **Mobile**; Forward+ é proibido para Android.
- `minSdk 24` e arquiteturas `armeabi-v7a` + `arm64-v8a` preservados.
- Nenhum asset de terceiros protegido por direitos autorais.
