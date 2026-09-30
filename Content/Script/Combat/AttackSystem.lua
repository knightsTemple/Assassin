---@class AttackSystem
---@field ComboInputGrace number
local AttackSystem = {}
AttackSystem.__index = AttackSystem

local MontagePaths = {
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_1_DownSlash_RM.AM_LightAttack_1_DownSlash_RM",
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_2_UpSlash_RM.AM_LightAttack_2_UpSlash_RM",
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_3_PushKick_RM.AM_LightAttack_3_PushKick_RM",
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_4_UppercutSlash_RM.AM_LightAttack_4_UppercutSlash_RM",
}

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

---@return AttackSystem?
function AttackSystem.New(Owner)
    if not IsValid(Owner) then
        return nil
    end

    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(Owner)
    if not IsValid(ASC) then
        return nil
    end

    local LightAttackAbilityClass = UE.UClass.Load("/Game/AssassinGirl/GAS/Abilities/GA_LightAttack.GA_LightAttack_C")
    if not LightAttackAbilityClass then
        return nil
    end

    local Montages = {}
    for Index, Path in ipairs(MontagePaths) do
        Montages[Index] = UE.UObject.Load(Path)
        if not IsValid(Montages[Index]) then
            print("AttackSystem: montage missing", Path)
            return nil
        end
    end

    return setmetatable({
        Owner = Owner,
        ASC = ASC,
        LightAttackAbilityClass = LightAttackAbilityClass,
        LightAttackAbilityHandle = nil,
        LightAttackMontages = Montages,
        ActiveAbility = nil,
        PendingLightAttack = false,
        WaitingForNextInput = false,
        ComboWindowOpen = false,
        -- Buffer one press; chain during blend-out, or allow 0.6 seconds after completion.
        ComboInputGrace = 0.6,
        ComboIndex = 0,
        Destroyed = false,
    }, AttackSystem)
end

function AttackSystem:GrantLightAttack()
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
        print("AttackSystem: failed to grant light attack")
        return false
    end

    self.LightAttackAbilityHandle = Handle
    return true
end

function AttackSystem:LightAttack()
    if self.Destroyed or not IsValid(self.ASC) or not self.LightAttackAbilityClass then
        return false
    end

    if IsValid(self.ActiveAbility) then
        if self.ComboIndex >= #self.LightAttackMontages then
            return false
        end

        self.PendingLightAttack = true
        if self.ComboWindowOpen or self.WaitingForNextInput then
            self:ContinueLightAttack()
        end
        return true
    end

    local Activated = self.ASC:TryActivateAbilityByClass(self.LightAttackAbilityClass)
    return Activated
end

function AttackSystem:BeginLightAttack(Ability)
    if self.Destroyed or not IsValid(Ability) or IsValid(self.ActiveAbility) then
        return false
    end

    self.ActiveAbility = Ability          -- 保存当前正在执行的轻攻击技能实例
    self.ComboIndex = 1                   -- 从轻攻击连招的第一段开始
    self.PendingLightAttack = false       -- 当前没有等待执行的下一段轻攻击输入
    self.WaitingForNextInput = false      -- 当前尚未进入等待下一次连招输入的阶段
    self.ComboWindowOpen = false
    return true
end

function AttackSystem:GetCurrentAttackMontage()
    return self.LightAttackMontages and self.LightAttackMontages[self.ComboIndex]
end

function AttackSystem:OnLightAttackBlendOut(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability
        or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    -- Start the next montage while this one still has weight, avoiding an idle gap.
    self.ComboWindowOpen = true
    if self.PendingLightAttack then
        self:ContinueLightAttack()
    end
end

function AttackSystem:OnLightAttackMontageCompleted(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability then
        return
    end

    if self.ComboIndex >= #self.LightAttackMontages then
        Ability:FinishLightAttack(false)
    elseif self.PendingLightAttack then
        self:ContinueLightAttack()
    else
        self.WaitingForNextInput = true
        Ability:WaitForComboInput(self.ComboInputGrace)
    end
end

function AttackSystem:ContinueLightAttack()
    if self.Destroyed or not IsValid(self.ActiveAbility) or not self.PendingLightAttack then
        return
    end

    self.PendingLightAttack = false
    self.WaitingForNextInput = false
    self.ComboWindowOpen = false
    self.ComboIndex = self.ComboIndex + 1
    self.ActiveAbility:PlayCurrentAttack()
end

function AttackSystem:OnLightAttackEnded(Ability)
    if self.ActiveAbility ~= Ability then
        return
    end

    self.ActiveAbility = nil
    self.PendingLightAttack = false
    self.WaitingForNextInput = false
    self.ComboWindowOpen = false
    self:ResetCombo()
end

function AttackSystem:HeavyAttack()
    -- TODO: Activate Assassin.Ability.Attack.Heavy through ASC when the ability exists.
end

function AttackSystem:ResetCombo()
    self.ComboIndex = 0
end

function AttackSystem:Destroy()
    self.Destroyed = true
    if IsValid(self.ActiveAbility) then
        self.ActiveAbility:FinishLightAttack(true)
    end

    self.ActiveAbility = nil
    self.PendingLightAttack = false
    self.WaitingForNextInput = false
    self.ComboWindowOpen = false
    self.Owner = nil
    self.ASC = nil
    self.LightAttackAbilityClass = nil
    self.LightAttackAbilityHandle = nil
    self.LightAttackMontages = nil
    self.ComboIndex = 0
end

return AttackSystem
