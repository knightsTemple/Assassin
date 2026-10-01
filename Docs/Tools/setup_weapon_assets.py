"""Run in Unreal Python after the user has compiled the new native weapon classes.

Creates configuration blueprints via factories; never calls a compiler or Live Coding.
"""
import json
import unreal

BASE = "/Game/AssassinGirl/Weapon"
FOLDERS = ["Sword", "LongBlade", "Bow", "Shield", "Axe"]


def create_blueprint(path, parent):
    if unreal.EditorAssetLibrary.does_asset_exist(path):
        blueprint = unreal.load_asset(path)
        if not isinstance(blueprint, unreal.Blueprint) or blueprint.get_editor_property("parent_class") != parent:
            raise RuntimeError(f"Existing asset has an unexpected parent: {path}")
        return blueprint
    factory = unreal.BlueprintFactory()
    factory.set_editor_property("parent_class", parent)
    folder, name = path.rsplit("/", 1)
    blueprint = unreal.AssetToolsHelpers.get_asset_tools().create_asset(name, folder, unreal.Blueprint, factory)
    if not isinstance(blueprint, unreal.Blueprint):
        raise RuntimeError(f"Could not create {path}")
    return blueprint


def setup():
    for folder in FOLDERS:
        path = f"{BASE}/{folder}"
        if not unreal.EditorAssetLibrary.does_directory_exist(path):
            if not unreal.EditorAssetLibrary.make_directory(path):
                raise RuntimeError(f"Could not create {path}")

    required = {name: unreal.load_class(None, f"/Script/Assassin.{name}") for name in
                ["AssassinWeaponBase", "AssassinShieldWeaponBase", "AssassinWeaponStatsEffect"]}
    missing = [name for name, value in required.items() if value is None]
    if missing:
        return {"status": "waiting_for_user_compile", "missing_classes": missing,
                "folders": [f"{BASE}/{name}" for name in FOLDERS]}

    effect = create_blueprint(f"{BASE}/GE_WeaponStats", required["AssassinWeaponStatsEffect"])
    effect_class = effect.generated_class()
    effect_defaults = unreal.get_default_object(effect_class)
    if effect_defaults.get_editor_property("duration_policy") != unreal.GameplayEffectDurationType.INFINITE:
        raise RuntimeError("GE_WeaponStats must have infinite duration")
    if effect_defaults.get_editor_property("stacking_type") != unreal.GameplayEffectStackingType.NONE:
        raise RuntimeError("GE_WeaponStats must use no stacking")
    if not unreal.EditorAssetLibrary.save_loaded_asset(effect):
        raise RuntimeError("Could not save GE_WeaponStats")

    base = create_blueprint(f"{BASE}/BP_WeaponBase", required["AssassinWeaponBase"])
    unreal.get_default_object(base.generated_class()).set_editor_property("equipment_stats_effect_class", effect_class)
    if not unreal.EditorAssetLibrary.save_loaded_asset(base):
        raise RuntimeError("Could not save BP_WeaponBase")

    enum = unreal.AssassinWeaponType
    children = [
        ("Sword/BP_SwordBase", base.generated_class(), enum.SWORD),
        ("LongBlade/BP_LongBladeBase", base.generated_class(), enum.LONG_BLADE),
        ("Bow/BP_BowBase", base.generated_class(), enum.BOW),
        ("Shield/BP_ShieldBase", required["AssassinShieldWeaponBase"], enum.SHIELD),
        ("Axe/BP_AxeBase", base.generated_class(), enum.AXE),
    ]
    paths = [f"{BASE}/GE_WeaponStats", f"{BASE}/BP_WeaponBase"]
    for name, parent, weapon_type in children:
        path = f"{BASE}/{name}"
        child = create_blueprint(path, parent)
        defaults = unreal.get_default_object(child.generated_class())
        defaults.set_editor_property("weapon_type", weapon_type)
        defaults.set_editor_property("equipment_stats_effect_class", effect_class)
        if not unreal.EditorAssetLibrary.save_loaded_asset(child):
            raise RuntimeError(f"Could not save {path}")
        paths.append(path)
    return {"status": "complete", "assets": paths}


if __name__ == "__main__":
    print(json.dumps(setup(), ensure_ascii=False))
