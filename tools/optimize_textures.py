#!/usr/bin/env python3
"""Otimizador de texturas para Android (MISSÃO 002).

Reduz texturas do modelo original para tamanhos adequados a um Galaxy A14
(4 GB de RAM), preservando ao máximo a qualidade visual. Nunca altera os
arquivos originais: sempre escreve em um diretório de saída separado.

Dois modos:

* ``plan``  — só lê os arquivos e imprime o que seria feito (não escreve nada).
* ``apply`` — grava as texturas redimensionadas no diretório de destino.

Formatos de origem tratados:
* PNG/JPG: redimensionados para o alvo quadrado mais próximo.
* EXR 8K: **não são redimensionados aqui** (exigem OpenEXR/ImageIO). São
  listados como "nao suportado" para que a conversão seja feita uma única vez
  fora do jogo, em vez de processar EXR em tempo de execução no aparelho.

Uso:
    python3 tools/optimize_textures.py plan  assets/models/player/original assets/models/player/optimized
    python3 tools/optimize_textures.py apply assets/models/player/original assets/models/player/optimized
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - dependência opcional
    Image = None  # type: ignore[assignment]

# Teto de textura para Android modesto. 1024 mantém boa leitura de detalhe sem
# estourar a memória de vídeo de aparelhos de entrada.
MAX_TEXTURE_SIZE = 1024
RASTER_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".tga"}
EXR_EXTENSIONS = {".exr"}


def find_textures(source: Path) -> list[Path]:
    return sorted(
        path
        for path in source.rglob("*")
        if path.is_file() and path.suffix.lower() in RASTER_EXTENSIONS | EXR_EXTENSIONS
    )


def target_size(width: int, height: int, maximum: int = MAX_TEXTURE_SIZE) -> tuple[int, int]:
    """Maior lado = min(maior lado original, máximo), preservando proporção."""
    largest = max(width, height)
    if largest <= maximum:
        return width, height
    scale = maximum / largest
    return max(1, round(width * scale)), max(1, round(height * scale))


def plan_for(path: Path) -> dict:
    if path.suffix.lower() in EXR_EXTENSIONS:
        return {"path": path, "action": "nao_suportado", "detail": "EXR: converter manualmente"}
    if Image is None:
        return {"path": path, "action": "sem_pillow", "detail": "instale Pillow para processar"}
    with Image.open(path) as image:
        width, height = image.size
    new_size = target_size(width, height)
    action = "manter" if new_size == (width, height) else "redimensionar"
    return {"path": path, "action": action, "detail": f"{width}x{height} -> {new_size[0]}x{new_size[1]}"}


def apply_for(path: Path, destination_root: Path, source_root: Path) -> None:
    relative = path.relative_to(source_root)
    destination = destination_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(path) as image:
        width, height = image.size
        new_size = target_size(width, height)
        converted = image.convert("RGBA") if image.mode not in ("RGB", "RGBA") else image
        if new_size != (width, height):
            converted = converted.resize(new_size, Image.LANCZOS)
        converted.save(destination)


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] not in {"plan", "apply"}:
        print(__doc__)
        return 2

    mode, source_arg, destination_arg = argv[1], Path(argv[2]), Path(argv[3])
    if not source_arg.is_dir():
        print(f"Diretorio de origem inexistente: {source_arg}")
        return 1

    textures = find_textures(source_arg)
    if not textures:
        print(f"Nenhuma textura encontrada em {source_arg}.")
        return 0

    for path in textures:
        info = plan_for(path)
        print(f"[{mode}] {info['action']:<14} {path.name}  {info['detail']}")
        if mode == "apply" and info["action"] == "redimensionar":
            apply_for(path, destination_arg, source_arg)

    if mode == "plan":
        print("\nNada foi escrito (modo plan).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
