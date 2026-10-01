"""Create GAS montages for the existing draw/sheath clips without editing the clips."""
import json
import unreal

BASE = "/Game/AssassinGirl/Animation/Sword"
ACTIONS = [
    ("UEFN_Ninja_Idle_Standing_Unsheathe_to_Chudan", "AM_Sword_Unsheathe_to_Chudan"),
    ("UEFN_Ninja_Idle_Chudan_Sheathe_to_Standing", "AM_Sword_Sheathe_to_Standing"),
]


def prepare():
    assets = unreal.AssetToolsHelpers.get_asset_tools()
    report = []
    attack = unreal.load_asset("/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_1_DownSlash_RM")
    expected_skeleton = attack.get_editor_property("skeleton")
    for source_name, montage_name in ACTIONS:
        source = unreal.load_asset(f"{BASE}/{source_name}")
        if not isinstance(source, unreal.AnimSequence):
            raise RuntimeError(f"Missing sword animation: {source_name}")
        if source.get_editor_property("skeleton") != expected_skeleton:
            raise RuntimeError(f"Incompatible skeleton: {source_name}")
        destination = f"{BASE}/Montages/{montage_name}"
        montage = unreal.load_asset(destination) if unreal.EditorAssetLibrary.does_asset_exist(destination) else None
        if montage is None:
            factory = unreal.AnimMontageFactory()
            factory.source_animation = source
            factory.target_skeleton = expected_skeleton
            montage = assets.create_asset(montage_name, f"{BASE}/Montages", unreal.AnimMontage, factory)
        if not isinstance(montage, unreal.AnimMontage):
            raise RuntimeError(f"Could not prepare sword montage: {destination}")
        for name in ("blend_in", "blend_out"):
            blend = montage.get_editor_property(name)
            blend.set_editor_property("blend_time", 0.08)
            montage.set_editor_property(name, blend)
        if not unreal.EditorAssetLibrary.save_loaded_asset(montage):
            raise RuntimeError(f"Could not save sword montage: {destination}")
        report.append({"source": source.get_path_name(), "montage": montage.get_path_name(),
                       "length": montage.get_play_length(), "blend": 0.08})
    return report


if __name__ == "__main__":
    print(json.dumps(prepare(), ensure_ascii=False))
