local AttackBase = require("Combat.attack.AttackBase")
local AttackPhase = require("Combat.attack.AttackPhase").AttackPhase
local EventDefine = require("Core.EventSubscribe.EventDefine")

local DefaultSwordSheatheDelay = 10.0

---@class LightAttack : AttackBase
---@field AttackSystem AttackSystem
---@field Events? EventBus
---@field Phase AttackPhase
---@field ActiveWeapon? AssassinWeaponBase
---@field SwordActionPlayRate number
---@field SwordDrawReadyTime? number
---@field SwordSheatheDelay number
local LightAttack = setmetatable({}, { __index = AttackBase })
LightAttack.__index = LightAttack

local IsValid = AttackBase.IsValid

---@return LightAttack?
function LightAttack.New(AttackSystem)
    local Self = AttackBase.New(AttackSystem, LightAttack)
    if not Self then
        return nil
    end

    Self.LightAttackMontages = {}
    Self.LightAttackTimings = {}
    Self.ActiveWeapon = nil
    Self.SwordDrawMontage = nil
    Self.SwordSheatheMontage = nil
    Self.SwordActionPlayRate = 1.0
    Self.SwordDrawReadyTime = nil
    Self.PendingLightAttack = false
    Self.CanAcceptNextAttack = false
    Self.SwordSheatheDelay = DefaultSwordSheatheDelay
    Self.ComboIndex = 0

    Self.Events = Self.Owner.Events
    if Self.Events then
        Self.Events:Subscribe(EventDefine.WeaponChanged, Self, Self.OnWeaponChanged)
    end
    return Self
end

---@param Payload WeaponChangedPayload
function LightAttack:OnWeaponChanged(Payload)
    if self.Destroyed or Payload.Character ~= self.Owner or Payload.Slot ~= "HandheldWeapon" then
        return
    end
    if self.ActiveWeapon and not self:HasCurrentWeapon() then
        self:CancelActiveAbility()
    end
end

function LightAttack:GetAbilityClass()
    return self.Owner.LightAttackAbilityClass
end

function LightAttack:LoadWeaponAnimations()
    local Weapon = self.Owner.HandheldWeapon
    if not Weapon or not IsValid(Weapon) or Weapon.EquippedCharacter ~= self.Owner then
        return false
    end

    local Source = Weapon.LightAttackMontages
    if not Source or Source:Num() == 0 then
        return false
    end

    local Montages, Timings = {}, {}
    for Index = 1, Source:Num() do
        local Montage = Source:Get(Index)
        if not IsValid(Montage) then
            return false
        end
        Montages[Index] = Montage
        local Config = Weapon.LightAttackTimings and Weapon.LightAttackTimings[Index]
        Timings[Index] = {
            PlayRate = Config and Config.PlayRate or 1.0,
            StartTime = Config and Config.StartTime or 0.0,
            ComboTime = Config and Config.ComboTime or nil,
            RecoveryTime = Config and Config.RecoveryTime or Montage:GetPlayLength(),
        }
    end

    self.ActiveWeapon = Weapon
    self.LightAttackMontages = Montages
    self.LightAttackTimings = Timings
    self.SwordDrawMontage = Weapon.DrawMontage
    self.SwordSheatheMontage = Weapon.SheatheMontage
    self.SwordActionPlayRate = math.max(0.1, Weapon.WeaponActionPlayRate or 1.0)
    self.SwordDrawReadyTime = Weapon.WeaponDrawReadyTime
    self.SwordSheatheDelay = math.max(DefaultSwordSheatheDelay, Weapon.WeaponSheatheDelay or DefaultSwordSheatheDelay)
    return true
end

function LightAttack:HasCurrentWeapon()
    local Weapon = self.ActiveWeapon
    return Weapon ~= nil and self.Owner.HandheldWeapon == Weapon and Weapon.EquippedCharacter == self.Owner
end

function LightAttack:HandleInput()
    if not IsValid(self.ActiveAbility) then
        return AttackBase.HandleInput(self)
    end

    if not self:HasCurrentWeapon() then
        self.ActiveAbility:FinishLightAttack(true)
        return false
    end

    if self.Phase == AttackPhase.Sheathing then
        return false
    end

    local MaxCombo = #self.LightAttackMontages
    -- 连招打完后在输入等待窗口内再次输入：重置并从第 1 段重新起手
    if self.CanAcceptNextAttack and self.ComboIndex >= MaxCombo then
        self.PendingLightAttack = false
        self.CanAcceptNextAttack = false
        self.ComboIndex = 1
        self.ActiveAbility:PlayCurrentAttack()
        return true
    end

    if self.ComboIndex >= MaxCombo then
        return false
    end

    self.PendingLightAttack = true
    if self.Phase == AttackPhase.Attacking and self.CanAcceptNextAttack then
        self:ContinueLightAttack()
    end
    return true
end

function LightAttack:BeginAttack(Ability)
    if self.ActiveAbility or not self:LoadWeaponAnimations() then
        return false
    end

    if not AttackBase.BeginAttack(self, Ability) then
        self.ActiveWeapon = nil
        self.LightAttackMontages = {}
        self.LightAttackTimings = {}
        return false
    end

    self.Phase = AttackPhase.Drawing
    self.ComboIndex = 1
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    return true
end

function LightAttack:OnSwordDrawReady(Ability)
    if self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Drawing then
        return
    end
    self.Phase = AttackPhase.Attacking
    Ability:PlayCurrentAttack()
end

function LightAttack:BeginSwordSheathe(Ability)
    if self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking then
        return
    end
    self.Phase = AttackPhase.Sheathing
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    Ability:PlaySwordSheathe()
end

function LightAttack:GetCurrentAttackMontage()
    if not self:HasCurrentWeapon() then
        return nil
    end
    return self.LightAttackMontages and self.LightAttackMontages[self.ComboIndex]
end

function LightAttack:GetCurrentAttackTiming()
    return self.LightAttackTimings and self.LightAttackTimings[self.ComboIndex]
end

function LightAttack:OnLightAttackComboWindow(Ability)
    if self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking
        or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    self.CanAcceptNextAttack = true
    if self.PendingLightAttack then
        self:ContinueLightAttack()
    end
end

function LightAttack:OnLightAttackRecoveryReady(Ability)
    if self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking then
        return
    end

    if self.PendingLightAttack and self.ComboIndex < #self.LightAttackMontages then
        self:ContinueLightAttack()
    else
        Ability:StopCurrentAttack()
        self.CanAcceptNextAttack = true
        Ability:WaitForComboInput(self.SwordSheatheDelay)
    end
end

function LightAttack:ContinueLightAttack()
    if self.Phase ~= AttackPhase.Attacking or not self.PendingLightAttack
        or self.ComboIndex >= #self.LightAttackMontages or not IsValid(self.ActiveAbility) then
        return
    end

    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self.ComboIndex = self.ComboIndex + 1
    self.ActiveAbility:PlayCurrentAttack()
end

function LightAttack:OnAttackEnded(Ability)
    if not AttackBase.OnAttackEnded(self, Ability) then
        return false
    end

    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self.ComboIndex = 0
    self.ActiveWeapon = nil
    self.LightAttackMontages = {}
    self.LightAttackTimings = {}
    self.SwordDrawMontage = nil
    self.SwordSheatheMontage = nil
    return true
end

function LightAttack:ResetCombo()
    self.ComboIndex = 0
end

function LightAttack:CancelActiveAbility()
    if IsValid(self.ActiveAbility) then
        self.ActiveAbility:FinishLightAttack(true)
    end
end

function LightAttack:Destroy()
    if self.Destroyed then
        return
    end
    if self.Events then
        self.Events:UnsubscribeOwner(self)
        self.Events = nil
    end
    AttackBase.Destroy(self)
    self.ActiveWeapon = nil
    self.LightAttackMontages = nil
    self.LightAttackTimings = nil
end

return LightAttack
