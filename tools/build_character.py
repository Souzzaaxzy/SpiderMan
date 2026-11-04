#!/usr/bin/env python3
"""Constroi o personagem do zero: malha + esqueleto humanoide limpo + pesos.

## Por que refazer, em vez de consertar o rig antigo

O modelo anterior vinha de um rig *Rigify*: 366 ossos, dos quais a maioria sao
controles, e a deformacao acontece por **279 constraints** — que **nao existem em
glTF**. Pior: os ossos que deformam a malha nao estao encadeados entre si. Cada
tentativa de retargeting precisava adivinhar uma hierarquia que o arquivo nao
tem, e o resultado saia dobrado (pernas na barriga, corpo inclinado).

Aqui o esqueleto e um **humanoide de jogo**: ossos de deformacao encadeados de
verdade, **zero constraints**, e nomes iguais aos do Mixamo (sem o prefixo
`mixamorig:`). Assim as animacoes do Mixamo entram por correspondencia direta de
nome, com a formula de diferenca de repouso.

Caracteristicas do personagem (pedido do responsavel): cabelo liso, rosto meio
serio, olhos castanhos, blusa termica preta por baixo, blusa lisa preta por cima,
calca preta basica e tenis branco. 1,83 m, 75 kg.

Uso:
    python3 tools/build_character.py <saida.glb>
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Vector

HEIGHT = 1.83

# --- Esqueleto ---------------------------------------------------------------
#
# Nomes identicos aos do Mixamo, sem o prefixo. Posicoes em metros, Z para cima,
# personagem encarando -Y (mesma convencao do Mixamo).
BONES = {
    # nome:            (cabeca,                  cauda,                  pai)
    "Hips":            ((0.0, 0.0, 1.02), (0.0, 0.0, 1.14), None),
    "Spine":           ((0.0, 0.0, 1.14), (0.0, 0.0, 1.26), "Hips"),
    "Spine1":          ((0.0, 0.0, 1.26), (0.0, 0.0, 1.40), "Spine"),
    "Spine2":          ((0.0, 0.0, 1.40), (0.0, 0.0, 1.54), "Spine1"),
    "Neck":            ((0.0, 0.0, 1.54), (0.0, 0.0, 1.63), "Spine2"),
    "Head":            ((0.0, 0.0, 1.63), (0.0, 0.0, 1.75), "Neck"),
    "HeadTop_End":     ((0.0, 0.0, 1.75), (0.0, 0.0, 1.83), "Head"),

    "LeftShoulder":    ((0.05, 0.0, 1.47), (0.17, 0.0, 1.49), "Spine2"),
    "LeftArm":         ((0.17, 0.0, 1.49), (0.20, 0.0, 1.21), "LeftShoulder"),
    "LeftForeArm":     ((0.20, 0.0, 1.21), (0.21, 0.0, 0.95), "LeftArm"),
    "LeftHand":        ((0.21, 0.0, 0.95), (0.22, 0.0, 0.80), "LeftForeArm"),

    "RightShoulder":   ((-0.05, 0.0, 1.47), (-0.17, 0.0, 1.49), "Spine2"),
    "RightArm":        ((-0.17, 0.0, 1.49), (-0.20, 0.0, 1.21), "RightShoulder"),
    "RightForeArm":    ((-0.20, 0.0, 1.21), (-0.21, 0.0, 0.95), "RightArm"),
    "RightHand":       ((-0.21, 0.0, 0.95), (-0.22, 0.0, 0.80), "RightForeArm"),

    "LeftUpLeg":       ((0.09, 0.0, 1.00), (0.09, 0.0, 0.56), "Hips"),
    "LeftLeg":         ((0.09, 0.0, 0.56), (0.09, 0.0, 0.11), "LeftUpLeg"),
    "LeftFoot":        ((0.09, 0.0, 0.11), (0.09, -0.13, 0.04), "LeftLeg"),
    "LeftToeBase":     ((0.09, -0.13, 0.04), (0.09, -0.22, 0.03), "LeftFoot"),

    "RightUpLeg":      ((-0.09, 0.0, 1.00), (-0.09, 0.0, 0.56), "Hips"),
    "RightLeg":        ((-0.09, 0.0, 0.56), (-0.09, 0.0, 0.11), "RightUpLeg"),
    "RightFoot":       ((-0.09, 0.0, 0.11), (-0.09, -0.13, 0.04), "RightLeg"),
    "RightToeBase":    ((-0.09, -0.13, 0.04), (-0.09, -0.22, 0.03), "RightFoot"),
}

# Ordem pai -> filho.
ORDER = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]

# --- Materiais ---------------------------------------------------------------
SKIN = (0.82, 0.62, 0.52)
HAIR = (0.10, 0.07, 0.05)
SHIRT_UNDER = (0.11, 0.11, 0.13)   # blusa termica preta
SHIRT_OVER = (0.05, 0.05, 0.06)    # blusa lisa preta
PANTS = (0.07, 0.07, 0.08)         # calca preta
SHOE = (0.93, 0.93, 0.94)          # tenis branco
EYE = (0.32, 0.19, 0.10)           # olhos castanhos


def _material(name, color, roughness=0.6):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def _finish(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


def _capsule(name, p0, p1, r0, r1, material, segments=16):
    """Cilindro afunilado de p0 a p1 (com tampas), alinhado ao eixo."""
    a = Vector(p0)
    b = Vector(p1)
    delta = b - a
    length = delta.length
    bpy.ops.mesh.primitive_cone_add(
        vertices=segments, radius1=r0, radius2=r1, depth=length,
        location=(a + b) * 0.5)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return _finish(obj, material)


def _sphere(name, center, scale, material, segments=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=1.0, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return _finish(obj, material)


def _box(name, center, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return _finish(obj, material)


def build_mesh():
    m_skin = _material("Skin", SKIN, 0.7)
    m_hair = _material("Hair", HAIR, 0.45)
    m_under = _material("ShirtThermal", SHIRT_UNDER, 0.75)
    m_over = _material("Shirt", SHIRT_OVER, 0.8)
    m_pants = _material("Pants", PANTS, 0.85)
    m_shoe = _material("Shoe", SHOE, 0.5)
    m_eye = _material("Eye", EYE, 0.25)

    parts = []

    # --- Cabeca e pescoco ---
    parts.append(_sphere("Head", (0.0, 0.0, 1.705), (0.098, 0.112, 0.125), m_skin))
    # Mandibula/queixo: esfera menor um pouco a frente e abaixo.
    parts.append(_sphere("Jaw", (0.0, -0.025, 1.655), (0.082, 0.088, 0.070), m_skin))
    parts.append(_capsule("Neck", (0.0, 0.0, 1.53), (0.0, -0.005, 1.63), 0.055, 0.050, m_skin))

    # --- Cabelo liso: calota que cobre o topo e a nuca ---
    parts.append(_sphere("Hair", (0.0, 0.012, 1.725), (0.108, 0.122, 0.118), m_hair))
    # Franja curta sobre a testa.
    parts.append(_box("Fringe", (0.0, -0.088, 1.760), (0.185, 0.055, 0.075), m_hair))

    # --- Olhos castanhos ---
    for side, sx in (("L", 1.0), ("R", -1.0)):
        parts.append(_sphere("Eye" + side, (sx * 0.038, -0.093, 1.706),
                             (0.017, 0.012, 0.014), m_eye, 12, 8))

    # --- Torso ---
    # Blusa termica (por baixo): cobre pescoco/ombros e aparece nas mangas.
    parts.append(_capsule("ThermalTorso", (0.0, 0.0, 1.05), (0.0, 0.0, 1.50),
                          0.125, 0.150, m_under))
    parts.append(_capsule("ThermalCollar", (0.0, 0.0, 1.47), (0.0, -0.005, 1.56),
                          0.075, 0.062, m_under))
    # Blusa lisa (por cima): um pouco maior, cobrindo o tronco.
    parts.append(_capsule("ShirtTorso", (0.0, 0.0, 1.02), (0.0, 0.0, 1.47),
                          0.140, 0.163, m_over))
    parts.append(_capsule("ShirtHem", (0.0, 0.0, 0.96), (0.0, 0.0, 1.03),
                          0.146, 0.140, m_over))

    # --- Bracos (mangas pretas) ---
    for side, sx in (("L", 1.0), ("R", -1.0)):
        parts.append(_capsule("Shoulder" + side, (sx * 0.06, 0.0, 1.49),
                              (sx * 0.175, 0.0, 1.50), 0.075, 0.058, m_over))
        parts.append(_capsule("UpperArm" + side, (sx * 0.175, 0.0, 1.49),
                              (sx * 0.202, 0.0, 1.21), 0.058, 0.048, m_over))
        parts.append(_capsule("ForeArm" + side, (sx * 0.202, 0.0, 1.21),
                              (sx * 0.212, 0.0, 0.96), 0.048, 0.038, m_over))
        # Mao (pele).
        parts.append(_sphere("Hand" + side, (sx * 0.216, -0.01, 0.90),
                             (0.036, 0.026, 0.055), m_skin, 12, 8))

    # --- Pernas (calca preta) ---
    for side, sx in (("L", 1.0), ("R", -1.0)):
        parts.append(_capsule("UpLeg" + side, (sx * 0.09, 0.0, 1.01),
                              (sx * 0.09, 0.0, 0.57), 0.095, 0.072, m_pants))
        parts.append(_capsule("LowLeg" + side, (sx * 0.09, 0.0, 0.57),
                              (sx * 0.09, 0.0, 0.13), 0.072, 0.052, m_pants))
        # Tenis branco.
        parts.append(_box("Shoe" + side, (sx * 0.09, -0.045, 0.055),
                          (0.105, 0.265, 0.105), m_shoe))
        parts.append(_sphere("ShoeToe" + side, (sx * 0.09, -0.16, 0.05),
                             (0.052, 0.055, 0.045), m_shoe, 12, 8))

    # Junta tudo numa malha so.
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    bpy.ops.object.shade_smooth()
    return body


def build_armature():
    bpy.ops.object.armature_add(location=(0.0, 0.0, 0.0))
    armature = bpy.context.active_object
    armature.name = "Armature"
    armature.data.name = "Skeleton"
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)
    created = {}
    for name in ORDER:
        head, tail, parent = BONES[name]
        bone = edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent is not None:
            bone.parent = created[parent]
        created[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    output_path = argv[1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = build_mesh()
    armature = build_armature()

    # Remove qualquer objeto que nao seja o corpo ou o esqueleto.
    for obj in list(bpy.data.objects):
        if obj not in (body, armature):
            bpy.data.objects.remove(obj, do_unlink=True)

    # Pesos automaticos: o esqueleto esta dentro da malha.
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    print("objetos antes do export:", [o.name for o in bpy.data.objects])
    for obj in list(bpy.data.objects):
        if obj.name not in (body.name, armature.name):
            bpy.data.objects.remove(obj, do_unlink=True)
    print("objetos apos limpeza:", [o.name for o in bpy.data.objects])
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    armature.select_set(True)
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
    print("exportado: %s (%.2f MB)" % (output_path, os.path.getsize(output_path) / 1048576))
    print("ossos: %d" % len(armature.data.bones))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
