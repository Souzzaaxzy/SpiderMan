#!/usr/bin/env python3
"""Retargeting das animacoes do Mixamo para o personagem novo.

## Por que e simples agora

O esqueleto do personagem foi construido do zero com **nomes iguais aos do
Mixamo** (sem o prefixo `mixamorig:`) e uma **hierarquia humana encadeada**, sem
constraints. Entao o retargeting e uma correspondencia direta de nome, sem
adivinhar hierarquia nem remover constraints — era isso que quebrava no rig
Rigify antigo.

## A formula

Para cada osso, copiamos a **diferenca de orientacao** do Mixamo sobre o repouso:

    delta = pose_mixamo @ repouso_mixamo^-1
    alvo  = delta @ repouso_nosso

Nessa forma as matrizes de espaco (rotacao 90 graus em X, escala 0,01) se
cancelam. Depois assamos a pose quadro a quadro.

Uso:
    python3 tools/retarget_character.py <personagem.glb> <pasta_mixamo> <saida.glb>
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fix_glb_quaternions import fix_quaternions

FPS = 24
# O quadril do Mixamo fica ~0,25 m mais alto que o nosso; este deslocamento
# assenta os pes no chao.
GROUND_OFFSET = 0.0

# Nosso osso -> osso do Mixamo (mesmo nome, com prefixo).
BONES = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]

CLIP_SOURCES = {
    "idle": "__IDLE__",
    "walking": "Walking.fbx",
    "jog": "Running.fbx",
    "sprint": "Running.fbx",
    "start_run": "Start Walking.fbx",
    "turn": "Walking Turn 180.fbx",
    "standing_jump": "Standing Jump.fbx",
    "falling_to_landing": "Falling To Landing.fbx",
    "land_roll": "Falling To Roll.fbx",
    "swing_start": "Start Swinging.fbx",
    "swing_loop": "Swinging.fbx",
    "swing_release": "Swing To Land.fbx",
    "swing_to_land": "Swing To Land (1).fbx",
    "swing_into_wall": "Swing Into Wall.fbx",
    "wall_run": "Wall Run.fbx",
    "low_crawl": "Low Crawl.fbx",
}


def _mixamo(name: str) -> str:
    return "mixamorig:" + name


def _import_mixamo(path: str):
    before = set(obj.name for obj in bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.abspath(path))
    armature = None
    for obj in bpy.data.objects:
        if obj.name not in before and obj.type == "ARMATURE":
            armature = obj
            break
    if armature is None:
        return None, None
    action = armature.animation_data.action if armature.animation_data else None
    if action is None and bpy.data.actions:
        action = bpy.data.actions[-1]
        armature.animation_data_create()
        armature.animation_data.action = action
        if hasattr(armature.animation_data, "action_slot") and action.slots:
            armature.animation_data.action_slot = action.slots[0]
    return armature, action


def _rest_world(armature, name: str) -> Matrix:
    return armature.matrix_world @ armature.data.bones[name].matrix_local


def _mixamo_rest(mixamo, name: str) -> Matrix:
    return (mixamo.matrix_world @ mixamo.data.bones[name].matrix_local).to_3x3().normalized()


def _mixamo_pose(mixamo, name: str) -> Matrix:
    return (mixamo.matrix_world @ mixamo.pose.bones[name].matrix).to_3x3().normalized()


def _discard_mixamo(mixamo) -> None:
    names = set()
    if mixamo.animation_data and mixamo.animation_data.action:
        names.add(mixamo.animation_data.action.name)
    if mixamo.animation_data:
        for track in mixamo.animation_data.nla_tracks:
            for strip in track.strips:
                if strip.action:
                    names.add(strip.action.name)
    for obj in list(bpy.data.objects):
        if obj == mixamo or obj.parent == mixamo:
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        if action.name in names or "mixamo" in action.name.lower():
            bpy.data.actions.remove(action)


def _new_action(armature, name: str):
    armature.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data.action = action
    if hasattr(armature.animation_data, "action_slot") and action.slots:
        armature.animation_data.action_slot = action.slots[0]
    return action


def _stash(armature, action) -> None:
    armature.animation_data_create()
    track = armature.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, 1, action)
    armature.animation_data.action = None


def _write_pose(armature, rests, mixamo, mix_rest) -> None:
    for name in BONES:
        mixamo_name = _mixamo(name)
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is None or mixamo.pose.bones.get(mixamo_name) is None:
            continue
        parent = armature.data.bones[name].parent
        parent_world = (armature.pose.bones[parent.name].matrix
                        if parent is not None else Matrix.Identity(4))
        parent_rest = (rests[parent.name] if parent is not None and parent.name in rests
                       else Matrix.Identity(4))
        rest_rel = parent_rest.inverted() @ rests[name]
        basis = (parent_world @ rest_rel).to_3x3().normalized()

        delta = _mixamo_pose(mixamo, mixamo_name) @ mix_rest[mixamo_name].inverted()
        target = delta @ rests[name].to_3x3().normalized()

        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (basis.inverted() @ target).to_quaternion()
        bpy.context.view_layer.update()


def _keyframe_all(armature, frame: int) -> None:
    for name in BONES:
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is None:
            continue
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        if name == "Hips":
            pose_bone.keyframe_insert("location", frame=frame)


def _retarget_clip(armature, mixamo, action, clip_name: str) -> int:
    rests = {name: _rest_world(armature, name) for name in BONES}
    mix_rest = {_mixamo(name): _mixamo_rest(mixamo, _mixamo(name)) for name in BONES}

    mixamo.animation_data_create()
    mixamo.animation_data.action = action
    if hasattr(mixamo.animation_data, "action_slot") and action.slots:
        mixamo.animation_data.action_slot = action.slots[0]

    our_action = _new_action(armature, clip_name)
    scene = bpy.context.scene
    frame_start = int(action.frame_range[0])
    frame_end = int(action.frame_range[1])

    hips_start = None
    for step, frame in enumerate(range(frame_start, frame_end + 1)):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        _write_pose(armature, rests, mixamo, mix_rest)
        hips = (mixamo.matrix_world @ mixamo.pose.bones["mixamorig:Hips"].matrix).translation
        if hips_start is None:
            hips_start = hips.z
        bob = hips.z - hips_start - GROUND_OFFSET
        root = armature.pose.bones["Hips"]
        root.location = rests["Hips"].to_3x3().inverted() @ Vector((0.0, 0.0, bob))
        _keyframe_all(armature, step + 1)

    our_action.use_fake_user = True
    _stash(armature, our_action)
    return frame_end - frame_start + 1


def _build_idle_clip(armature, mixamo_dir: str, clip_name: str) -> int:
    source = os.path.join(mixamo_dir, "Walking.fbx")
    if not os.path.isfile(source):
        return 0
    mixamo, action = _import_mixamo(source)
    if mixamo is None or action is None:
        return 0

    rests = {name: _rest_world(armature, name) for name in BONES}
    mix_rest = {_mixamo(name): _mixamo_rest(mixamo, _mixamo(name)) for name in BONES}

    mixamo.animation_data_create()
    mixamo.animation_data.action = action
    if hasattr(mixamo.animation_data, "action_slot") and action.slots:
        mixamo.animation_data.action_slot = action.slots[0]

    our_action = _new_action(armature, clip_name)
    scene = bpy.context.scene
    first = int(action.frame_range[0])
    length = 48
    for step in range(length + 1):
        scene.frame_set(first)
        bpy.context.view_layer.update()
        _write_pose(armature, rests, mixamo, mix_rest)
        bob = 0.008 * math.sin(step / float(length) * math.tau)
        root = armature.pose.bones["Hips"]
        root.location = rests["Hips"].to_3x3().inverted() @ Vector((0.0, 0.0, bob))
        _keyframe_all(armature, 1 + step)

    our_action.use_fake_user = True
    _stash(armature, our_action)
    _discard_mixamo(mixamo)
    return length + 1


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__)
        return 2
    character_path, mixamo_dir, output_path = argv[1], argv[2], argv[3]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=character_path)
    armature = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    our_meshes = [o.name for o in bpy.data.objects if o.type == "MESH"]
    for stale in list(bpy.data.actions):
        bpy.data.actions.remove(stale)

    retargeted = 0
    for clip_name, filename in CLIP_SOURCES.items():
        if filename == "__IDLE__":
            frames = _build_idle_clip(armature, mixamo_dir, clip_name)
            print("  gerado '%s' (%d quadros)" % (clip_name, frames))
            retargeted += 1 if frames > 0 else 0
            continue
        source = os.path.join(mixamo_dir, filename)
        if not os.path.isfile(source):
            print("  ausente: %s" % filename)
            continue
        mixamo, action = _import_mixamo(source)
        if mixamo is None or action is None:
            print("  falhou ao importar: %s" % filename)
            continue
        frames = _retarget_clip(armature, mixamo, action, clip_name)
        print("  retargeted '%s' de '%s' (%d quadros)" % (clip_name, filename, frames))
        retargeted += 1
        _discard_mixamo(mixamo)

    print("total de clipes: %d" % retargeted)

    # O import do Mixamo cria malhas de "bone shape" (Beta_Joints/Beta_Surface).
    # Remove tudo que nao seja o nosso corpo e o nosso esqueleto.
    keep = set(our_meshes) | {armature.name}
    for obj in list(bpy.data.objects):
        if obj.name not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_bake_animation=False,
        export_optimize_animation_size=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print("exportado: %s (%.2f MB)" % (output_path, os.path.getsize(output_path) / 1048576))
    fixed = fix_quaternions(output_path)
    if fixed:
        print("quaternions: %d trocas de sinal corrigidas" % fixed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
