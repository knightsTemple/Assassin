local AttackPhase = require("Combat.attack.AttackPhase").AttackPhase

---@class AttackBase : AttackModule
---@field AttackSystem AttackSystem
---@field Owner any
---@field ASC any
---@field AbilityClass any
---@field AbilityHandle any
---@field ActiveAbility any
---@field Phase AttackPhase
---@field Destroyed boolean
local AttackBase = {}
AttackBase.__index = AttackBase

function AttackBase.IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

function AttackBase.New(AttackSystem, Class)
    if not AttackSystem or not AttackBase.IsValid(AttackSystem.Owner) or not AttackBase.IsValid(AttackSystem.ASC) then
        return nil
    end

    local Self = setmetatable({
        AttackSystem = AttackSystem,
        Owner = AttackSystem.Owner,
        ASC = AttackSystem.ASC,
        Phase = AttackPhase.Idle,
        Destroyed = false,
    }, Class or AttackBase)

    Self.AbilityClass = Self:GetAbilityClass()
    if not AttackBase.IsValid(Self.AbilityClass) then
        return nil
    end
    return Self
end

function AttackBase:GetAbilityClass()
    return nil
end

function AttackBase:GrantAbility()
    if not self.AbilityClass or not AttackBase.IsValid(self.ASC) then
        return false
    end
    if self.Owner:HasAbility(self.AbilityClass) then
        return true
    end
    local Handle = self.ASC:K2_GiveAbility(self.AbilityClass, 1)
    if not self.Owner:HasAbility(self.AbilityClass) then
        return false
    end
    self.AbilityHandle = Handle
    return true
end

function AttackBase:HandleInput()
    if not AttackBase.IsValid(self.ASC) or not self.AbilityClass then
        return false
    end
    return self.ASC:TryActivateAbilityByClass(self.AbilityClass)
end

function AttackBase:BeginAttack(Ability)
    if not AttackBase.IsValid(Ability) or self.ActiveAbility or not self.AttackSystem:TryBeginAttack(self) then
        return false
    end
    self.ActiveAbility = Ability
    return true
end

function AttackBase:OnAttackEnded(Ability)
    if self.ActiveAbility ~= Ability then
        return false
    end

    if self.Owner then
        if self.Owner.AttackTraceComponent then self.Owner.AttackTraceComponent:ClearWindow() end
        if self.Owner.AttackHitReceiver then self.Owner.AttackHitReceiver:Clear() end
    end

    self.ActiveAbility = nil
    self.Phase = AttackPhase.Idle
    if self.AttackSystem then
        self.AttackSystem:EndAttack(self)
    end
    return true
end

function AttackBase:CancelActiveAbility()
    if AttackBase.IsValid(self.ActiveAbility) then
        self.ActiveAbility:K2_CancelAbility()
    end
end

function AttackBase:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true

    self:CancelActiveAbility()
    self.ActiveAbility = nil
    self.Phase = AttackPhase.Idle

    if self.AttackSystem then
        self.AttackSystem:EndAttack(self)
        self.AttackSystem = nil
    end
    self.Owner = nil
    self.ASC = nil
    self.AbilityClass = nil
    self.AbilityHandle = nil
end

return AttackBase
