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

## MISSÃO 002 — Personagem 3D e movimentação ✅ (com pendência de asset)

- [x] Verificação de disponibilidade e licença do modelo (ver `ASSET_LICENSE.md`).
- [x] Otimizador de texturas para Android (`tools/optimize_textures.py`).
- [x] Personagem jogável com `CharacterBody3D`: caminhada, corrida, pulo,
      gravidade, colisões e rotação suave.
- [x] Animação baseada na velocidade (modo modelo e modo procedural).
- [x] Câmera em terceira pessoa com `SpringArm3D` e controle por toque.
- [x] Controles touchscreen: joystick, área de câmera, botões de pulo e corrida.
- [x] Cenário de teste: chão, prédios, plataformas, obstáculos, iluminação.
- [x] Teste funcional automatizado (34 verificações) e APK de debug.
- [ ] **Pendente:** importar o modelo do personagem — depende de liberação de
      licença e do fornecimento dos arquivos pelo responsável.

## MISSÃO 003 — Blocos da cidade ⏳

- [ ] Geração de quarteirões e ruas em grade.
- [ ] Prédios com `MultiMeshInstance3D` para performance.
- [ ] Streaming por chunks (carregar/descarregar por proximidade).
- [ ] Iluminação e névoa otimizadas para Mobile.

## MISSÃO 004 — Sistemas de mundo ⏳

- [ ] Ciclo dia/noite.
- [ ] Colisão e navegação em superfície.
- [ ] Pontos de interesse e objetivos simples.
- [ ] HUD mínimo (objetivo atual, minimapa).

## MISSÃO 005 — Conteúdo e polimento ⏳

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
