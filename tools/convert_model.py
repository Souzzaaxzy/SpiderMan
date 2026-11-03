#!/usr/bin/env python3
"""Converte a cena do Blender do personagem em um .glb para a Godot.

Por que isto existe: os arquivos FBX fornecidos **não têm esqueleto** (sem
Deformer/Skin/Cluster). O rig está na cena do Blender (`raimisuitblender5.0.blend`),
que traz as texturas embutidas em 4K. Este script:

1. abre a cena do Blender;
2. reponta as texturas embutidas para as versões otimizadas
   (`assets/models/player/optimized/textures`, 1024 px);
3. exporta apenas o rig e as malhas do personagem em `.glb`.

O `.glb` resultante é versionado; as texturas otimizadas ficam embutidas nele.

Requisitos: `pip install bpy` (traz o Blender como módulo Python).
Uso:
    python3 tools/convert_model.py <caminho/para/raimisuitblender5.0.blend> \
        assets/models/player/optimized/textures assets/models/player/spiderman_newlife.glb
"""

from __future__ import annotations

import os
import sys

# Objetos que formam o personagem (rig + malhas). Luzes e helpers ficam de fora.
KEEP_OBJECTS = ("rig", "Body", "Frames", "Logos", "Webs")


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__)
        return 2
    blend_path, textures_dir, output_path = argv[1], argv[2], argv[3]

    import bpy  # importado aqui: só existe quando o bpy está instalado

    if not os.path.isfile(blend_path):
        print(f"Cena do Blender nao encontrada: {blend_path}")
        return 1
    if not os.path.isdir(textures_dir):
        print(f"Diretorio de texturas otimizadas nao encontrado: {textures_dir}")
        return 1

    bpy.ops.wm.open_mainfile(filepath=blend_path)

    repointed = 0
    for image in list(bpy.data.images):
        base = os.path.basename(image.filepath) if image.filepath else ""
        if not base:
            continue
        candidate = os.path.join(textures_dir, base)
        if not os.path.exists(candidate):
            print(f"  sem versao otimizada para {base}")
            continue
        if image.packed_file is not None:
            image.unpack(method="REMOVE")
        image.filepath = candidate
        image.reload()
        repointed += 1
    print(f"texturas repontadas: {repointed}")

    bpy.ops.object.select_all(action="DESELECT")
    for name in KEEP_OBJECTS:
        obj = bpy.data.objects.get(name)
        if obj is None:
            print(f"  objeto ausente na cena: {name}")
            continue
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["rig"]

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_skins=True,
        export_animations=False,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"exportado: {output_path} ({os.path.getsize(output_path) / 1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
