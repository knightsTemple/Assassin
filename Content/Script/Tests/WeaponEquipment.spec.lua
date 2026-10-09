-- 在 Content/Script 下以 Lua 5.4 运行。模拟 Actor/GE，验证栏位事务。
local BaseClass = {}
UE = {
    UKismetSystemLibrary = { IsValid = function(Object) return Object ~= nil and not Object.Invalid end },
    UClass = { Load = function(Path)
        assert(type(Path) == "string" and Path ~= "")
        return BaseClass
    end },
    EAssassinWeaponType = { Sword = 0, LongBlade = 1, Bow = 2, Shield = 3, Axe = 4 },
}
local EffectClass = { GetDefaultObject = function() return { StackingType = 0, DurationPolicy = 1 } end }
UE.EGameplayEffectStackingType = { None = 0 }
UE.EGameplayEffectDurationType = { Infinite = 1, HasDuration = 2 }
UE.UAssassinWeaponGASLibrary = {
    MakeWeaponEffectContext = function(_, Weapon) return Weapon end,
    IsSpecValid = function(Spec) return Spec ~= nil end,
    IsEffectHandleValid = function(Handle) return Handle ~= nil end,
    GetEquipmentDataTag = function(Tag) return Tag end,
}
local ASC = {}
function ASC:MakeOutgoingSpec(Class, Level, Context) return { Class = Class, Values = {} } end
function ASC:BP_ApplyGameplayEffectSpecToSelf(Spec) return { Spec = Spec, Active = true } end
function ASC:RemoveActiveGameplayEffect(Handle) Handle.Active = false end
UE.UAbilitySystemBlueprintLibrary = {
    GetAbilitySystemComponent = function() return ASC end,
    AssignTagSetByCallerMagnitude = function(Spec, Tag, Value) Spec.Values[Tag] = Value; return Spec end,
}
local Equipment = require("Weapon.WeaponEquipment")
local function Fixture()
    local Owner = { Effects = 0 }
    return Owner, assert(Equipment.New(Owner))
end
local function Weapon(Type)
    local W = { WeaponType = Type or 0, Equips = 0,
        EquipmentStatsEffectClass = EffectClass, EffectLevel = 1,
        AdditionalEffects = { Num = function() return 0 end }, }
    function W:MakeBaseStatsValues() return { AttackPower = 10 } end
    function W:IsA(Class) return Class == BaseClass end
    function W:AttachForEquipment(Owner)
        if self.FailEquip then return false end
        if self.EquippedCharacter then return self.EquippedCharacter == Owner end
        self.EquippedCharacter = Owner
        Owner.Effects = Owner.Effects + 1
        self.Equips = self.Equips + 1
        if self.OnEquip then self.OnEquip() end
        return true
    end
    function W:DetachForEquipment()
        if self.FailUnequip then return false end
        if self.EquippedCharacter then
            self.EquippedCharacter.Effects = self.EquippedCharacter.Effects - 1
        end
        self.EquippedCharacter = nil
        return true
    end
    return W
end

local Owner, System = Fixture()
local Sword, Axe = Weapon(0), Weapon(4)
assert(System:Equip(Sword))
assert(Owner.HandheldWeapon == Sword and Owner.Effects == 1)
assert(System:Equip(Sword) and Sword.Equips == 1 and Owner.Effects == 1)
assert(System:Equip(Axe))
assert(Owner.HandheldWeapon == Axe and Sword.EquippedCharacter == nil and Owner.Effects == 1)

local Broken = Weapon(0)
Broken.FailEquip = true
assert(not System:Equip(Broken))
assert(Owner.HandheldWeapon == Axe and Axe.EquippedCharacter == Owner and Owner.Effects == 1)
Axe.FailUnequip = true
assert(not System:Equip(Sword) and Owner.HandheldWeapon == Axe)
Axe.FailUnequip = false

local Shield, Bow, Blade = Weapon(3), Weapon(2), Weapon(0)
assert(not System:Equip(Bow, "HandheldWeapon"))
assert(System:Equip(Shield) and System:Equip(Bow))
assert(System:Equip(Blade, "HiddenBladeWeapon") and Owner.Effects == 4)
assert(not System:Equip(Axe, "HiddenBladeWeapon"))
local Other, OtherSystem = Fixture()
assert(not OtherSystem:Equip(Axe) and Other.Effects == 0)
-- 故意传入不符合接口类型的值，验证运行时参数校验。
---@diagnostic disable-next-line: param-type-mismatch
assert(not System:Equip(nil))
---@diagnostic disable-next-line: param-type-mismatch
assert(not System:Unequip("BadSlot"))
Owner.Invalid = true
assert(not System:Unequip("HandheldWeapon") and Owner.Effects == 4)
Owner.Invalid = nil
assert(System:Unequip("BowWeapon") and Owner.Effects == 3)
assert(System:Unequip("BowWeapon") and Owner.Effects == 3)

Owner.AttackSystem = { ActiveAttack = {} }
assert(not System:Equip(Sword) and Owner.HandheldWeapon == Axe)
assert(not System:Unequip("HandheldWeapon") and Owner.HandheldWeapon == Axe)
Owner.AttackSystem.ActiveAttack = nil

local Reentrant = Weapon(4)
Reentrant.OnEquip = function() assert(not System:Unequip("ShieldWeapon")) end
assert(System:Equip(Reentrant) and Owner.ShieldWeapon == Shield)
System:Destroy()
assert(Owner.Effects == 0 and Owner.HandheldWeapon == nil and Owner.HiddenBladeWeapon == nil)
System:Destroy()
assert(not System:Equip(Sword))

local ConfigOwner, ConfigSystem = Fixture()
ConfigOwner.HandheldWeapon = Weapon(0)
ConfigOwner.BowWeapon = Weapon(2)
assert(ConfigSystem:EquipConfigured() and ConfigOwner.Effects == 2)
assert(ConfigSystem:EquipConfigured() and ConfigOwner.Effects == 2)
ConfigOwner.Invalid = true
ConfigSystem:Destroy()
assert(ConfigOwner.Effects == 0)

local RollOwner, RollSystem = Fixture()
local Old = Weapon(0)
assert(RollSystem:Equip(Old))
Old.FailEquip = true
assert(not RollSystem:Equip(Broken))
assert(RollOwner.HandheldWeapon == nil and RollOwner.Effects == 0)
print("PASS: equip, idempotence, swap, rollback, slots, ownership, invalid owner, reentry, cleanup")

-- 验证角色入口和生命周期接入。
UnLua = { Class = function(SuperModule) return {} end }
package.loaded["Combat.attack.AttackSystem"] = { New = function() return {
    GrantAbilities = function() end, Destroy = function() end,
} end }
package.loaded["UnLua.EnhancedInput"] = { BindAction = function() end }

local Character = require("Character.BP_AssassinGirl")
local Girl = setmetatable({ Overridden = { ReceiveEndPlay = function() end }, Effects = 0 }, { __index = Character })
function Girl:GetAssassinAttributeSet() return {} end
assert(not Girl:EquipWeapon(Weapon(0)))
Girl:OnGASInitialized()
local CharacterEvents, CharacterCloth = Girl.Events, Girl.ClothCollision
Girl:OnGASInitialized()
assert(Girl.Events == CharacterEvents and Girl.ClothCollision == CharacterCloth)
assert(Girl:EquipWeapon(Weapon(4)) and Girl.Effects == 1)
assert(Girl:UnequipWeapon("HandheldWeapon") and Girl.Effects == 0)
assert(Girl:EquipWeapon(Weapon(0)))
Girl:ReceiveEndPlay(0)
assert(Girl.Effects == 0 and Girl.WeaponEquipment == nil)
assert(Girl.Events == nil and Girl.ClothCollision == nil and CharacterEvents.Destroyed and CharacterCloth.Destroyed)
Girl:OnGASInitialized()
assert(Girl.Events == nil, "late GAS initialization must not recreate modules after EndPlay")
print("PASS: BP_AssassinGirl GAS initialization, equip/unequip wrappers and EndPlay")

local DefaultOwner, DefaultSystem = Fixture()
local DefaultAxe = Weapon(4)
DefaultOwner.DefaultHandheldWeapon = { ChildActor = DefaultAxe }
assert(DefaultSystem:EquipDefaultHandheld())
assert(DefaultOwner.HandheldWeapon == DefaultAxe and DefaultOwner.Effects == 1)
assert(DefaultSystem:EquipDefaultHandheld() and DefaultOwner.Effects == 1)
local Replacement = Weapon(0)
assert(DefaultSystem:Equip(Replacement))
assert(DefaultSystem:EquipDefaultHandheld() and DefaultOwner.HandheldWeapon == Replacement)
DefaultSystem:Destroy()
assert(DefaultOwner.Effects == 0)
print("PASS: blueprint-selected default axe equips once and respects replacement")

local MissingOwner, MissingSystem = Fixture()
MissingOwner.DefaultHandheldWeapon = {}
assert(not MissingSystem:EquipDefaultHandheld())
assert(MissingOwner.HandheldWeapon == nil and MissingOwner.Effects == 0)
MissingSystem:Destroy()
print("PASS: ChildActor reflected property and missing child handling")
