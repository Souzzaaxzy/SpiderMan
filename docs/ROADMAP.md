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

## MISSÃO 002 — Núcleo de personagem ⏳

- [ ] Controlador do herói com `CharacterBody3D` e câmera em terceira pessoa.
- [ ] Movimentação básica (andar, correr, virar) adaptada a touchscreen.
- [ ] Sistema de balanço por teia (swing) com raycast e ponto de ancoragem.
- [ ] Estados do personagem (parado, andando, caindo, balançando).
- [ ] Controles touchscreen: joystick virtual + botões de ação.

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
