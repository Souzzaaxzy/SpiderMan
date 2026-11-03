#!/usr/bin/env python3
"""Retargeting das animações do Mixamo para o rig do personagem.

## A descoberta que definiu o método

O rig é *Rigify em modo IK*: os ossos que **deformam a malha** são
`thigh_stretch.l`, `leg_twist_2.l`, `foot.l`, `arm_stretch.l`, `forearm_twist_2.l`
e assim por diante — nenhum deles é o osso que se chamaria de "coxa" ou "braço".
Quem manda neles são as constraints, a partir dos **alvos IK**
(`c_foot_ik.l`, `c_hand_ik.l`) e do quadril (`root.x`).

Copiar rotação osso a osso, como numa primeira tentativa, não funciona: medi que
o pé movia **0,000 m** com as constraints ativas, porque a `COPY_ROTATION`
sobrescrevia o que eu escrevia.

O método correto para um rig assim é o que já uso nas MISSÕES 002 e 003:
**mover os alvos IK** para as posições que o Mixamo indica, e deixar as
constraints fazerem o resto. Depois **assar** a pose avaliada.

## Mapeamento

| Mixamo | nosso controle | o que move |
| --- | --- | --- |
| `mixamorig:Hips` | `root.x` | corpo todo (posição + rotação) |
| `mixamorig:LeftFoot` | `c_foot_ik.l` | perna esquerda inteira |
| `mixamorig:RightFoot` | `c_foot_ik.r` | perna direita inteira |
| `mixamorig:LeftHand` | `c_hand_ik.l` | braço esquerdo inteiro |
| `mixamorig:RightHand` | `c_hand_ik.r` | braço direito inteiro |

A rotação do corpo vem do `Hips`; a posição dos membros vem dos alvos IK. É
suficiente para uma movimentação convincente e evita dirigir 366 ossos.

## Root motion

Os clipes do Mixamo **têm root motion** (o `Walking` anda 1,79 m). A missão pede
animações **in-place**: quem move o personagem é a física. Então a translação
horizontal é descartada e só a oscilação vertical é preservada.

Uso:
    python3 tools/retarget_animations.py <cena.blend> <pasta_mixamo> <saida.glb> <texturas>
"""

from __future__ import annotations

import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 24
KEEP_OBJECTS = ("rig", "Body", "Frames", "Logos", "Webs")

# Mixamo → nossos controles.
IK_MAP = {
    "mixamorig:LeftFoot": "c_foot_ik.l",
    "mixamorig:RightFoot": "c_foot_ik.r",
    "mixamorig:LeftHand": "c_hand_ik.l",
    "mixamorig:RightHand": "c_hand_ik.r",
}
HIPS_MIXAMO = "mixamorig:Hips"
HIPS_OURS = "root.x"

# Clipe no jogo → arquivo do Mixamo.
CLIP_SOURCES = {
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


def _clear_pose(armature) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pose_bone.location = (0, 0, 0)
    bpy.context.view_layer.update()


def _capture_rest(armature) -> dict:
    """Posição e rotação de repouso dos controles, com a action removida.

    Se a action continuar atribuída, o `frame_set` reaplica a pose animada e o
    "repouso" capturado seria o do primeiro quadro.
    """
    if armature.animation_data:
        armature.animation_data.action = None
    _clear_pose(armature)
    return {pb.name: pb.matrix.copy() for pb in armature.pose.bones}


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


def _bake_full(armature, frame_start: int, frame_end: int) -> None:
    """Assa a pose avaliada em chaves de todos os ossos.

    `nla.bake` opera sobre o **objeto ativo**. No fluxo completo o ativo é o
    esqueleto do Mixamo recém-importado, então o rig é selecionado e ativado
    aqui, explicitamente — sem isto o bake assava o esqueleto errado e o clipe
    saía com dois quadros.
    """
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
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
    bpy.ops.object.mode_set(mode="OBJECT")


def _world_to_bone_location(bone, world_position: Vector, rest_world: Matrix) -> Vector:
    """`location` local que põe o osso em `world_position`.

    O controle IK não tem pai, então o alvo é resolvido no espaço do próprio
    osso: subtrai-se a posição de repouso, no referencial de repouso.
    """
    local_delta = rest_world.to_3x3().inverted() @ (world_position - rest_world.translation)
    return local_delta


def _world_rotation_to_local(bone, world_rotation: Matrix, rest_world: Matrix) -> Quaternion:
    """Rotação local que aplica `world_rotation` sobre o repouso do osso."""
    rest_rotation = rest_world.to_3x3().normalized()
    local = rest_rotation.inverted() @ world_rotation.to_3x3().normalized() @ rest_rotation
    return local.to_quaternion()


def _retarget_clip(our_armature, mixamo_armature, action, clip_name: str) -> int:
    frame_start = int(action.frame_range[0])
    frame_end = int(action.frame_range[1])

    mixamo_rest = _capture_rest(mixamo_armature)
    our_rest = _capture_rest(our_armature)

    mixamo_armature.animation_data_create()
    mixamo_armature.animation_data.action = action
    if hasattr(mixamo_armature.animation_data, "action_slot") and action.slots:
        mixamo_armature.animation_data.action_slot = action.slots[0]

    our_action = _new_action(our_armature, clip_name)
    scene = bpy.context.scene
    scale = mixamo_armature.matrix_world.to_scale().z
    hips_start = None

    for frame in range(frame_start, frame_end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()

        # --- Quadril: rotação e oscilação vertical ---
        hips_bone = mixamo_armature.pose.bones.get(HIPS_MIXAMO)
        our_hips = our_armature.pose.bones.get(HIPS_OURS)
        if hips_bone is not None and our_hips is not None:
            hips_world = hips_bone.matrix.translation.copy()
            if hips_start is None:
                hips_start = hips_world
            rest = mixamo_rest.get(HIPS_MIXAMO)
            delta_rotation = Matrix.Identity(3)
            if rest is not None:
                delta_rotation = (hips_bone.matrix.to_3x3().normalized()
                                  @ rest.to_3x3().normalized().inverted())
            our_hips.rotation_mode = "QUATERNION"
            our_hips.rotation_quaternion = _world_rotation_to_local(
                our_hips, delta_rotation, our_rest[HIPS_OURS])
            # Só a oscilação vertical: o horizontal é root motion, e a física do
            # jogo é quem move o personagem.
            vertical = (hips_world.z - hips_start.z) * scale
            our_hips.location = _world_to_bone_location(
                our_hips, our_rest[HIPS_OURS].translation + Vector((0.0, 0.0, vertical)),
                our_rest[HIPS_OURS])
            our_hips.keyframe_insert("rotation_quaternion", frame=frame)
            our_hips.keyframe_insert("location", frame=frame)

        # --- Membros: os alvos IK seguem as mãos e os pés do Mixamo ---
        for mixamo_name, our_name in IK_MAP.items():
            mixamo_bone = mixamo_armature.pose.bones.get(mixamo_name)
            our_bone = our_armature.pose.bones.get(our_name)
            if mixamo_bone is None or our_bone is None:
                continue
            rest = mixamo_rest.get(mixamo_name)
            if rest is None:
                continue
            # Posição do membro em espaço de mundo, com a escala corrigida.
            world_target = mixamo_bone.matrix.translation.copy() * scale
            our_bone.location = _world_to_bone_location(
                our_bone, world_target, our_rest[our_name])
            # Rotação do membro, para o pé e a mão apontarem certo.
            delta_rotation = (mixamo_bone.matrix.to_3x3().normalized()
                              @ rest.to_3x3().normalized().inverted())
            our_bone.rotation_mode = "QUATERNION"
            our_bone.rotation_quaternion = _world_rotation_to_local(
                our_bone, delta_rotation, our_rest[our_name])
            our_bone.keyframe_insert("location", frame=frame)
            our_bone.keyframe_insert("rotation_quaternion", frame=frame)

        bpy.context.view_layer.update()

    # Assa a pose final: é o que faz o resultado sobreviver ao export, sem
    # depender das constraints nem dos controles.
    _bake_full(our_armature, frame_start, frame_end)

    our_action.use_fake_user = True
    _stash(our_armature, our_action)
    return frame_end - frame_start + 1


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


def _discard_mixamo(mixamo_armature) -> None:
    """Remove o esqueleto do Mixamo e as ações dele.

    Apagar só o objeto não basta: as ações importadas continuam em
    `bpy.data.actions` e o exportador as inclui, dobrando as animações do arquivo.
    """
    names = set()
    if mixamo_armature.animation_data and mixamo_armature.animation_data.action:
        names.add(mixamo_armature.animation_data.action.name)
    if mixamo_armature.animation_data:
        for track in mixamo_armature.animation_data.nla_tracks:
            for strip in track.strips:
                if strip.action:
                    names.add(strip.action.name)

    for obj in list(bpy.data.objects):
        if obj == mixamo_armature or obj.parent == mixamo_armature:
            bpy.data.objects.remove(obj, do_unlink=True)

    for action in list(bpy.data.actions):
        if action.name in names or "mixamo" in action.name.lower():
            bpy.data.actions.remove(action)


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(__doc__)
        return 2
    blend_path, mixamo_dir, output_path, textures_dir = argv[1], argv[2], argv[3], argv[4]

    bpy.ops.wm.open_mainfile(filepath=blend_path)
    our_armature = bpy.data.objects["rig"]
    bpy.context.scene.render.fps = FPS

    # Reponta as texturas para as versões otimizadas. Sem isto o .glb embute os
    # PNG 4K empacotados na cena: 109 MB de imagem.
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
    print("texturas repontadas: %d" % repointed)

    for stale in list(bpy.data.actions):
        bpy.data.actions.remove(stale)
    if our_armature.animation_data:
        for track in list(our_armature.animation_data.nla_tracks):
            our_armature.animation_data.nla_tracks.remove(track)

    retargeted = 0
    for clip_name, filename in CLIP_SOURCES.items():
        source = os.path.join(mixamo_dir, filename)
        if not os.path.isfile(source):
            print("  ausente: %s" % filename)
            continue
        mixamo_armature, action = _import_mixamo(source)
        if mixamo_armature is None or action is None:
            print("  falhou ao importar: %s" % filename)
            continue
        frames = _retarget_clip(our_armature, mixamo_armature, action, clip_name)
        print("  retargeted '%s' de '%s' (%d quadros)" % (clip_name, filename, frames))
        retargeted += 1
        _discard_mixamo(mixamo_armature)

    print("total de clipes retargeted: %d" % retargeted)
    _clear_pose(our_armature)

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
