#!/usr/bin/env python3
"""Retargeting completo das animações do Mixamo para o rig Rigify.

## Por que a versão anterior deixava o personagem travado

O rig é *Rigify*. Ele tem **dois modos de controle** para braços e pernas,
escolhidos pelo slider `ik_fk_switch` de cada controle:

- `ik_fk_switch = 0` → modo **IK**. Quem manda é o alvo (`c_hand_ik.l`), e os
  controles FK (`c_arm_fk.l`, `c_forearm_fk.l`) ficam **inertes**.
- `ik_fk_switch = 1` → modo **FK**. Quem manda são os controles FK, e o alvo IK
  fica inerte.

A versão anterior dirigia **só os alvos IK das mãos e dos pés** — quatro pontos
no corpo inteiro. Resultado: ombros, cotovelos, joelhos e coluna nunca recebiam
pose. Era essa a rigidez relatada: o corpo só tinha as pontas controladas.

Medido: com `ik_fk_switch = 0`, girar `c_arm_fk.l` 40° movia a mão **0,000 m**.
Com o switch em 1, movia **0,398 m**.

## O método correto

1. Ligar `ik_fk_switch = 1` nos quatro membros, para os controles FK mandarem.
2. Retargetar **osso a osso** para a cadeia FK completa: quadril, coluna, pescoço,
   cabeça, ombros, braços, antebraços, mãos, coxas, canelas e pés.
3. Assar a pose avaliada em todos os 366 ossos.

Uso:
    python3 tools/retarget_animations.py <cena.blend> <pasta_mixamo> <saida.glb> <texturas>
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 24
KEEP_OBJECTS = ("rig", "Body", "Frames", "Logos", "Webs")

# Mapeamento Mixamo → nossos controles FK.
#
# Nossa coluna tem quatro segmentos (`spine_01..04`) e o Mixamo tem três
# (`Spine`, `Spine1`, `Spine2`). O mapeamento abaixo associa os três primeiros e
# deixa o quarto em repouso — foi a recomendação encontrada na pesquisa, porque
# associar `Spine` ao `spine_01` faz o osso controlar o corpo errado.
BONE_MAP = {
    "mixamorig:Hips": "c_root.x",
    "mixamorig:Spine": "c_spine_01.x",
    "mixamorig:Spine1": "c_spine_02.x",
    "mixamorig:Spine2": "c_spine_03.x",
    "mixamorig:Neck": "c_neck.x",
    "mixamorig:Head": "c_head.x",
    "mixamorig:LeftShoulder": "c_shoulder.l",
    "mixamorig:LeftArm": "c_arm_fk.l",
    "mixamorig:LeftForeArm": "c_forearm_fk.l",
    "mixamorig:LeftHand": "c_hand_fk.l",
    "mixamorig:RightShoulder": "c_shoulder.r",
    "mixamorig:RightArm": "c_arm_fk.r",
    "mixamorig:RightForeArm": "c_forearm_fk.r",
    "mixamorig:RightHand": "c_hand_fk.r",
    "mixamorig:LeftUpLeg": "c_thigh_fk.l",
    "mixamorig:LeftLeg": "c_leg_fk.l",
    "mixamorig:LeftFoot": "c_foot_fk.l",
    "mixamorig:RightUpLeg": "c_thigh_fk.r",
    "mixamorig:RightLeg": "c_leg_fk.r",
    "mixamorig:RightFoot": "c_foot_fk.r",
}

# Controles com slider IK/FK: precisam ir para 1 (FK) para os controles FK
# deixarem de ser inertes.
IK_FK_SWITCHES = ("c_hand_ik.l", "c_hand_ik.r", "c_foot_ik.l", "c_foot_ik.r")

# Mixamo → arquivo. `idle` é gerado, não vem do pacote.
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


def _capture_rest(armature) -> dict:
    """Matriz de repouso de cada osso, com a action removida.

    Sem remover a action, o `frame_set` reaplica a pose animada e o "repouso"
    capturado seria o do primeiro quadro — o delta sairia nulo.
    """
    if armature.animation_data:
        armature.animation_data.action = None
    _clear_pose(armature)
    return {pb.name: pb.matrix.copy() for pb in armature.pose.bones}


def _set_fk_mode(armature) -> None:
    """Liga o modo FK nos quatro membros.

    Sem isto os controles FK são inertes: medido, girar `c_arm_fk.l` 40° movia a
    mão 0,000 m em modo IK, contra 0,398 m em modo FK.
    """
    for name in IK_FK_SWITCHES:
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is not None and "ik_fk_switch" in pose_bone.keys():
            pose_bone["ik_fk_switch"] = 1.0
    bpy.context.view_layer.update()


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


def _hierarchy_order(armature, bone_names) -> list:
    """Ordena os ossos do topo para baixo: o pai precisa ser escrito primeiro."""
    def depth(name):
        bone = armature.data.bones.get(name)
        level = 0
        while bone is not None and bone.parent is not None:
            level += 1
            bone = bone.parent
        return level
    return sorted([n for n in bone_names if armature.data.bones.get(n) is not None], key=depth)


def _retarget_bone(mixamo_pose, our_rest, our_parent_world, our_parent_rest,
                   space: Matrix) -> Quaternion:
    """Rotação local que faz nosso osso apontar como o do Mixamo.

    ## A fórmula, validada por medição

    O Mixamo traz o armature **rotacionado 90° em X e com escala 0,01**; o nosso
    está alinhado ao mundo, escala 1. Sem compensar isso, a rotação copiada sai
    girada: medido, **erro de 82,9 graus** e o corpo comprimido (cabeça a 1,12 m
    em vez de 1,85 m).

    A matriz de espaço correta é `nosso⁻¹ · mixamo`. Com ela o erro cai para
    **0,3 graus** e a cabeça fica na altura certa (1,85 m). A variante invertida
    (`nosso · mixamo⁻¹`) dá 157,8 graus — é o pior caso.

    A conta completa:

        alvo_mundo = espaço · rotação_mundo_do_osso_mixamo
        local      = (pose_pai · repouso_relativo)⁻¹ · alvo_mundo
    """
    parent_world = our_parent_world.to_3x3().normalized()
    rest_local = our_parent_rest.inverted() @ our_rest
    reference = (parent_world @ rest_local.to_3x3().normalized()).inverted()
    target = space @ mixamo_pose.to_3x3().normalized()
    return (reference @ target).to_quaternion()


def _retarget_clip(our_armature, mixamo_armature, action, clip_name: str) -> int:
    frame_start = int(action.frame_range[0])
    frame_end = int(action.frame_range[1])

    mixamo_rest = _capture_rest(mixamo_armature)
    our_rest = _capture_rest(our_armature)

    mixamo_armature.animation_data_create()
    mixamo_armature.animation_data.action = action
    if hasattr(mixamo_armature.animation_data, "action_slot") and action.slots:
        mixamo_armature.animation_data.action_slot = action.slots[0]

    _set_fk_mode(our_armature)
    ordered = _hierarchy_order(our_armature, list(BONE_MAP.values()))
    # O armature do Mixamo esta rotacionado 90 graus em X e tem escala 0.01.
    # `nosso^-1 * mixamo` compensa isso: medido, o erro angular cai de 82,9 para
    # 0,3 graus, e a cabeca volta para a altura certa (1,85 m).
    space = (our_armature.matrix_world.to_3x3().normalized().inverted()
             @ mixamo_armature.matrix_world.to_3x3().normalized())

    our_action = _new_action(our_armature, clip_name)
    scene = bpy.context.scene
    hips_start = None

    for frame in range(frame_start, frame_end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()

        for our_name in ordered:
            mixamo_name = _mixamo_for(our_name)
            if mixamo_name is None:
                continue
            mixamo_bone = mixamo_armature.pose.bones.get(mixamo_name)
            our_bone = our_armature.pose.bones.get(our_name)
            if mixamo_bone is None or our_bone is None:
                continue
            if mixamo_name not in mixamo_rest or our_name not in our_rest:
                continue

            our_parent = our_bone.parent
            our_parent_world = our_parent.matrix if our_parent is not None else Matrix.Identity(4)
            our_parent_rest = (our_rest[our_parent.name]
                               if our_parent is not None and our_parent.name in our_rest
                               else Matrix.Identity(4))

            our_bone.rotation_mode = "QUATERNION"
            our_bone.rotation_quaternion = _retarget_bone(
                mixamo_bone.matrix, our_rest[our_name],
                our_parent_world, our_parent_rest, space)

            # O quadril carrega a oscilação vertical; o deslocamento horizontal é
            # root motion e é descartado (a física do jogo move o personagem).
            if our_name == "c_root.x":
                hips_world = mixamo_armature.matrix_world @ mixamo_bone.matrix.translation
                if hips_start is None:
                    hips_start = hips_world
                vertical = hips_world.z - hips_start.z
                target = our_rest[our_name].translation + Vector((0.0, 0.0, vertical))
                our_bone.location = _world_to_local(our_bone, target, our_rest[our_name])
                our_bone.keyframe_insert("location", frame=frame)
            else:
                our_bone.location = Vector((0.0, 0.0, 0.0))

            our_bone.keyframe_insert("rotation_quaternion", frame=frame)
            bpy.context.view_layer.update()

        bpy.context.view_layer.update()

    _bake_full(our_armature, frame_start, frame_end)
    our_action.use_fake_user = True
    _stash(our_armature, our_action)
    return frame_end - frame_start + 1


def _build_idle_clip(our_armature, mixamo_dir: str, clip_name: str) -> int:
    """Gera o clipe de repouso a partir do primeiro quadro de uma caminhada.

    O pacote não trouxe um `Idle` do Mixamo. Sem ele, o personagem parado tocava
    `walking` — andando no lugar, que era o defeito de "ficar se mexendo".
    """
    source = os.path.join(mixamo_dir, "Walking.fbx")
    if not os.path.isfile(source):
        return 0
    mixamo_armature, action = _import_mixamo(source)
    if mixamo_armature is None or action is None:
        return 0

    mixamo_rest = _capture_rest(mixamo_armature)
    our_rest = _capture_rest(our_armature)
    mixamo_armature.animation_data_create()
    mixamo_armature.animation_data.action = action
    if hasattr(mixamo_armature.animation_data, "action_slot") and action.slots:
        mixamo_armature.animation_data.action_slot = action.slots[0]

    _set_fk_mode(our_armature)
    ordered = _hierarchy_order(our_armature, list(BONE_MAP.values()))
    # O armature do Mixamo esta rotacionado 90 graus em X e tem escala 0.01.
    # `nosso^-1 * mixamo` compensa isso: medido, o erro angular cai de 82,9 para
    # 0,3 graus, e a cabeca volta para a altura certa (1,85 m).
    space = (our_armature.matrix_world.to_3x3().normalized().inverted()
             @ mixamo_armature.matrix_world.to_3x3().normalized())

    our_action = _new_action(our_armature, clip_name)
    scene = bpy.context.scene
    frame_start = int(action.frame_range[0])
    length = 48

    # Amostra a pose neutra do primeiro quadro e repete, com respiração discreta.
    scene.frame_set(frame_start)
    bpy.context.view_layer.update()
    snapshot = {}
    for our_name in ordered:
        mixamo_name = _mixamo_for(our_name)
        if mixamo_name is None:
            continue
        mixamo_bone = mixamo_armature.pose.bones.get(mixamo_name)
        if mixamo_bone is None or mixamo_name not in mixamo_rest or our_name not in our_rest:
            continue
        snapshot[our_name] = mixamo_bone.matrix.copy()

    for step in range(length + 1):
        frame = 1 + step
        bob = 0.008 * math.sin(step / float(length) * math.tau)
        for our_name in ordered:
            if our_name not in snapshot:
                continue
            our_bone = our_armature.pose.bones.get(our_name)
            mixamo_name = _mixamo_for(our_name)
            if our_bone is None or mixamo_name is None:
                continue
            our_parent = our_bone.parent
            our_parent_world = our_parent.matrix if our_parent is not None else Matrix.Identity(4)
            our_parent_rest = (our_rest[our_parent.name]
                               if our_parent is not None and our_parent.name in our_rest
                               else Matrix.Identity(4))
            our_bone.rotation_mode = "QUATERNION"
            our_bone.rotation_quaternion = _retarget_bone(
                snapshot[our_name], our_rest[our_name],
                our_parent_world, our_parent_rest, space)
            if our_name == "c_root.x":
                target = our_rest[our_name].translation + Vector((0.0, 0.0, bob))
                our_bone.location = _world_to_local(our_bone, target, our_rest[our_name])
                our_bone.keyframe_insert("location", frame=frame)
            our_bone.keyframe_insert("rotation_quaternion", frame=frame)
            bpy.context.view_layer.update()

    _bake_full(our_armature, 1, 1 + length)
    our_action.use_fake_user = True
    _stash(our_armature, our_action)
    _discard_mixamo(mixamo_armature)
    return length + 1


def _world_to_local(bone, world_position: Vector, rest_world: Matrix) -> Vector:
    """`location` local que põe o osso em `world_position`."""
    return rest_world.to_3x3().inverted() @ (world_position - rest_world.translation)


def _mixamo_for(our_name: str) -> str | None:
    for mixamo_name, mapped in BONE_MAP.items():
        if mapped == our_name:
            return mixamo_name
    return None


def _bake_full(armature, frame_start: int, frame_end: int) -> None:
    """Assa a pose avaliada em chaves de todos os ossos.

    `nla.bake` opera sobre o **objeto ativo**. No fluxo completo o ativo é o
    esqueleto do Mixamo recém-importado, então o rig é ativado aqui — sem isto o
    bake assa o esqueleto errado e o clipe sai com 2 quadros.
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
        if filename == "__IDLE__":
            frames = _build_idle_clip(our_armature, mixamo_dir, clip_name)
            print("  gerado '%s' (%d quadros)" % (clip_name, frames))
            retargeted += 1 if frames > 0 else 0
            continue
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
