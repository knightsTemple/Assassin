"""Run in Unreal Python to author the project's level 1-100 sword balance curves.

Project balance proposal inspired by levelled equipment in AC Odyssey;
these are NOT Ubisoft's proprietary formulas. Rerunning replaces these five curves.
"""
import json
import math
import pathlib
import unreal

MIN_LEVEL = 1
MAX_LEVEL = 100
ROOT = pathlib.Path(unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir()))
FOLDER = "/Game/AssassinGirl/Weapon/Sword/Curves"
FIELDS = {
    "AttackPower": "attack_power",
    "AssassinationPower": "assassination_power",
    "CritDamageBonus": "crit_damage_bonus",
    "CritChance": "crit_chance",
    "Weight": "weight",
}


def values_at(level):
    t = (max(MIN_LEVEL, min(MAX_LEVEL, level)) - MIN_LEVEL) / (MAX_LEVEL - MIN_LEVEL)
    attack = round(20.0 * 60.0 ** t, 4)
    return {
        "AttackPower": attack,
        "AssassinationPower": round(3.0 * attack, 4),
        "CritDamageBonus": round(0.10 + 0.40 * (1.0 - (1.0 - t) ** 1.2), 6),
        "CritChance": round(0.02 + 0.08 * (1.0 - (1.0 - t) ** 1.4), 6),
        "Weight": 2.0,
    }


def generate():
    if unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).is_in_play_in_editor():
        raise RuntimeError("Stop PIE before importing curves.")
    bp = unreal.load_asset("/Game/AssassinGirl/Weapon/Sword/BP_Sword")
    if not isinstance(bp, unreal.Blueprint):
        raise RuntimeError("BP_Sword is missing.")
    rows = [{"level": level, **values_at(level)} for level in range(MIN_LEVEL, MAX_LEVEL + 1)]
    source_dir = ROOT / "Docs/Data/SwordCurves"
    source_dir.mkdir(parents=True, exist_ok=True)
    curves = {}
    for field in FIELDS:
        name = f"CF_Sword_{field}"
        path = f"{FOLDER}/{name}"
        old = unreal.load_asset(path)
        if old:
            unreal.get_editor_subsystem(unreal.AssetEditorSubsystem).close_all_editors_for_asset(old)
        source = source_dir / f"{name}.csv"
        source.write_text("".join(f"{r['level']},{r[field]:.6f}\n" for r in rows), encoding="utf-8")
        factory = unreal.CSVImportFactory()
        factory.set_editor_property("automated_import_settings", unreal.CSVImportSettings(
            import_type=unreal.CSVImportType.ECSV_CURVE_FLOAT))
        task = unreal.AssetImportTask()
        task.filename = str(source)
        task.destination_path = FOLDER
        task.destination_name = name
        task.automated = True
        task.replace_existing = True
        task.save = True
        task.factory = factory
        unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
        curve = unreal.load_asset(path)
        if not isinstance(curve, unreal.CurveFloat):
            raise RuntimeError(f"Curve import failed: {path}")
        previous = -1.0
        for row in rows:
            actual = curve.get_float_value(row["level"])
            if not math.isclose(actual, row[field], rel_tol=1e-6, abs_tol=1e-5):
                raise RuntimeError(f"Incorrect sample: {field} level {row['level']}")
            if actual < previous:
                raise RuntimeError(f"Unexpected decrease: {field}")
            previous = actual
        curves[field] = curve

    cdo = unreal.get_default_object(bp.generated_class())
    growth = cdo.get_editor_property("StatGrowthCurves")
    base = cdo.get_editor_property("base_stats")
    for field, python_name in FIELDS.items():
        growth.set_editor_property(field, curves[field])
        base.set_editor_property(python_name, rows[0][field])
    cdo.set_editor_property("StatGrowthCurves", growth)
    cdo.set_editor_property("base_stats", base)
    result = json.loads(unreal.MCPythonHelper.compile_blueprint(bp))
    if not result.get("success"):
        raise RuntimeError(result)
    if not unreal.EditorAssetLibrary.save_loaded_asset(bp):
        raise RuntimeError("Could not save BP_Sword.")
    (source_dir / "sword_growth_1_100.json").write_text(
        json.dumps({"version": 1, "kind": "project_balance_not_ubisoft_formula", "rows": rows},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    return {"levels": 100, "curves": [c.get_path_name() for c in curves.values()],
            "milestones": [rows[i - 1] for i in [1, 25, 50, 75, 100]]}


if __name__ == "__main__":
    print(json.dumps(generate(), ensure_ascii=False))
