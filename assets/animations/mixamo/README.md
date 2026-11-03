# assets/animations/mixamo — animações a importar

Diretório de destino das animações humanoides. **Está vazio de propósito:** o
Mixamo exige login e não permite download por URL direta neste ambiente, então
nenhum arquivo de lá existe no projeto.

Coloque aqui os FBX baixados, nomeados conforme `docs/ANIMATIONS.md`. O sistema
os encontra automaticamente — nenhum código precisa mudar.

Arquivos esperados: `jog`, `sprint`, `start_run`, `stop_run`, `turn`,
`jump_start`, `jump_loop`, `fall`, `land`, `land_roll`, `air_move`,
`web_shoot_l`, `web_shoot_r`, `swing_start`, `swing_loop`, `swing_release`,
`web_zip`, `wall_run`, `wall_climb`, `wall_jump` (extensão `.fbx`).

Enquanto não existirem, esses 20 estados rodam com o clipe alternativo mais
próximo, e o console registra quais são.
