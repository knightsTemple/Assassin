-- 使用真实 WeaponBase/WeaponEquipment，替换引擎接口验证 GE 的完整生命周期。
UnLua = { Class = function() return {} end }
local function Array(Items)
    Items = Items or {}
    function Items:Num() return #self end
    function Items:Get(Index) return self[Index] end
    return Items
end
local Class = { GetDefaultObject = function() return { StackingType = 0, DurationPolicy = 1 } end }
UE = {
    UKismetSystemLibrary = { IsValid = function(Object) return Object ~= nil and not Object.Invalid end },
    UClass = { Load = function() return Class end },
    FAssassinWeaponStats = function() return {} end,
    EAssassinWeaponType = { Sword = 0, LongBlade = 1, Bow = 2, Shield = 3, Axe = 4 },
    EGameplayEffectStackingType = { None = 0 },
    EGameplayEffectDurationType = { Infinite = 1, HasDuration = 2 },
    EAttachmentRule = { SnapToTarget = 0, KeepRelative = 1 },
    EDetachmentRule = { KeepWorld = 0 },
    FGameplayTag = {}, float = {},
    -- 与 UnLua 构造接口一致：接收键类型和值类型，避免语言服务推断为无参数函数。
    TMap = function(KeyType, ValueType)
        assert(KeyType == UE.FGameplayTag and ValueType == UE.float)
        return { Add = function(self, Key, Value) self[Key] = Value end }
    end,
    UAssassinWeaponGASLibrary = {
        GetEquipmentDataTag = function(Tag) return Tag end,
        MakeWeaponEffectContext = function(_, Weapon) return Weapon end,
        IsSpecValid = function(Spec) return Spec ~= nil end,
        IsEffectHandleValid = function(Handle) return Handle ~= nil end,
    },
    UAbilitySystemBlueprintLibrary = {
        GetAbilitySystemComponent = function(Owner) return Owner.ASC end,
        AssignTagSetByCallerMagnitude = function(Spec, Tag, Value) Spec.Values[Tag] = Value; return Spec end,
        GetActiveGameplayEffectStackCount = function(Handle) return Handle.Active and 1 or 0 end,
    },
}
local Base = require("Weapon.WeaponBase")
local Equipment = require("Weapon.WeaponEquipment")
local function Fixture()
    local ASC = { Handles = {}, Applies = 0 }
    function ASC:MakeOutgoingSpec(Effect, Level, Context)
        return { Effect = Effect, Values = {}, Weapon = Context }
    end
    function ASC:BP_ApplyGameplayEffectSpecToSelf(Spec)
        self.Applies = self.Applies + 1
        if Spec.Effect.Fail then return nil end
        if Spec.Effect.Throw then error("simulated GE failure") end
        local Handle = { Active = true, Spec = Spec }
        self.Handles[#self.Handles + 1] = Handle
        return Handle
    end
    function ASC:RemoveActiveGameplayEffect(Handle) Handle.Active = false end
    function ASC:UpdateActiveGameplayEffectSetByCallerMagnitudes(Handle, Values)
        if self.FailRefresh then error("simulated refresh failure") end
        Handle.Spec.Values = Values
    end
    local Owner = { ASC = ASC, Mesh = { DoesSocketExist = function() return true end } }
    Owner.WeaponEquipment = Equipment.New(Owner)
    return Owner, Owner.WeaponEquipment, ASC
end
local function Weapon()
    local W = setmetatable({ WeaponType = 0, WeaponLevel = 1, EffectLevel = 1,
        BaseStats = {}, StatGrowthCurves = { AttackPower = { GetFloatValue = function(_, Level) return Level * 10 end } },
        EquipmentStatsEffectClass = Class, AdditionalEffects = Array({Class}), EquipSocketName = "Back",
        Overridden = { ReceiveEndPlay = function() end },
    }, { __index = Base })
    function W:IsA() return true end
    function W:IsShieldWeapon() return false end
    function W:GetMaxHealthBonus() return 0 end
    function W:SetOwner(Owner) self.ActorOwner = Owner end
    function W:K2_AttachToComponent() self.Attached = not self.FailAttach; return self.Attached end
    function W:K2_DetachFromActor() self.Attached = false end
    function W:OnWeaponEquipped() self.EquipEvents = (self.EquipEvents or 0) + 1 end
    function W:OnWeaponUnequipped() self.UnequipEvents = (self.UnequipEvents or 0) + 1 end
    W:ReceiveBeginPlay()
    return W
end
local function ActiveCount(ASC)
    local Count = 0
    for _, Handle in ipairs(ASC.Handles) do if Handle.Active then Count = Count + 1 end end
    return Count
end
local Owner, Manager, ASC = Fixture()
local W = Weapon()
assert(W:SetWeaponLevel(2) and ASC.Applies == 0)
assert(W:EquipToCharacter(Owner) and Owner.HandheldWeapon == W)
local Record = Manager.Records[W]
assert(Record and Record.ASC == ASC and #Record.Handles == 2)
assert(W._EquipmentASC == nil and W._EquipmentHandles == nil and W._BaseStatsEffectHandle == nil)
local Handle = Record.BaseStatsHandle
assert(Handle.Spec.Values['Assassin.Data.Equipment.AttackPower'] == 20)
assert(W:EquipToCharacter(Owner) and ASC.Applies == 2 and W.EquipEvents == 1)
assert(W:SetWeaponLevel(5) and Handle.Spec.Values['Assassin.Data.Equipment.AttackPower'] == 50)
assert(Manager.Records[W].BaseStatsHandle == Handle and ActiveCount(ASC) == 2)
ASC.FailRefresh = true
assert(not W:SetWeaponLevel(6) and W.WeaponLevel == 5 and not Manager.Busy)
ASC.FailRefresh = false
Manager.Busy = true
assert(not W:SetWeaponLevel(8) and W.WeaponLevel == 5)
Manager.Busy = false
Owner.AttackSystem = { ActiveAttack = {} }
assert(not W:UnequipFromCharacter() and ActiveCount(ASC) == 2)
Owner.AttackSystem = nil

-- 新武器的附加 GE 失败或抛异常时，撤销部分效果并恢复旧武器。
for _, Failure in ipairs({'Fail', 'Throw'}) do
    local Broken = Weapon()
    Broken.AdditionalEffects = Array({setmetatable({ [Failure] = true }, { __index = Class })})
    assert(not Manager:Equip(Broken))
    assert(Owner.HandheldWeapon == W and W.EquippedCharacter == Owner and W.Attached)
    assert(not Broken.Attached and Broken.EquippedCharacter == nil and not Manager.Records[Broken])
    assert(ActiveCount(ASC) == 2 and not Manager.Busy)
end
local BadSocket = Weapon()
BadSocket.FailAttach = true
assert(not Manager:Equip(BadSocket) and Owner.HandheldWeapon == W and ActiveCount(ASC) == 2)
assert(W:UnequipFromCharacter() and ActiveCount(ASC) == 0)
assert(Owner.HandheldWeapon == nil and W._EquipmentManager == nil)
assert(W:EquipToCharacter(Owner))
W:ReceiveEndPlay(0)
assert(ActiveCount(ASC) == 0 and Owner.HandheldWeapon == nil and not Manager.Records[W])

-- Actor 已无效、栏位被外部清空时，记录仍足以在角色结束时清理效果。
local Lost = Weapon()
assert(Manager:Equip(Lost))
Owner.HandheldWeapon = nil
Lost.Invalid = true
Owner.Invalid = true
Manager:Destroy()
assert(ActiveCount(ASC) == 0 and next(Manager.Records) == nil)
Manager:Destroy()
print('PASS: real weapon/manager integration, GE ownership, upgrade, rollback, wrappers and destruction')
