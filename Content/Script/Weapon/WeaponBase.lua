---@class AssassinWeaponBase
local M = UnLua.Class()

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

local function NonNegative(Value)
    if type(Value) ~= "number" or Value ~= Value or Value == math.huge or Value == -math.huge then
        return 0.0
    end
    return math.max(0.0, Value)
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
    self._ChangingEquipment = false
    self._AttachedByEquipment = false
    if self:IsShieldWeapon() then
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
    local Stats = self.BaseStats
    local Values = {
        AttackPower = NonNegative(Stats.AttackPower),
        AssassinationPower = NonNegative(Stats.AssassinationPower),
        CritDamageBonus = NonNegative(Stats.CritDamageBonus),
        CritChance = math.min(1.0, NonNegative(Stats.CritChance)),
        Weight = NonNegative(Stats.Weight),
        MaxHealth = NonNegative(self:GetMaxHealthBonus()),
    }
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
        return true
    end
    if not ApplySpec(self:MakeBaseStatsSpec(ASC)) then
        return Rollback()
    end
    for _, EffectClass in ipairs(Effects) do
        if not ApplySpec(self:MakeEquipmentSpec(ASC, EffectClass)) then
            return Rollback()
        end
    end

    self._EquipmentASC = ASC
    self._EquipmentHandles = Handles
    self._AttachedByEquipment = Attached
    self.EquippedCharacter = Character
    self:SetOwner(Character)
    self._ChangingEquipment = false
    self:OnWeaponEquipped(Character)
    return true
end

function M:UnequipFromCharacter()
    if self._ChangingEquipment or not self:HasAuthority() then
        return false
    end
    self._ChangingEquipment = true
    local PreviousCharacter = self.EquippedCharacter
    local ASC = self._EquipmentASC
    local Handles = self._EquipmentHandles
    self._EquipmentASC = nil
    self._EquipmentHandles = {}
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

function M:ApplyShieldDamage(Damage)
    if not self:HasAuthority() or not self:IsShieldWeapon() then
        return 0.0
    end
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
