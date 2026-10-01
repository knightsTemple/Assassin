local AttackPhase = require("Combat.AttackPhase").AttackPhase

-- 收剑等待的默认值和下限（秒）。
local DefaultSwordSheatheDelay = 10.0

---@class LightAttack : AttackModule
---@field AttackSystem AttackSystem
---@field Phase AttackPhase
---@field ActiveWeapon? AssassinWeaponBase
---@field SwordActionPlayRate number
---@field SwordDrawReadyTime? number
---@field SwordSheatheDelay number
local LightAttack = {}
LightAttack.__index = LightAttack

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

---@return LightAttack?
function LightAttack.New(AttackSystem)
    local Owner = AttackSystem.Owner
    if not IsValid(Owner) then
        return nil
    end

    local ASC = AttackSystem.ASC
    if not IsValid(ASC) then
        return nil
    end

    local LightAttackAbilityClass = UE.UClass.Load("/Game/AssassinGirl/GAS/Abilities/GA_LightAttack.GA_LightAttack_C")
    if not LightAttackAbilityClass then
        return nil
    end

    return setmetatable({
        AttackSystem = AttackSystem,
        Owner = Owner,
        ASC = ASC,
        LightAttackAbilityClass = LightAttackAbilityClass,
        LightAttackAbilityHandle = nil,
        LightAttackMontages = {},
        LightAttackTimings = {},
        ActiveWeapon = nil,
        SwordDrawMontage = nil,
        SwordSheatheMontage = nil,
        SwordActionPlayRate = 1.0,
        SwordDrawReadyTime = nil,
        Phase = AttackPhase.Idle,
        ActiveAbility = nil,
        PendingLightAttack = false,
        CanAcceptNextAttack = false, -- 连击窗口或收招后的持剑等待期内，可立即开始下一刀
        -- 攻击收招结束后延迟收剑；期间可移动、续招或重新从第一刀开始。
        SwordSheatheDelay = DefaultSwordSheatheDelay,
        ComboIndex = 0,
        Destroyed = false,
    }, LightAttack)
end

-- 每轮攻击读取当前手持武器，禁止回退到全局剑动画。
function LightAttack:LoadWeaponAnimations()
    ---@type AssassinWeaponBase?
    local Weapon = IsValid(self.Owner) and self.Owner.HandheldWeapon or nil
    if not Weapon or not IsValid(Weapon) or Weapon.EquippedCharacter ~= self.Owner then
        return false
    end
    local Source = Weapon.LightAttackMontages
    if not Source or Source:Num() == 0 then
        print("LightAttack: equipped weapon has no light attack montages")
        return false
    end
    local Montages, Timings = {}, {}
    for Index = 1, Source:Num() do
        local Montage = Source:Get(Index)
        if not IsValid(Montage) then return false end
        Montages[Index] = Montage
        local Config = Weapon.LightAttackTimings and Weapon.LightAttackTimings[Index]
        -- 其他武器未提供精细时机时，按完整动画播放，最后一段不续接。
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
    return IsValid(self.Owner) and Weapon ~= nil and IsValid(Weapon)
        and self.Owner.HandheldWeapon == Weapon
        and Weapon.EquippedCharacter == self.Owner
end

function LightAttack:GrantAbility()
    if self.Destroyed or not IsValid(self.Owner) or not IsValid(self.ASC)
        or not self.LightAttackAbilityClass then
        return false
    end

    -- The PlayerState ASC may already own this ability after a pawn is replaced.
    if self.Owner:HasAbility(self.LightAttackAbilityClass) then
        return true
    end

    local Handle = self.ASC:K2_GiveAbility(self.LightAttackAbilityClass, 1)
    if not self.Owner:HasAbility(self.LightAttackAbilityClass) then
        print("LightAttack: failed to grant light attack")
        return false
    end

    self.LightAttackAbilityHandle = Handle
    return true
end

function LightAttack:HandleInput()
    if self.Destroyed or not IsValid(self.ASC) or not self.LightAttackAbilityClass then
        return false
    end

    if IsValid(self.ActiveAbility) then
        if not self:HasCurrentWeapon() then
            self.ActiveAbility:FinishLightAttack(true)
            return false
        end
        -- 收剑期间不重新激活同一个 GAS 技能，也不推进攻击段数。
        if self.Phase == AttackPhase.Sheathing then
            return false
        end
        if self.CanAcceptNextAttack and self.ComboIndex >= #self.LightAttackMontages then
            -- 最后一段结束后的等待期间可开始新一轮，不重复拔出武器。
            self.PendingLightAttack = false -- 输入缓存回答：玩家有没有提前按过下一刀？
            self.CanAcceptNextAttack = false -- 新一刀开始，重新等待允许衔接的时机
            self.ComboIndex = 1
            self.ActiveAbility:PlayCurrentAttack()
            return true
        end
        if self.ComboIndex >= #self.LightAttackMontages then
            return false
        end

        self.PendingLightAttack = true
        if self.Phase == AttackPhase.Attacking and self.CanAcceptNextAttack then
            self:ContinueLightAttack()
        end
        return true
    end

    local Activated = self.ASC:TryActivateAbilityByClass(self.LightAttackAbilityClass)
    return Activated
end

function LightAttack:BeginAttack(Ability)
    if self.Destroyed or not IsValid(Ability) or IsValid(self.ActiveAbility) then
        return false
    end

    if not self:LoadWeaponAnimations() then
        return false
    end

    if not self.AttackSystem:TryBeginAttack(self) then
        return false
    end

    self.ActiveAbility = Ability          -- 从拔剑到收剑结束都使用同一个技能实例
    self.Phase = AttackPhase.Drawing
    self.ComboIndex = 1                   -- 拔剑完成后自动播放第一段，无需再按一次
    self.PendingLightAttack = false       -- 拔剑期间的额外点击可缓存为第二段输入
    self.CanAcceptNextAttack = false     -- 连击窗口开启或收招结束后，才允许立即接下一刀
    return true
end

function LightAttack:OnSwordDrawReady(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Drawing then
        return
    end
    self.Phase = AttackPhase.Attacking
    Ability:PlayCurrentAttack()
end

function LightAttack:BeginSwordSheathe(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking then
        return
    end
    self.Phase = AttackPhase.Sheathing
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    Ability:PlaySwordSheathe()
end

function LightAttack:GetCurrentAttackMontage()
    if not self:HasCurrentWeapon() then return nil end
    return self.LightAttackMontages and self.LightAttackMontages[self.ComboIndex]
end

function LightAttack:GetCurrentAttackTiming()
    return self.LightAttackTimings and self.LightAttackTimings[self.ComboIndex]
end

function LightAttack:OnLightAttackComboWindow(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking
        or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    -- 动作主体完成后就允许续接，不再等待动画尾部的自然混出。
    self.CanAcceptNextAttack = true
    if self.PendingLightAttack then
        self:ContinueLightAttack()
    end
end

function LightAttack:OnLightAttackRecoveryReady(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking then
        return
    end

    if self.PendingLightAttack and self.ComboIndex < #self.LightAttackMontages then
        self:ContinueLightAttack()
    else
        Ability:StopCurrentAttack()
        self.CanAcceptNextAttack = true -- 最后一段也在收招结束后允许重新起手
        Ability:WaitForComboInput(self.SwordSheatheDelay)
    end
end

function LightAttack:ContinueLightAttack()
    if self.Destroyed or self.Phase ~= AttackPhase.Attacking or not IsValid(self.ActiveAbility)
        or not self.PendingLightAttack or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self.ComboIndex = self.ComboIndex + 1
    self.ActiveAbility:PlayCurrentAttack()
end

function LightAttack:OnAttackEnded(Ability)
    if self.ActiveAbility ~= Ability then
        return
    end

    self.ActiveAbility = nil
    self.Phase = AttackPhase.Idle
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self:ResetCombo()
    self.ActiveWeapon = nil
    self.LightAttackMontages = {}
    self.LightAttackTimings = {}
    self.SwordDrawMontage = nil
    self.SwordSheatheMontage = nil
    self.AttackSystem:EndAttack(self)
end

function LightAttack:ResetCombo()
    self.ComboIndex = 0
end

function LightAttack:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    if IsValid(self.ActiveAbility) then
        self.ActiveAbility:FinishLightAttack(true)
    end

    self.ActiveAbility = nil
    self.Phase = AttackPhase.Idle
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self.AttackSystem:EndAttack(self)
    self.AttackSystem = nil
    self.Owner = nil
    self.ASC = nil
    self.LightAttackAbilityClass = nil
    self.LightAttackAbilityHandle = nil
    self.ActiveWeapon = nil
    self.LightAttackTimings = nil
    self.LightAttackMontages = nil
    self.SwordDrawMontage = nil
    self.SwordSheatheMontage = nil
    self.ComboIndex = 0
end

return LightAttack
