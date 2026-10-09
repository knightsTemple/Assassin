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
local EventBus = require("Core.EventSubscribe.EventBus")
local EventDefine = require("Core.EventSubscribe.EventDefine")
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
    local Owner = { ASC = ASC, Events = EventBus.New(), Mesh = { DoesSocketExist = function() return true end } }
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

-- 使用真实事件总线验证最终通知；结果在回调外断言，避免被总线异常隔离吞掉。
local EventOwner, EventManager, EventASC = Fixture()
local Notifications, States = {}, {}
EventOwner.Events:Subscribe(EventDefine.WeaponChanged, Notifications, function(_, Data)
    Notifications[#Notifications + 1] = Data
    States[#States + 1] = {
        Weapon = EventOwner[Data.Slot], Effects = ActiveCount(EventASC),
        Busy = EventManager.Busy, Reentered = EventManager:Unequip(Data.Slot),
    }
end)
local First, Second = Weapon(), Weapon()
assert(EventManager:Equip(First))
assert(#Notifications == 1 and Notifications[1].OldWeapon == nil and Notifications[1].NewWeapon == First)
assert(States[1].Weapon == First and States[1].Effects == 2 and States[1].Busy and not States[1].Reentered)
assert(EventManager:Equip(First) and #Notifications == 1, "idempotent equip must not broadcast")
assert(EventManager:Equip(Second))
assert(#Notifications == 2 and Notifications[2].OldWeapon == First and Notifications[2].NewWeapon == Second)
assert(States[2].Weapon == Second and States[2].Effects == 2)
local Failing = Weapon()
Failing.AdditionalEffects = Array({setmetatable({ Fail = true }, { __index = Class })})
assert(not EventManager:Equip(Failing))
assert(#Notifications == 2 and EventOwner.HandheldWeapon == Second, "successful rollback must stay silent")
Second.FailAttach = true
assert(not EventManager:Equip(Failing))
assert(#Notifications == 3 and Notifications[3].Reason == "RollbackFailed")
assert(Notifications[3].OldWeapon == Second and Notifications[3].NewWeapon == nil)
assert(States[3].Weapon == nil and States[3].Effects == 0)
Second.FailAttach = false
assert(EventManager:Equip(Second))
assert(EventManager:Unequip("HandheldWeapon"))
assert(#Notifications == 5 and Notifications[5].Reason == "Unequip" and States[5].Effects == 0)
assert(EventManager:Unequip("HandheldWeapon") and #Notifications == 5)
-- 蓝图预置同一 Actor 引用：第一次实际装配通知，重复初始化不通知。
EventOwner.HandheldWeapon = First
assert(EventManager:EquipConfigured() and #Notifications == 6)
assert(Notifications[6].OldWeapon == nil and Notifications[6].NewWeapon == First)
assert(EventManager:EquipConfigured() and #Notifications == 6)
First.Invalid = true
First:ReceiveEndPlay(0)
assert(#Notifications == 7 and Notifications[7].Reason == "WeaponDestroyed")
assert(States[7].Weapon == nil and States[7].Effects == 0)
assert(EventManager:Equip(Second))
local BeforeDestroy = #Notifications
EventManager:Destroy()
assert(#Notifications == BeforeDestroy and ActiveCount(EventASC) == 0)
print("PASS: committed equipment events, idempotence, rollback, reentry and invalid weapon cleanup")

-- 真实武器发布拔出事件，布料实例订阅处理；覆盖失败挂接、重复状态及角色隔离。
local Collision = require("Weapon.BackClothCollision")
UE.USkeletalMeshComponent, UE.AActor = {}, {}
UE.TArray = function() return Array() end
local VisualOwner, VisualManager = Fixture()
local OtherOwner, OtherManager = Fixture()
local Adds, Removes = 0, 0
local Cape = {
    GetName = function() return "IntegrationCape" end,
    AddClothCollisionSource = function() Adds = Adds + 1 end,
    RemoveClothCollisionSource = function() Removes = Removes + 1 end,
}
function VisualOwner:K2_GetComponentsByClass() return Array({ self.Mesh, Cape }) end
function VisualOwner:GetAllChildActors() end
local Cloth = Collision.New(VisualOwner, VisualOwner.Events)
local VisualWeapon = Weapon()
VisualWeapon.BackClothPhysicsAsset, VisualWeapon.DrawnSocketName = {}, "Hand"
local DrawEvents = {}
VisualOwner.Events:Subscribe(EventDefine.WeaponDrawnChanged, DrawEvents, function(_, Data)
    DrawEvents[#DrawEvents + 1] = Data
end)
assert(VisualManager:Equip(VisualWeapon) and Adds == 1)
assert(VisualWeapon:SetWeaponDrawn(true) and Removes == 1 and #DrawEvents == 1)
assert(DrawEvents[1].Weapon == VisualWeapon and DrawEvents[1].Drawn)
assert(VisualWeapon:SetWeaponDrawn(true) and Removes == 1 and #DrawEvents == 1)
VisualWeapon.FailAttach = true
assert(not VisualWeapon:SetWeaponDrawn(false) and #DrawEvents == 1 and Adds == 1)
VisualWeapon.FailAttach = false
assert(VisualWeapon:SetWeaponDrawn(false) and Adds == 2 and #DrawEvents == 2)
assert(not DrawEvents[2].Drawn)
assert(OtherManager:Equip(Weapon()) and Adds == 2 and Removes == 1)
-- 子模型更换仍由模块内部低频刷新发现。
Cape = {
    GetName = function() return "ReplacementCape" end,
    AddClothCollisionSource = function() Adds = Adds + 1 end,
    RemoveClothCollisionSource = function() Removes = Removes + 1 end,
}
Cloth:Tick(0.1)
assert(Adds == 2)
Cloth:Tick(0.15)
assert(Adds == 3 and Removes == 2)
-- GE 应用失败并回滚成功，不刷新临时武器，也不移除旧武器的碰撞。
assert(not VisualManager:Equip(Failing))
assert(Adds == 3 and Removes == 2 and VisualOwner.HandheldWeapon == VisualWeapon)
VisualWeapon.Invalid = true
VisualWeapon:ReceiveEndPlay(0)
assert(Removes == 3 and next(Cloth.Tracked) == nil)
local Final = Weapon()
Final.BackClothPhysicsAsset = {}
assert(VisualManager:Equip(Final) and Adds == 4)
Cloth:Destroy()
Cloth:Destroy()
assert(Removes == 4 and VisualOwner.Events:UnsubscribeOwner(Cloth) == 0)
assert(VisualManager:Unequip("HandheldWeapon") and Removes == 4)
VisualManager:Destroy()
OtherManager:Destroy()
VisualOwner.Events:Destroy()
OtherOwner.Events:Destroy()
print("PASS: equipment/draw events drive cloth, actor isolation, visual refresh and subscriber cleanup")
