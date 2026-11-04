#!/usr/bin/env python3
"""Gera os clipes que faltam e os adiciona ao modelo animado.

## Por que gerar, e nao retargetar

O pacote do Mixamo que o responsavel subiu tem 14 animacoes, mas **nao** tem:
`fall` (queda), `air_move` (movimento no ar), `wall_climb` (escalada) nem
`wall_jump` (pulo de parede). Sem eles, o estado caia num clipe alternativo —
e era isso que fazia o personagem abrir as pernas "como prancha" no ar: o
`standing_jump` tem uma pose de agachamento com as pernas afastadas.

Aqui esses clipes sao gerados por **pose procedural**: pequenos ajustes sobre o
repouso, que descrevem o que o corpo faz em cada situacao. Ficam no mesmo rig,
com os mesmos 22 ossos, e sao adicionados ao `.glb` existente sem mexer nos
outros clipes.

Uso:
    python3 tools/add_generated_clips.py <modelo_animado.glb>
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

BONES = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]

DEG = math.pi / 180.0


def _rest_world(armature, name: str) -> Matrix:
    return armature.matrix_world @ armature.data.bones[name].matrix_local


def _rotate(armature, name: str, world_axis: Vector, angle: float) -> None:
    """Soma uma rotação em torno de um eixo de MUNDO à pose do osso."""
    if abs(angle) < 1e-6:
        return
    pose_bone = armature.pose.bones.get(name)
    if pose_bone is None:
        return
    rest = armature.data.bones[name].matrix_local.to_3x3().normalized()
    local = rest.inverted() @ Matrix.Rotation(angle, 3, world_axis.normalized()) @ rest
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.rotation_quaternion = (
        pose_bone.rotation_quaternion @ local.to_quaternion())


def _reset(armature) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pose_bone.location = (0, 0, 0)
    bpy.context.view_layer.update()


def _keyframe(armature, frame: int) -> None:
    for name in BONES:
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is None:
            continue
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        if name == "Hips":
            pose_bone.keyframe_insert("location", frame=frame)


def _new_action(armature, name: str):
    armature.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data.action = action
    if hasattr(armature.animation_data, "action_slot") and action.slots:
        armature.animation_data.action_slot = action.slots[0]
    return action


def _stash(armature, action) -> None:
    track = armature.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, 1, action)
    armature.animation_data.action = None


def _arms(armature, left_up: float, right_up: float, back: float,
          elbow: float) -> None:
    """Levanta/abaixa os braços. `up` em graus (0 = caído)."""
    # Braço esquerdo (+X): girar em torno de Z e Y para levantar e ir para trás.
    _rotate(armature, "LeftArm", Vector((0, 0, 1)), -left_up * DEG)
    _rotate(armature, "LeftArm", Vector((1, 0, 0)), back * DEG)
    _rotate(armature, "LeftForeArm", Vector((0, 0, 1)), -elbow * DEG)
    _rotate(armature, "RightArm", Vector((0, 0, 1)), right_up * DEG)
    _rotate(armature, "RightArm", Vector((1, 0, 0)), back * DEG)
    _rotate(armature, "RightForeArm", Vector((0, 0, 1)), elbow * DEG)


def _legs(armature, bend: float, apart: float, thigh: float = 0.0) -> None:
    """Pernas: `bend` dobra o joelho, `apart` afasta, `thigh` levanta a coxa."""
    _rotate(armature, "LeftUpLeg", Vector((1, 0, 0)), thigh * DEG)
    _rotate(armature, "RightUpLeg", Vector((1, 0, 0)), thigh * DEG)
    _rotate(armature, "LeftUpLeg", Vector((0, 1, 0)), apart * DEG)
    _rotate(armature, "RightUpLeg", Vector((0, 1, 0)), -apart * DEG)
    _rotate(armature, "LeftLeg", Vector((1, 0, 0)), -bend * DEG)
    _rotate(armature, "RightLeg", Vector((1, 0, 0)), -bend * DEG)


def build_fall(armature, length: int = 40) -> None:
    """Queda: braços meio abertos para cima, pernas juntas e levemente dobradas."""
    action = _new_action(armature, "fall")
    for step in range(length + 1):
        t = step / float(length)
        _reset(armature)
        sway = math.sin(t * math.tau) * 6.0
        _arms(armature, 62.0 + sway, 62.0 - sway, 18.0, 22.0)
        _legs(armature, 16.0 + sway * 0.4, 4.0)
        _rotate(armature, "Spine1", Vector((1, 0, 0)), 8.0 * DEG)
        _rotate(armature, "Neck", Vector((1, 0, 0)), -6.0 * DEG)
        _keyframe(armature, 1 + step)
    action.use_fake_user = True
    _stash(armature, action)


def build_jump_loop(armature, length: int = 32) -> None:
    """Subida no ar: pernas juntas e recolhidas, braços para cima.

    Existe porque o `standing_jump` do Mixamo abre as pernas (pose de
    agachamento) e no ar isso lê como "prancha". Aqui as pernas ficam juntas.
    """
    action = _new_action(armature, "jump_loop")
    for step in range(length + 1):
        t = step / float(length)
        _reset(armature)
        lift = math.sin(t * math.pi) * 6.0
        _arms(armature, 84.0 + lift, 84.0 - lift, 10.0, 26.0)
        # Pernas juntas, joelho dobrado, sem afastar.
        _rotate(armature, "LeftUpLeg", Vector((1, 0, 0)), 28.0 * DEG)
        _rotate(armature, "RightUpLeg", Vector((1, 0, 0)), 24.0 * DEG)
        _rotate(armature, "LeftLeg", Vector((1, 0, 0)), -46.0 * DEG)
        _rotate(armature, "RightLeg", Vector((1, 0, 0)), -40.0 * DEG)
        _rotate(armature, "Spine1", Vector((1, 0, 0)), 6.0 * DEG)
        _keyframe(armature, 1 + step)
    action.use_fake_user = True
    _stash(armature, action)


def build_air_move(armature, length: int = 32) -> None:
    """Movimento no ar: corpo inclinado para frente, braços para trás, pernas juntas."""
    action = _new_action(armature, "air_move")
    for step in range(length + 1):
        t = step / float(length)
        _reset(armature)
        bob = math.sin(t * math.tau) * 4.0
        _arms(armature, 34.0 + bob, 34.0 - bob, -22.0, 16.0)
        _legs(armature, 10.0, 3.0, thigh=-6.0)
        _rotate(armature, "Spine1", Vector((1, 0, 0)), 16.0 * DEG)
        _rotate(armature, "Spine2", Vector((1, 0, 0)), 8.0 * DEG)
        _keyframe(armature, 1 + step)
    action.use_fake_user = True
    _stash(armature, action)


def build_wall_climb(armature, length: int = 48) -> None:
    """Escalada: braços e pernas alternando, como quem sobe uma parede.

    O personagem encara a parede (frente em -Y), entao os membros vao para a
    frente (-Y) alternadamente.
    """
    action = _new_action(armature, "wall_climb")
    for step in range(length + 1):
        phase = (step / float(length)) * math.tau
        _reset(armature)
        # Braços: um sobe enquanto o outro desce.
        left = 70.0 + math.sin(phase) * 30.0
        right = 70.0 - math.sin(phase) * 30.0
        _arms(armature, left, right, 30.0, 30.0)
        # Pernas: alternam, com o joelho bem dobrado.
        left_thigh = 30.0 + math.sin(phase + math.pi) * 22.0
        right_thigh = 30.0 - math.sin(phase + math.pi) * 22.0
        _rotate(armature, "LeftUpLeg", Vector((1, 0, 0)), left_thigh * DEG)
        _rotate(armature, "RightUpLeg", Vector((1, 0, 0)), right_thigh * DEG)
        _rotate(armature, "LeftLeg", Vector((1, 0, 0)), -55.0 * DEG)
        _rotate(armature, "RightLeg", Vector((1, 0, 0)), -55.0 * DEG)
        _rotate(armature, "Spine1", Vector((1, 0, 0)), 6.0 * DEG)
        _keyframe(armature, 1 + step)
    action.use_fake_user = True
    _stash(armature, action)


def build_wall_jump(armature, length: int = 24) -> None:
    """Pulo de parede: empurra para longe, braços abrem, pernas se esticam."""
    action = _new_action(armature, "wall_jump")
    for step in range(length + 1):
        t = step / float(length)
        _reset(armature)
        # Abre do agachamento para o corpo esticado.
        spread = 30.0 + t * 30.0
        _arms(armature, spread, spread, -10.0, 10.0 * (1.0 - t))
        _legs(armature, 40.0 * (1.0 - t), 8.0 * (1.0 - t))
        _rotate(armature, "Spine1", Vector((1, 0, 0)), (12.0 * (1.0 - t)) * DEG)
        _keyframe(armature, 1 + step)
    action.use_fake_user = True
    _stash(armature, action)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    path = argv[1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    armature = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    our_meshes = [o.name for o in bpy.data.objects if o.type == "MESH"]

    # Remove as actions que vamos regerar (se ja existirem).
    for name in ["fall", "air_move", "wall_climb", "wall_jump", "jump_loop"]:
        existing = bpy.data.actions.get(name)
        if existing is not None:
            bpy.data.actions.remove(existing)
    # Limpa as NLA tracks antigas desses nomes.
    if armature.animation_data:
        for track in list(armature.animation_data.nla_tracks):
            if track.name in ["fall", "air_move", "wall_climb", "wall_jump", "jump_loop"]:
                armature.animation_data.nla_tracks.remove(track)

    build_fall(armature)
    build_jump_loop(armature)
    build_air_move(armature)
    build_wall_climb(armature)
    build_wall_jump(armature)
    print("clipes gerados: fall, jump_loop, air_move, wall_climb, wall_jump")

    # Remove malhas de bone-shape do import, se houver.
    keep = set(our_meshes) | {armature.name}
    for obj in list(bpy.data.objects):
        if obj.name not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type in {"MESH", "ARMATURE"}:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
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
    print("exportado: %s (%.2f MB)" % (path, os.path.getsize(path) / 1048576))
    fixed = fix_quaternions(path)
    if fixed:
        print("quaternions: %d trocas de sinal corrigidas" % fixed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
