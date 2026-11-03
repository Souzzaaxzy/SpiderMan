#!/usr/bin/env python3
"""Gera as animações do personagem no Blender e exporta tudo para .glb.

Por que isto existe
-------------------
O rig do arquivo é do tipo *Rigify* em modo IK: os ossos que deformam a malha
recebem a pose de **controles** (`c_foot_ik.*`, `c_hand_ik.*`, `c_root.x`) por
meio de **279 constraints**. Constraints não existem em glTF, então ao importar
o modelo na Godot os braços e as pernas ficavam presos — era impossível animá-los
por script.

Solução: animar os controles aqui (onde as constraints funcionam), **assar**
(*bake*) o resultado em chaves de todos os 366 ossos e exportar como clipes de
animação. Na Godot basta tocar os clipes — não há constraints para reproduzir.

Gera quatro clipes: `idle`, `walk`, `run`, `jump`.

Uso:
    python3 tools/build_animations.py <raimisuitblender5.0.blend> \
        assets/models/player/optimized/textures \
        assets/models/player/spiderman_newlife.glb
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

FPS = 24
KEEP_OBJECTS = ("rig", "Body", "Frames", "Logos", "Webs")

# O rig é Rigify em modo IK: quem manda na pose são os controles `c_*_ik.*`.
# Os eixos LOCAIS desses controles estão rotacionados em relação ao mundo, então
# todo deslocamento é informado em espaço MUNDIAL e convertido aqui.
#
# No espaço do Blender o personagem encara -Y, então:
#   mundo -Y = para frente     mundo +Y = para trás
#   mundo +Z = para cima       mundo ±X = lateral


def _world_to_local(armature: bpy.types.Object, bone_name: str, world_delta) -> Vector:
    """Converte um deslocamento em espaço mundial para o `location` local do osso."""
    matrix = armature.pose.bones[bone_name].bone.matrix_local.to_3x3()
    return matrix.inverted() @ Vector(world_delta)


# --- Braços caídos ---------------------------------------------------------
#
# O rig de repouso tem os braços abertos a ~55° da vertical: é uma pose de T, não
# uma pose de pessoa parada. Movendo o alvo IK de cada mão para baixo e para
# dentro do corpo, os braços caem a ~18°, como no dia a dia.
#
# Isso PRECISA ser assado aqui: na Godot, mexer no controle IK não faz nada,
# porque quem obedece ao controle são as constraints — e constraints não existem
# em glTF. Foi exatamente o erro que deixou os braços travados no jogo.
RELAXED_ARM_OFFSET = Vector((-0.40, 0.0, -0.40))
HAND_IK_BONES = ("c_hand_ik.l", "c_hand_ik.r")


def _relaxed_arm_pose(side: str, extra: Vector | None = None) -> tuple:
    """Pose do alvo IK da mão: braço caído ao lado do corpo."""
    sign = 1.0 if side == "l" else -1.0
    delta = Vector((RELAXED_ARM_OFFSET.x * sign, RELAXED_ARM_OFFSET.y, RELAXED_ARM_OFFSET.z))
    if extra is not None:
        delta += extra
    return (delta, None)


def _relaxed_arms(extra: dict | None = None) -> dict:
    """Pose base com os dois braços caídos, opcionalmente com ajustes por lado."""
    pose = {}
    for side in ("l", "r"):
        pose["c_hand_ik.%s" % side] = _relaxed_arm_pose(side)
    if extra:
        pose.update(extra)
    return pose


def _throwing_arm(side: str, lift: float) -> tuple:
    """Braço levantado na direção do arremesso: para cima e para frente."""
    sign = 1.0 if side == "l" else -1.0
    # Parte do braço caído e sobe até acima do ombro.
    delta = Vector((-0.45 * sign, -0.45, -0.40 + 0.55 * lift))
    return (delta, None)


def _clear_pose(armature: bpy.types.Object) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pose_bone.location = (0, 0, 0)


def _key_controls(armature: bpy.types.Object, frame: int, pose: dict) -> None:
    """Aplica e registra a pose dos controles em um quadro.

    `pose` mapeia o nome do osso para (deslocamento em espaço MUNDIAL, rotação).
    """
    bpy.context.scene.frame_set(frame)
    for bone_name, (world_delta, rotation) in pose.items():
        pose_bone = armature.pose.bones.get(bone_name)
        if pose_bone is None:
            continue
        pose_bone.location = _world_to_local(armature, bone_name, world_delta)
        pose_bone.rotation_quaternion = Quaternion(rotation) if rotation else Quaternion((1, 0, 0, 0))
        pose_bone.keyframe_insert("location", frame=frame)
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)


def _bake(armature: bpy.types.Object, frame_start: int, frame_end: int) -> None:
    """Assa a pose avaliada (com constraints) em chaves de todos os ossos."""
    bpy.ops.nla.bake(
        frame_start=frame_start,
        frame_end=frame_end,
        only_selected=False,
        visual_keying=True,
        clear_constraints=False,
        clear_parents=False,
        use_current_action=True,
        bake_types={"POSE"},
    )


def _new_action(armature: bpy.types.Object, name: str):
    armature.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data.action = action
    if hasattr(armature.animation_data, "action_slot") and action.slots:
        armature.animation_data.action_slot = action.slots[0]
    return action


def _stash(armature: bpy.types.Object, action) -> None:
    """Guarda a ação em uma trilha NLA para o exportador encontrá-la."""
    track = armature.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, 1, action)
    armature.animation_data.action = None


def build_idle(armature: bpy.types.Object, action) -> None:
    """Parado: braços caídos, com respiração discreta."""
    length = 48
    for step in range(0, length + 1, 6):
        phase = step / length * math.tau
        bob = 0.012 * math.sin(phase)
        _key_controls(armature, 1 + step, _relaxed_arms({
            "c_root.x": ((0.0, 0.0, bob), None),
        }))
    _bake(armature, 1, 1 + length)
    _stash(armature, action)


def _locomotion(armature: bpy.types.Object, action, length: int, stride: float,
                lift: float, arm_swing: float, bob: float, lean: float) -> None:
    """Ciclo de passada: pernas alternam, braços caídos balançando em oposição.

    Os deslocamentos são em espaço mundial: -Y é para frente, +Z para cima.
    """
    samples = 12
    for step in range(samples + 1):
        frame = 1 + round(step / samples * length)
        phase = step / samples * math.tau

        # cos=+1 => pé atrás; cos=-1 => pé à frente. As pernas ficam opostas.
        left_stride = math.cos(phase) * stride
        right_stride = -math.cos(phase) * stride
        # O pé só levanta na metade do ciclo em que avança para frente.
        left_lift = max(0.0, math.sin(phase)) * lift
        right_lift = max(0.0, -math.sin(phase)) * lift
        # Braços caídos, balançando junto com a perna oposta.
        left_arm = math.cos(phase) * arm_swing
        right_arm = -math.cos(phase) * arm_swing
        # Pequeno balanço lateral do quadril, no compasso da passada.
        sway = 0.015 * math.sin(phase)

        pose = _relaxed_arms({
            "c_foot_ik.l": ((0.0, left_stride, left_lift), None),
            "c_foot_ik.r": ((0.0, right_stride, right_lift), None),
            "c_root.x": ((sway, 0.0, bob * abs(math.sin(phase))),
                         Quaternion(Vector((1, 0, 0)), math.radians(lean))),
        })
        # O balanço do braço soma ao braço já caído.
        pose["c_hand_ik.l"] = _relaxed_arm_pose("l", Vector((0.0, left_arm, 0.0)))
        pose["c_hand_ik.r"] = _relaxed_arm_pose("r", Vector((0.0, right_arm, 0.0)))
        _key_controls(armature, frame, pose)
    _bake(armature, 1, 1 + length)
    _stash(armature, action)


def build_walk(armature: bpy.types.Object, action) -> None:
    _locomotion(armature, action, length=24, stride=0.26, lift=0.10,
                arm_swing=0.16, bob=0.03, lean=2.0)


def build_run(armature: bpy.types.Object, action) -> None:
    _locomotion(armature, action, length=16, stride=0.44, lift=0.20,
                arm_swing=0.30, bob=0.06, lean=9.0)


def build_jump(armature: bpy.types.Object, action) -> None:
    """Impulso: agacha, estende, sobe e pousa. O braço sobe no arremesso."""
    keys = [
        (1, 0.00, 0.0, 0.00, 0.0),
        (4, -0.06, 0.0, -0.10, 2.0),   # agacha
        (8, 0.14, 0.8, 0.16, 4.0),     # estende, braço subindo
        (14, 0.20, 1.0, 0.12, 6.0),    # auge, braço no alto
        (20, 0.06, 0.3, -0.05, 2.0),   # descida
        (24, 0.00, 0.0, 0.00, 0.0),    # pousa
    ]
    for frame, foot_y, lift, bob, lean in keys:
        pose = _relaxed_arms({
            "c_foot_ik.l": ((0.0, foot_y, max(0.0, foot_y)), None),
            "c_foot_ik.r": ((0.0, foot_y, max(0.0, foot_y)), None),
            "c_root.x": ((0.0, 0.0, bob), Quaternion(Vector((1, 0, 0)), math.radians(lean))),
        })
        # Braço direito sobe no arremesso; o esquerdo acompanha um pouco.
        pose["c_hand_ik.r"] = _throwing_arm("r", lift)
        pose["c_hand_ik.l"] = _throwing_arm("l", lift * 0.5)
        _key_controls(armature, frame, pose)
    _bake(armature, 1, 24)
    _stash(armature, action)


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__)
        return 2
    blend_path, textures_dir, output_path = argv[1], argv[2], argv[3]

    bpy.ops.wm.open_mainfile(filepath=blend_path)
    armature = bpy.data.objects["rig"]
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)

    # Repontar texturas embutidas para as versões otimizadas.
    repointed = 0
    for image in list(bpy.data.images):
        base = os.path.basename(image.filepath) if image.filepath else ""
        candidate = os.path.join(textures_dir, base)
        if base and os.path.exists(candidate):
            if image.packed_file is not None:
                image.unpack(method="REMOVE")
            image.filepath = candidate
            image.reload()
            repointed += 1
    print(f"texturas repontadas: {repointed}")

    bpy.ops.object.mode_set(mode="POSE")
    bpy.context.scene.render.fps = FPS

    for stale in list(bpy.data.actions):
        bpy.data.actions.remove(stale)

    _clear_pose(armature)
    build_idle(armature, _new_action(armature, "idle"))
    _clear_pose(armature)
    build_walk(armature, _new_action(armature, "walk"))
    _clear_pose(armature)
    build_run(armature, _new_action(armature, "run"))
    _clear_pose(armature)
    build_jump(armature, _new_action(armature, "jump"))
    _clear_pose(armature)

    bpy.ops.object.mode_set(mode="OBJECT")
    print("acoes geradas: %s" % [a.name for a in bpy.data.actions])

    bpy.ops.object.select_all(action="DESELECT")
    for name in KEEP_OBJECTS:
        obj = bpy.data.objects.get(name)
        if obj is not None:
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
    print("exportado: %s (%.1f MB)" % (output_path, os.path.getsize(output_path) / 1048576))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
