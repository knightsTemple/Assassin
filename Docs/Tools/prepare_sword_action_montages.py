"""Prepare draw/sheath montages and an upper-body layer in the active locomotion ABP."""
import json
import unreal

BASE = "/Game/AssassinGirl/Animation/Sword"
ANIM_BP = "/Game/Blueprints/SandboxCharacter_CMC_ABP"
SLOT = "SwordUpperBody"
CACHE = "SwordActionBase"
ACTIONS = [
    ("UEFN_Ninja_Idle_Standing_Unsheathe_to_Chudan", "AM_Sword_Unsheathe_to_Chudan"),
    ("UEFN_Ninja_Idle_Chudan_Sheathe_to_Standing", "AM_Sword_Sheathe_to_Standing"),
]


def checked(result):
    result = json.loads(result)
    if not result.get("success"):
        raise RuntimeError(result)
    return result


def graph_nodes(bp):
    return checked(unreal.MCPythonHelper.get_blueprint_graph_info(bp, "AnimGraph"))["nodes"]


def setup_upper_body(montages):
    bp = unreal.load_asset(ANIM_BP)
    if not isinstance(bp, unreal.AnimBlueprint):
        raise RuntimeError(f"Missing locomotion AnimBlueprint: {ANIM_BP}")
    nodes = graph_nodes(bp)
    # These tags identify our nodes without depending on Unreal's generated names.
    def ensure(class_name, tag, x, y, properties=None, **extra):
        matches = [
            n for n in graph_nodes(bp)
            if n["node_class"] == class_name
            and unreal.find_object(None, f"{bp.get_path_name()}:AnimGraph.{n['node_name']}").get_editor_property("tag") == tag
        ]
        if len(matches) > 1:
            raise RuntimeError(f"Duplicate sword-layer node: {tag}")
        spec = dict(type="AnimGraphNode", class_path=f"/Script/AnimGraph.{class_name}",
                    pos_x=x, pos_y=y, properties=properties or {}, **extra)
        if matches:
            spec["existing_node"] = matches[0]["node_name"]
        result = checked(unreal.MCPythonHelper.add_blueprint_node(bp, "AnimGraph", json.dumps(spec)))
        name = result["node_name"]
        node = unreal.find_object(None, f"{bp.get_path_name()}:AnimGraph.{name}")
        if not node:
            raise RuntimeError(f"Cannot locate authored node: {name}")
        node.set_editor_property("tag", tag)
        return name

    default_slots = [
        n for n in nodes
        if n["node_class"] == "AnimGraphNode_Slot" and "'DefaultSlot'" in n["node_title"]
    ]
    if len(default_slots) != 1:
        raise RuntimeError("Expected exactly one full-body DefaultSlot.")
    full_slot = default_slots[0]["node_name"]
    offsets = [n for n in nodes if n["node_class"] == "AnimGraphNode_OffsetRootBone"]
    if len(offsets) != 1:
        raise RuntimeError("Expected exactly one locomotion Offset Root Bone.")
    output = offsets[0]["node_name"]

    save = ensure("AnimGraphNode_SaveCachedPose", "Sword layer: cached full-body base", -980, 440,
                  {"CacheName": CACHE})
    base = ensure("AnimGraphNode_UseCachedPose", "Sword layer: lower-body base", -720, 460,
                  cache_node=save)
    source = ensure("AnimGraphNode_UseCachedPose", "Sword layer: slot source", -1120, 720,
                    cache_node=save)
    slot = ensure("AnimGraphNode_Slot", "Sword layer: draw and sheathe only", -860, 720,
                  {"Node": f"(SlotName={SLOT},bAlwaysUpdateSourcePose=True)"},
                  montage_paths=[m.get_path_name() for m in montages])
    layer = ensure("AnimGraphNode_LayeredBoneBlend", "Sword layer: spine_01 and descendants", -420, 440,
                   {"Node": "(BlendPoses=(()),BlendWeights=(1.0),"
                    "LayerSetup=((BranchFilters=((BoneName=spine_01,BlendDepth=3)))),"
                    "bMeshSpaceRotationBlend=True,bBlendRootMotionBasedOnRootBone=True,"
                    "CurveBlendOption=UseBasePose)"})
    for src, src_pin, dst, dst_pin in [
        (full_slot, "Pose", save, "Pose"),
        (base, "Pose", layer, "BasePose"),
        (source, "Pose", slot, "Source"),
        (slot, "Pose", layer, "BlendPoses_0"),
        (layer, "Pose", output, "Source"),
    ]:
        checked(unreal.MCPythonHelper.connect_blueprint_pins(bp, "AnimGraph", src, src_pin, dst, dst_pin))
    checked(unreal.MCPythonHelper.compile_blueprint(bp))
    for asset in [bp, bp.get_editor_property("target_skeleton"), *montages]:
        if not unreal.EditorAssetLibrary.save_loaded_asset(asset):
            raise RuntimeError(f"Could not save {asset.get_path_name()}")
    return {"anim_blueprint": ANIM_BP, "slot": SLOT, "bone": "spine_01", "blend_depth": 3}


def prepare():
    assets = unreal.AssetToolsHelpers.get_asset_tools()
    report = []
    montages = []
    attack = unreal.load_asset("/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_1_DownSlash_RM")
    expected_skeleton = attack.get_editor_property("skeleton")
    for source_name, montage_name in ACTIONS:
        source = unreal.load_asset(f"{BASE}/{source_name}")
        if not isinstance(source, unreal.AnimSequence):
            raise RuntimeError(f"Missing sword animation: {source_name}")
        if source.get_editor_property("skeleton") != expected_skeleton:
            raise RuntimeError(f"Incompatible skeleton: {source_name}")
        if source.get_editor_property("enable_root_motion"):
            raise RuntimeError(f"Sword upper-body animation must not drive root motion: {source_name}")
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
        montages.append(montage)
        report.append({"source": source.get_path_name(), "montage": montage.get_path_name(),
                       "length": montage.get_play_length(), "blend": 0.08, "slot": SLOT})
    return {"montages": report, "layer": setup_upper_body(montages)}


if __name__ == "__main__":
    print(json.dumps(prepare(), ensure_ascii=False))
