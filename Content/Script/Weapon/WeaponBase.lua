-- 与 C++ 反射接口对应，供 Lua Language Server 识别 UE 注入的成员。
---@class AssassinWeaponStats
---@field AttackPower number
---@field AssassinationPower number
---@field CritDamageBonus number
---@field CritChance number
---@field Weight number

---@class AssassinEquipmentEffectArray
---@field Num fun(self: AssassinEquipmentEffectArray): integer
---@field Get fun(self: AssassinEquipmentEffectArray, Index: integer): any

---@class AssassinShieldWeaponBase : AssassinWeaponBase
---@field MaxShieldHealth number
---@field ShieldHealth number
---@field OnShieldHealthChanged fun(self: AssassinShieldWeaponBase, OldHealth: number, NewHealth: number)

---@class AssassinWeaponBase
---@field IsA fun(self: AssassinWeaponBase, Class: any): boolean
---@field BaseStats AssassinWeaponStats
---@field WeaponLevel integer
---@field StatGrowthCurves table<string, any>
---@field EffectLevel number
---@field EquipmentStatsEffectClass any
---@field AdditionalEffects AssassinEquipmentEffectArray
---@field EquipSocketName any 角色 SkeletalMesh 上的装备插槽名
---@field LightAttackMontages any 轻攻击蒙太奇数组，按连招顺序排列
---@field HeavyAttackMontages any 重攻击蒙太奇数组，暂未使用
---@field LightAttackTimings? table 每段轻攻击的可选时机配置
---@field DrawnSocketName any
---@field WeaponDrawAttachTime? number
---@field WeaponSheatheAttachTime? number
---@field DrawMontage any
---@field SheatheMontage any
---@field WeaponActionPlayRate? number
---@field WeaponDrawReadyTime? number
---@field WeaponSheatheDelay? number
---@field EquippedCharacter any
---@field Overridden { ReceiveEndPlay: fun(self: AssassinWeaponBase, EndPlayReason: any) }
---@field IsShieldWeapon fun(self: AssassinWeaponBase): boolean
---@field GetMaxHealthBonus fun(self: AssassinWeaponBase): number
---@field HasAuthority fun(self: AssassinWeaponBase): boolean
---@field GetName fun(self: AssassinWeaponBase): string
---@field K2_DetachFromActor fun(self: AssassinWeaponBase, LocationRule: any, RotationRule: any, ScaleRule: any)
---@field K2_AttachToComponent fun(self: AssassinWeaponBase, Parent: any, SocketName: any, LocationRule: any, RotationRule: any, ScaleRule: any, WeldSimulatedBodies: boolean): boolean
---@field SetOwner fun(self: AssassinWeaponBase, NewOwner: any)
---@field OnWeaponEquipped fun(self: AssassinWeaponBase, Character: any)
---@field OnWeaponUnequipped fun(self: AssassinWeaponBase, PreviousCharacter: any)
local M = UnLua.Class()
local BackClothCollision = require("Weapon.BackClothCollision")

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

local function NonNegative(Value)
    if type(Value) ~= "number" or Value ~= Value or Value == math.huge or Value == -math.huge then
        return 0.0
    end
    return math.max(0.0, Value)
end


local StatNames = { "AttackPower", "AssassinationPower", "CritDamageBonus", "CritChance", "Weight" }

local function NormalizeLevel(Level)
    return math.max(1, math.min(100, math.floor(NonNegative(Level))))
end

function M:GetStatsAtLevel(Level)
    local Stats = UE.FAssassinWeaponStats()
    Level = NormalizeLevel(Level)
    for _, Name in ipairs(StatNames) do
        local Curve = self.StatGrowthCurves[Name]
        local Value = IsValid(Curve) and Curve:GetFloatValue(Level) or self.BaseStats[Name]
        Stats[Name] = NonNegative(Value)
    end
    Stats.CritChance = math.min(1.0, Stats.CritChance)
    return Stats
end

function M:GetCurrentStats()
    return self:GetStatsAtLevel(self.WeaponLevel)
end

function M:MakeBaseStatsValues()
    local Stats = self:GetCurrentStats()
    local Values = {}
    for _, Name in ipairs(StatNames) do
        Values[Name] = Stats[Name]
    end
    Values.MaxHealth = NonNegative(self:GetMaxHealthBonus())
    return Values
end

function M:RefreshEquipmentStats()
    if self._ChangingEquipment or not self:HasAuthority() then
        return false
    end
    if not IsValid(self.EquippedCharacter) then
        return true
    end
    local ASC = self._EquipmentASC
    local Handle = self._BaseStatsEffectHandle
    if not IsValid(ASC) or not Handle
        or UE.UAbilitySystemBlueprintLibrary.GetActiveGameplayEffectStackCount(Handle) == 0 then
        return false
    end

    -- Update the existing GE in place: no duplicate bonuses or reset of additional effects.
    local Values = UE.TMap(UE.FGameplayTag, UE.float)
    for Name, Value in pairs(self:MakeBaseStatsValues()) do
        Values:Add(UE.UAssassinWeaponGASLibrary.GetEquipmentDataTag("Assassin.Data.Equipment." .. Name), Value)
    end
    self._ChangingEquipment = true
    ASC:UpdateActiveGameplayEffectSetByCallerMagnitudes(Handle, Values)
    self._ChangingEquipment = false
    return true
end

function M:SetWeaponLevel(NewLevel)
    if self._ChangingEquipment or not self:HasAuthority() then
        return false
    end
    local OldLevel = self.WeaponLevel
    self.WeaponLevel = NormalizeLevel(NewLevel)
    if not self:RefreshEquipmentStats() then
        self.WeaponLevel = OldLevel
        return false
    end
    return true
end

local function SupportsEquipmentEffect(EffectClass, MustBeInfinite)
    if not IsValid(EffectClass) then
        return false
    end
    local Defaults = EffectClass:GetDefaultObject()
    if not IsValid(Defaults) or Defaults.StackingType ~= UE.EGameplayEffectStackingType.None then
        return false
    end
    local Policy = Defaults.DurationPolicy
    if MustBeInfinite then
        return Policy == UE.EGameplayEffectDurationType.Infinite
    end
    -- Instant effects have no removable active handle and cannot represent equipment buffs.
    return Policy == UE.EGameplayEffectDurationType.Infinite
        or Policy == UE.EGameplayEffectDurationType.HasDuration
end

local function RemoveEffects(ASC, Handles)
    if IsValid(ASC) then
        for _, Handle in ipairs(Handles or {}) do
            ASC:RemoveActiveGameplayEffect(Handle, -1)
        end
    end
end

function M:ReceiveBeginPlay()
    self._EquipmentASC = nil
    self._EquipmentHandles = {}
    self._BaseStatsEffectHandle = nil
    self.WeaponLevel = NormalizeLevel(self.WeaponLevel)
    self._ChangingEquipment = false
    self._AttachedByEquipment = false
    if self:IsShieldWeapon() then
        ---@cast self AssassinShieldWeaponBase
        self.ShieldHealth = NonNegative(self.MaxShieldHealth)
    end
end

function M:MakeEquipmentSpec(ASC, EffectClass)
    local Library = UE.UAssassinWeaponGASLibrary
    local Context = Library.MakeWeaponEffectContext(ASC, self)
    local Spec = ASC:MakeOutgoingSpec(EffectClass, math.max(1.0, NonNegative(self.EffectLevel)), Context)
    if not Library.IsSpecValid(Spec) then
        return nil
    end
    return Spec
end

function M:MakeBaseStatsSpec(ASC)
    local Spec = self:MakeEquipmentSpec(ASC, self.EquipmentStatsEffectClass)
    if not Spec then
        return nil
    end
    local Values = self:MakeBaseStatsValues()
    for Name, Value in pairs(Values) do
        local Tag = UE.UAssassinWeaponGASLibrary.GetEquipmentDataTag("Assassin.Data.Equipment." .. Name)
        Spec = UE.UAbilitySystemBlueprintLibrary.AssignTagSetByCallerMagnitude(Spec, Tag, Value)
    end
    return Spec
end

function M:EquipToCharacter(Character)
    if self._ChangingEquipment or not self:HasAuthority() or not IsValid(Character)
        or not Character:HasAuthority() then
        return false
    end
    if IsValid(self.EquippedCharacter) then
        -- Repeated calls must not apply another set of effects. Transfer requires unequipping first.
        return self.EquippedCharacter == Character and IsValid(self._EquipmentASC)
    end
    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(Character)
    if not IsValid(ASC) or not SupportsEquipmentEffect(self.EquipmentStatsEffectClass, true) then
        print("Weapon: missing ASC or invalid equipment stats GE", self:GetName())
        return false
    end

    local Effects = {}
    for Index = 1, self.AdditionalEffects:Num() do
        local EffectClass = self.AdditionalEffects:Get(Index)
        if IsValid(EffectClass) then
            if not SupportsEquipmentEffect(EffectClass, false) then
                print("Weapon: additional GE must be persistent and use no stacking", self:GetName(), Index)
                return false
            end
            table.insert(Effects, EffectClass)
        end
    end

    local Socket = tostring(self.EquipSocketName)
    local AttachMesh = Socket ~= "" and Socket ~= "None"
    if AttachMesh and (not IsValid(Character.Mesh) or not Character.Mesh:DoesSocketExist(self.EquipSocketName)) then
        print("Weapon: equip socket does not exist", Socket)
        return false
    end

    self._ChangingEquipment = true
    local Handles = {}
    local Attached = false
    local function Rollback()
        RemoveEffects(ASC, Handles)
        if Attached then
            self:K2_DetachFromActor(UE.EDetachmentRule.KeepWorld, UE.EDetachmentRule.KeepWorld, UE.EDetachmentRule.KeepWorld)
        end
        self._ChangingEquipment = false
        return false
    end

    if AttachMesh then
        Attached = self:K2_AttachToComponent(Character.Mesh, self.EquipSocketName,
            UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.KeepRelative, false)
        if not Attached then
            return Rollback()
        end
    end

    local function ApplySpec(Spec)
        if not Spec then
            return false
        end
        local Handle = ASC:BP_ApplyGameplayEffectSpecToSelf(Spec)
        if not UE.UAssassinWeaponGASLibrary.IsEffectHandleValid(Handle) then
            return false
        end
        table.insert(Handles, Handle)
        return Handle
    end
    local BaseStatsHandle = ApplySpec(self:MakeBaseStatsSpec(ASC))
    if not BaseStatsHandle then
        return Rollback()
    end
    for _, EffectClass in ipairs(Effects) do
        if not ApplySpec(self:MakeEquipmentSpec(ASC, EffectClass)) then
            return Rollback()
        end
    end

    self._EquipmentASC = ASC
    self._EquipmentHandles = Handles
    self._BaseStatsEffectHandle = BaseStatsHandle
    self._AttachedByEquipment = Attached
    self.EquippedCharacter = Character
    self:SetOwner(Character)
    self._ChangingEquipment = false
    self._WeaponDrawn = false
    BackClothCollision.Update(self)
    self:OnWeaponEquipped(Character)
    return true
end

function M:UnequipFromCharacter()
    if self._ChangingEquipment or not self:HasAuthority() then
        return false
    end
    self._ChangingEquipment = true
    BackClothCollision.Clear(self)
    local PreviousCharacter = self.EquippedCharacter
    local ASC = self._EquipmentASC
    local Handles = self._EquipmentHandles
    self._EquipmentASC = nil
    self._EquipmentHandles = {}
    self._BaseStatsEffectHandle = nil
    RemoveEffects(ASC, Handles)
    if self._AttachedByEquipment then
        self:K2_DetachFromActor(UE.EDetachmentRule.KeepWorld, UE.EDetachmentRule.KeepWorld, UE.EDetachmentRule.KeepWorld)
    end
    self._AttachedByEquipment = false
    self.EquippedCharacter = nil
    self:SetOwner(nil)
    self._ChangingEquipment = false
    if IsValid(PreviousCharacter) then
        self:OnWeaponUnequipped(PreviousCharacter)
    end
    return true
end

-- 切换视觉挂接，不重复应用或移除装备 GE。
function M:SetWeaponDrawn(Drawn)
    local HandSocket = self.DrawnSocketName
    if HandSocket == nil or tostring(HandSocket) == "" or tostring(HandSocket) == "None" then
        return true -- 未配置双插槽的武器保持原有行为。
    end
    local Character = self.EquippedCharacter
    if not self:HasAuthority() or not IsValid(Character) or not IsValid(Character.Mesh) then
        return false
    end
    local Socket = Drawn and HandSocket or self.EquipSocketName
    if Socket == nil or tostring(Socket) == "" or tostring(Socket) == "None"
        or not Character.Mesh:DoesSocketExist(Socket) then
        return false
    end
    if not self:K2_AttachToComponent(Character.Mesh, Socket,
        UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.SnapToTarget,
        UE.EAttachmentRule.KeepRelative, false) then
        return false
    end
    self._AttachedByEquipment = true
    self._WeaponDrawn = Drawn
    BackClothCollision.Update(self)
    return true
end

function M:ApplyShieldDamage(Damage)
    if not self:HasAuthority() or not self:IsShieldWeapon() then
        return 0.0
    end
    ---@cast self AssassinShieldWeaponBase
    local OldHealth = math.min(NonNegative(self.MaxShieldHealth), NonNegative(self.ShieldHealth))
    local NewHealth = math.max(0.0, OldHealth - NonNegative(Damage))
    self.ShieldHealth = NewHealth
    if OldHealth ~= NewHealth then
        self:OnShieldHealthChanged(OldHealth, NewHealth)
    end
    return OldHealth - NewHealth
end

function M:RepairShield(Amount)
    if not self:HasAuthority() or not self:IsShieldWeapon() then
        return 0.0
    end
    ---@cast self AssassinShieldWeaponBase
    local Maximum = NonNegative(self.MaxShieldHealth)
    local OldHealth = math.min(Maximum, NonNegative(self.ShieldHealth))
    local NewHealth = math.min(Maximum, OldHealth + NonNegative(Amount))
    self.ShieldHealth = NewHealth
    if OldHealth ~= NewHealth then
        self:OnShieldHealthChanged(OldHealth, NewHealth)
    end
    return NewHealth - OldHealth
end

function M:ReceiveEndPlay(EndPlayReason)
    -- The owner's ASC is on PlayerState and can survive the pawn or this weapon.
    self:UnequipFromCharacter()
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
end

return M
