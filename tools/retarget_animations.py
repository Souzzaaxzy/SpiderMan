#!/usr/bin/env python3
"""Retargeting das animacoes do Mixamo para o rig do personagem.

## O defeito que esta versao corrige

O rig e *Rigify*: os ossos que **deformam a malha** (`thigh_stretch.l`,
`arm_stretch.l`, `foot.l`, `leg_stretch.l`, ...) recebem a pose de controles
(`c_thigh_fk.l`, `c_hand_ik.l`) por meio de **279 constraints**. Constraints nao
existem em glTF.

As versoes anteriores tentavam dirigir os **controles** (`c_*`) e assar. Isso
falhava por dois motivos somados:

1. **Hierarquia partida.** No rig, os ossos de deformacao nao sao filhos uns dos
   outros: `leg_stretch.l` e filho de `c_traj` (a raiz do rig), nao de
   `thigh_stretch.l`. Sem as constraints, girar a coxa **nao movia a perna** —
   medido: o pe ia parar na **altura do peito** (z = 1,15 a 1,39 m no `walking`;
   1,6 a 2,3 m no `jog`). Era esse o "personagem todo bugado", com as pernas
   dentro da barriga e os bracos na cabeca.
2. **Espaco de coordenadas.** O armature do Mixamo esta rotacionado 90 graus em X
   e com escala 0,01. Copiar a matriz de pose crua deformava o corpo.

## O metodo que funciona (validado por medicao)

1. **Reconstruir a hierarquia** de deformacao como uma cadeia humana limpa
   (`root -> spine -> shoulder -> arm -> forearm -> hand`; `root -> thigh -> leg
   -> foot -> toes`). O reparenting **nao altera** o `matrix_local` de cada osso,
   so a relacao de pai e filho, entao o bind da malha continua correto.
2. Para cada osso, copiar a **diferenca de orientacao** do Mixamo, aplicada sobre
   a orientacao de repouso do nosso osso:
   `delta = pose_mixamo * repouso_mixamo^-1` e `alvo = delta * repouso_nosso`.
   As matrizes de espaco (rotacao 90 graus e escala) se cancelam nessa forma.
3. Assar a pose avaliada em chaves.

Medido com o metodo novo (`walking`): pe alternando **0,09 a 0,39 m** do chao,
maos caidas a ~1,1 m, cabeca estavel a 1,85 m, altura do corpo constante 2,07 m.

Uso:
    python3 tools/retarget_animations.py <cena.blend> <pasta_mixamo> <saida.glb> <texturas>
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
# O rig de destino e um pouco mais alto que o do Mixamo, entao a pose copiada
# deixa o personagem flutuando ~0,25 m. Este deslocamento assenta os pes no chao.
# Medido: sem ele, o ponto mais baixo da malha ficava a 0,235 m; com ele, em ~0.
GROUND_OFFSET = 0.25
KEEP_OBJECTS = ("rig", "Body", "Frames", "Logos", "Webs")

# --- Hierarquia de deformacao limpa ------------------------------------------
#
# O osso da esquerda/direita recebe o pai que faz a pose fluir. Estes sao os
# ossos que **tem peso real** na malha (verificado: peso maximo > 0,25).
DEFORM_PARENT = {
    "root.x": "c_root.x",
    "spine_01.x": "root.x", "spine_02.x": "spine_01.x",
    "spine_03.x": "spine_02.x", "spine_04.x": "spine_03.x",
    "neck.x": "spine_04.x", "head.x": "neck.x",
    "shoulder.l": "spine_04.x",
    "arm_twist.l": "shoulder.l", "arm_stretch.l": "arm_twist.l",
    "forearm_stretch.l": "arm_stretch.l", "hand.l": "forearm_stretch.l",
    "thigh_twist.l": "root.x", "thigh_stretch.l": "thigh_twist.l",
    "leg_stretch.l": "thigh_stretch.l", "foot.l": "leg_stretch.l", "toes_01.l": "foot.l",
    "shoulder.r": "spine_04.x",
    "arm_twist.r": "shoulder.r", "arm_stretch.r": "arm_twist.r",
    "forearm_stretch.r": "arm_stretch.r", "hand.r": "forearm_stretch.r",
    "thigh_twist.r": "root.x", "thigh_stretch.r": "thigh_twist.r",
    "leg_stretch.r": "thigh_stretch.r", "foot.r": "leg_stretch.r", "toes_01.r": "foot.r",
}

# --- Mapeamento Mixamo -> nosso osso de deformacao ---------------------------
#
# Cada osso do Mixamo controla **um unico** osso nosso. O Mixamo tem 3 ossos de
# coluna e 2 de braco/perna por lado; nosso rig tem mais. Osso sem correspondente
# (`spine_04.x`, `arm_stretch.*`, `thigh_stretch.*`) fica **em repouso** e herda a
# rotacao do pai. Mapear dois ossos para o mesmo do Mixamo **dobrava** a rotacao e
# comprimia o corpo (cabeca descia para 1,93 m em vez de 2,07 m).
MIXAMO_BONE = {
    "root.x": "mixamorig:Hips",
    "spine_01.x": "mixamorig:Spine", "spine_02.x": "mixamorig:Spine1",
    "spine_03.x": "mixamorig:Spine2",
    "neck.x": "mixamorig:Neck", "head.x": "mixamorig:Head",
    "shoulder.l": "mixamorig:LeftShoulder",
    "arm_twist.l": "mixamorig:LeftArm",
    "forearm_stretch.l": "mixamorig:LeftForeArm", "hand.l": "mixamorig:LeftHand",
    "thigh_twist.l": "mixamorig:LeftUpLeg",
    "leg_stretch.l": "mixamorig:LeftLeg",
    "foot.l": "mixamorig:LeftFoot", "toes_01.l": "mixamorig:LeftToeBase",
    "shoulder.r": "mixamorig:RightShoulder",
    "arm_twist.r": "mixamorig:RightArm",
    "forearm_stretch.r": "mixamorig:RightForeArm", "hand.r": "mixamorig:RightHand",
    "thigh_twist.r": "mixamorig:RightUpLeg",
    "leg_stretch.r": "mixamorig:RightLeg",
    "foot.r": "mixamorig:RightFoot", "toes_01.r": "mixamorig:RightToeBase",
}

# Ordem pai -> filho: o pai precisa ser escrito antes do filho.
ORDER = [
    "root.x",
    "spine_01.x", "spine_02.x", "spine_03.x", "spine_04.x", "neck.x", "head.x",
    "shoulder.l", "arm_twist.l", "arm_stretch.l", "forearm_stretch.l", "hand.l",
    "thigh_twist.l", "thigh_stretch.l", "leg_stretch.l", "foot.l", "toes_01.l",
    "shoulder.r", "arm_twist.r", "arm_stretch.r", "forearm_stretch.r", "hand.r",
    "thigh_twist.r", "thigh_stretch.r", "leg_stretch.r", "foot.r", "toes_01.r",
]

# Mixamo -> arquivo. `idle` e gerado, nao vem do pacote.
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


def _clear_pose(armature) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pose_bone.location = (0, 0, 0)
    bpy.context.view_layer.update()


def _strip_constraints(armature) -> int:
    """Remove todas as constraints.

    Elas nao existem em glTF e, ao dirigir os ossos de deformacao diretamente,
    so atrapalhariam: uma `COPY_ROTATION` sobrescreveria a chave que escrevemos.
    """
    removed = 0
    for pose_bone in armature.pose.bones:
        for constraint in list(pose_bone.constraints):
            pose_bone.constraints.remove(constraint)
            removed += 1
    return removed


def _reparent(armature) -> None:
    """Reconstroi a cadeia de deformacao como uma hierarquia humana limpa.

    So muda o **pai** de cada osso; `matrix_local` (a pose de repouso) fica
    intacto, entao o bind da malha continua valido.
    """
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = armature.data.edit_bones
    for child, parent in DEFORM_PARENT.items():
        if child in edit_bones and parent in edit_bones:
            edit_bones[child].parent = edit_bones[parent]
            edit_bones[child].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()


def _rest_world(armature, name: str) -> Matrix:
    return armature.matrix_world @ armature.data.bones[name].matrix_local


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


def _mixamo_rest(mixamo, name: str) -> Matrix:
    return (mixamo.matrix_world @ mixamo.data.bones[name].matrix_local).to_3x3().normalized()


def _mixamo_pose(mixamo, name: str) -> Matrix:
    return (mixamo.matrix_world @ mixamo.pose.bones[name].matrix).to_3x3().normalized()


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


def _write_pose(armature, rests, mixamo, mix_rest) -> None:
    """Escreve a pose de um quadro: cada osso recebe a diferenca do Mixamo.

    Osso sem correspondente no Mixamo (`spine_04.x`, `arm_stretch.*`,
    `thigh_stretch.*`) fica em **repouso**: recebe a orientacao de repouso, e o
    filho herda a rotacao do pai pela hierarquia.
    """
    for name in ORDER:
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is None:
            continue
        parent = armature.data.bones[name].parent
        parent_world = (armature.pose.bones[parent.name].matrix
                        if parent is not None else Matrix.Identity(4))
        parent_rest = (rests[parent.name] if parent is not None and parent.name in rests
                       else Matrix.Identity(4))
        rest_rel = parent_rest.inverted() @ rests[name]
        basis = (parent_world @ rest_rel).to_3x3().normalized()

        mixamo_name = MIXAMO_BONE.get(name)
        if mixamo_name is not None and mixamo.pose.bones.get(mixamo_name) is not None:
            # Diferenca de orientacao do Mixamo, aplicada sobre o nosso repouso.
            delta = _mixamo_pose(mixamo, mixamo_name) @ mix_rest[mixamo_name].inverted()
            target = delta @ rests[name].to_3x3().normalized()
        else:
            target = rests[name].to_3x3().normalized()

        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (basis.inverted() @ target).to_quaternion()
        bpy.context.view_layer.update()


def _keyframe_all(armature, frame: int) -> None:
    for name in ORDER:
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is None:
            continue
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        if name == "root.x":
            pose_bone.keyframe_insert("location", frame=frame)


def _retarget_clip(armature, mixamo, action, clip_name: str) -> int:
    rests = {name: _rest_world(armature, name) for name in ORDER}
    mix_rest = {m: _mixamo_rest(mixamo, m) for m in set(MIXAMO_BONE.values())}

    mixamo.animation_data_create()
    mixamo.animation_data.action = action
    if hasattr(mixamo.animation_data, "action_slot") and action.slots:
        mixamo.animation_data.action_slot = action.slots[0]

    our_action = _new_action(armature, clip_name)
    scene = bpy.context.scene
    frame_start = int(action.frame_range[0])
    frame_end = int(action.frame_range[1])

    for step, frame in enumerate(range(frame_start, frame_end + 1)):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        _write_pose(armature, rests, mixamo, mix_rest)
        # O quadril carrega a oscilacao vertical. O deslocamento horizontal e
        # root motion e e descartado (a fisica do jogo move o personagem).
        hips = (mixamo.matrix_world @ mixamo.pose.bones["mixamorig:Hips"].matrix).translation
        if step == 0:
            our_action["hips_start"] = hips.z
        bob = hips.z - float(our_action.get("hips_start", hips.z)) - GROUND_OFFSET
        root = armature.pose.bones["root.x"]
        root.location = rests["root.x"].to_3x3().inverted() @ Vector((0.0, 0.0, bob))
        _keyframe_all(armature, step + 1)

    our_action.use_fake_user = True
    _stash(armature, our_action)
    return frame_end - frame_start + 1


def _build_idle_clip(armature, mixamo_dir: str, clip_name: str) -> int:
    """Gera o repouso a partir do primeiro quadro de uma caminhada.

    O pacote nao trouxe um `Idle`. Sem ele o personagem parado tocava `walking` —
    andando no lugar. Aqui a pose neutra e congelada, com uma respiracao discreta.
    """
    source = os.path.join(mixamo_dir, "Walking.fbx")
    if not os.path.isfile(source):
        return 0
    mixamo, action = _import_mixamo(source)
    if mixamo is None or action is None:
        return 0

    rests = {name: _rest_world(armature, name) for name in ORDER}
    mix_rest = {m: _mixamo_rest(mixamo, m) for m in set(MIXAMO_BONE.values())}

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
        bob = 0.008 * math.sin(step / float(length) * math.tau) - GROUND_OFFSET
        root = armature.pose.bones["root.x"]
        root.location = rests["root.x"].to_3x3().inverted() @ Vector((0.0, 0.0, bob))
        _keyframe_all(armature, 1 + step)

    our_action.use_fake_user = True
    _stash(armature, our_action)
    _discard_mixamo(mixamo)
    return length + 1


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(__doc__)
        return 2
    blend_path, mixamo_dir, output_path, textures_dir = argv[1], argv[2], argv[3], argv[4]

    bpy.ops.wm.open_mainfile(filepath=blend_path)
    our_armature = bpy.data.objects["rig"]
    bpy.context.scene.render.fps = FPS

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

    removed = _strip_constraints(our_armature)
    print("constraints removidas: %d" % removed)
    _reparent(our_armature)
    print("hierarquia de deformacao reconstruida")

    for stale in list(bpy.data.actions):
        bpy.data.actions.remove(stale)
    if our_armature.animation_data:
        for track in list(our_armature.animation_data.nla_tracks):
            our_armature.animation_data.nla_tracks.remove(track)

    retargeted = 0
    for clip_name, filename in CLIP_SOURCES.items():
        if filename == "__IDLE__":
            frames = _build_idle_clip(our_armature, mixamo_dir, clip_name)
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
        frames = _retarget_clip(our_armature, mixamo, action, clip_name)
        print("  retargeted '%s' de '%s' (%d quadros)" % (clip_name, filename, frames))
        retargeted += 1
        _discard_mixamo(mixamo)

    print("total de clipes: %d" % retargeted)
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
    fixed = fix_quaternions(output_path)
    if fixed:
        print("quaternions: %d trocas de sinal corrigidas" % fixed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
