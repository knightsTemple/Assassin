"""Run in Unreal Editor Python. Generate attack copies; never modify source clips.

UEFN clips here store horizontal travel on pelvis and leave foot IK bones static.
Transfer pelvis XY to root and bake foot IK targets from the animated feet.
Keep authored vertical motion (including UppercutSlash's hop) on the body.
"""
import json
import unreal

BASE = "/Game/AssassinGirl/Animation/Combat/Attack"
ATTACKS = ["DownSlash", "UpSlash", "PushKick", "UppercutSlash"]


def generate():
    assets = unreal.AssetToolsHelpers.get_asset_tools()
    options = unreal.AnimPoseEvaluationOptions()
    options.should_retarget = False
    options.extract_root_motion = False
    options.incorporate_root_motion_into_pose = True
    report = []

    for index, attack in enumerate(ATTACKS, 1):
        source = unreal.load_asset(f"{BASE}/UEFN_Ninja_Chudan_Attack_{attack}_Attacker")
        destination = f"{BASE}/RootMotion/AS_LightAttack_{index}_{attack}_RM"
        # Always evaluate the original to make regeneration idempotent.
        model = source.data_model_interface
        frame_rate = model.get_frame_rate()
        frame_count = model.get_number_of_frames()
        poses = [
            unreal.AnimPoseExtensions.get_anim_pose_at_frame(source, frame, options)
            for frame in range(frame_count + 1)
        ]
        get_bone = unreal.AnimPoseExtensions.get_bone_pose
        local = unreal.AnimPoseSpaces.LOCAL
        world = unreal.AnimPoseSpaces.WORLD
        origin = get_bone(poses[0], "pelvis", world).translation
        bone_names = unreal.AnimPoseExtensions.get_bone_names(poses[0])
        root_children = [
            str(bone) for bone in bone_names
            if len(unreal.AnimationLibrary.find_bone_path_to_root(source, bone)) == 2
        ]
        tracks = {bone: [] for bone in root_children + ["root", "ik_foot_l", "ik_foot_r"]}

        for pose in poses:
            old_root = get_bone(pose, "root", local)
            # These four clips have an identity root. Do not silently process other rigs.
            if old_root.translation.length() > 0.001 or abs(old_root.rotation.w) < 0.99999:
                raise RuntimeError(f"Unexpected authored root in {source.get_name()}")
            pelvis = get_bone(pose, "pelvis", world).translation
            offset = unreal.Vector(pelvis.x - origin.x, pelvis.y - origin.y, 0.0)
            new_root = unreal.Transform()
            new_root.translation = offset
            tracks["root"].append(new_root)
            for bone in root_children:
                transform = get_bone(pose, bone, world).make_relative(new_root)
                # Keep IK foot parent at origin; its children now follow the real feet.
                if bone == "ik_foot_root":
                    transform = unreal.Transform()
                tracks[bone].append(transform)
            for side in ("l", "r"):
                tracks[f"ik_foot_{side}"].append(
                    get_bone(pose, f"foot_{side}", world).make_relative(new_root)
                )

        output = unreal.load_asset(destination)
        if output is None:
            output = unreal.EditorAssetLibrary.duplicate_asset(source.get_path_name(), destination)
        if output is None:
            raise RuntimeError(f"Could not create {destination}")
        controller = output.controller
        controller.open_bracket("Prepare light attack root motion and foot IK")
        try:
            for bone, transforms in tracks.items():
                ok = controller.set_bone_track_keys(
                    bone,
                    [t.translation for t in transforms],
                    [t.rotation for t in transforms],
                    [t.scale3d for t in transforms],
                )
                if not ok:
                    raise RuntimeError(f"Could not update {bone} in {destination}")
        finally:
            controller.close_bracket()
        output.set_editor_property("enable_root_motion", True)
        output.set_editor_property("root_motion_root_lock", unreal.RootMotionRootLock.ANIM_FIRST_FRAME)
        output.set_editor_property("force_root_lock", False)
        if not unreal.EditorAssetLibrary.save_loaded_asset(output):
            raise RuntimeError(f"Could not save {destination}")

        montage_path = f"{BASE}/Montages/AM_LightAttack_{index}_{attack}_RM"
        montage = unreal.load_asset(montage_path)
        if montage is None:
            factory = unreal.AnimMontageFactory()
            factory.source_animation = output
            factory.target_skeleton = output.get_editor_property("skeleton")
            folder, name = montage_path.rsplit("/", 1)
            montage = assets.create_asset(name, folder, unreal.AnimMontage, factory)
        if montage is None:
            raise RuntimeError(f"Could not create {montage_path}")
        for property_name in ("blend_in", "blend_out"):
            blend = montage.get_editor_property(property_name)
            blend.set_editor_property("blend_time", 0.12)
            montage.set_editor_property(property_name, blend)
        if not unreal.EditorAssetLibrary.save_loaded_asset(montage):
            raise RuntimeError(f"Could not save {montage_path}")
        final_offset = tracks["root"][-1].translation
        report.append({
            "animation": destination, "montage": montage_path,
            "frames": frame_count, "rate": str(frame_rate),
            "travel_cm": [final_offset.x, final_offset.y, final_offset.z],
        })
    return report


if __name__ == "__main__":
    print(json.dumps(generate(), ensure_ascii=False))
