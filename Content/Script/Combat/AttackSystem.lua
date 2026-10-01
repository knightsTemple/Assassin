---@class AttackSystem
---@field SwordActionPlayRate number
---@field SwordDrawReadyTime number
---@field SwordSheatheDelay number
local AttackSystem = {}
AttackSystem.__index = AttackSystem

local MontagePaths = {
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_1_DownSlash_RM.AM_LightAttack_1_DownSlash_RM",
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_2_UpSlash_RM.AM_LightAttack_2_UpSlash_RM",
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_3_PushKick_RM.AM_LightAttack_3_PushKick_RM",
    "/Game/AssassinGirl/Animation/Combat/Attack/Montages/AM_LightAttack_4_UppercutSlash_RM.AM_LightAttack_4_UppercutSlash_RM",
}

local SwordDrawMontagePath = "/Game/AssassinGirl/Animation/Sword/Montages/AM_Sword_Unsheathe_to_Chudan.AM_Sword_Unsheathe_to_Chudan"
local SwordSheatheMontagePath = "/Game/AssassinGirl/Animation/Sword/Montages/AM_Sword_Sheathe_to_Standing.AM_Sword_Sheathe_to_Standing"

-- 时间点使用动画原始时间（秒）；实际等待时长会除以播放速度。
-- ComboTime：有缓存输入时接下一段；RecoveryTime：没有输入时结束收招。
-- 第四段保留腾空、落地和短暂缓冲，避免在空中切回站姿。
local LightAttackTimings = {
    { PlayRate = 1.20, StartTime = 0.06, ComboTime = 0.72, RecoveryTime = 0.95 }, -- 下劈
    { PlayRate = 1.20, StartTime = 0.14, ComboTime = 0.80, RecoveryTime = 1.00 }, -- 上撩
    { PlayRate = 1.20, StartTime = 0.06, ComboTime = 0.85, RecoveryTime = 1.05 }, -- 踢击
    { PlayRate = 1.20, StartTime = 0.08, RecoveryTime = 1.45 },                -- 升龙斩
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

    local DrawMontage = UE.UObject.Load(SwordDrawMontagePath)
    local SheatheMontage = UE.UObject.Load(SwordSheatheMontagePath)
    if not IsValid(DrawMontage) or not IsValid(SheatheMontage) then
        print("AttackSystem: sword draw/sheath montage missing")
        return nil
    end

    return setmetatable({
        Owner = Owner,
        ASC = ASC,
        LightAttackAbilityClass = LightAttackAbilityClass,
        LightAttackAbilityHandle = nil,
        LightAttackMontages = Montages,
        SwordDrawMontage = DrawMontage,
        SwordSheatheMontage = SheatheMontage,
        SwordActionPlayRate = 1.0,
        -- 原拔剑动画约 1.25 秒已完成主体，后面的站姿整理不再等待。
        SwordDrawReadyTime = 1.25,
        Phase = "Idle",
        ActiveAbility = nil,
        PendingLightAttack = false,
        WaitingForNextInput = false,
        ComboWindowOpen = false,
        -- 攻击收招结束后延迟收剑；期间可移动、续招或重新从第一刀开始。
        SwordSheatheDelay = 2.0,
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
        -- 收剑期间不重新激活同一个 GAS 技能，也不推进攻击段数。
        if self.Phase == "Sheathing" then
            return false
        end
        if self.WaitingForNextInput and self.ComboIndex >= #self.LightAttackMontages then
            -- 第四刀结束后的持剑等待期间可以直接开始新一轮，不重复拔剑。
            self.PendingLightAttack = false
            self.WaitingForNextInput = false
            self.ComboWindowOpen = false
            self.ComboIndex = 1
            self.ActiveAbility:PlayCurrentAttack()
            return true
        end
        if self.ComboIndex >= #self.LightAttackMontages then
            return false
        end

        self.PendingLightAttack = true
        if self.Phase == "Attacking" and (self.ComboWindowOpen or self.WaitingForNextInput) then
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

    self.ActiveAbility = Ability          -- 从拔剑到收剑结束都使用同一个技能实例
    self.Phase = "Drawing"
    self.ComboIndex = 1                   -- 拔剑完成后自动播放第一段，无需再按一次
    self.PendingLightAttack = false       -- 拔剑期间的额外点击可缓存为第二段输入
    self.WaitingForNextInput = false      -- 收招后等待 SwordSheatheDelay 秒再收剑
    self.ComboWindowOpen = false          -- 由动作主体结束时间开启连击窗口
    return true
end

function AttackSystem:OnSwordDrawReady(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= "Drawing" then
        return
    end
    self.Phase = "Attacking"
    Ability:PlayCurrentAttack()
end

function AttackSystem:BeginSwordSheathe(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= "Attacking" then
        return
    end
    self.Phase = "Sheathing"
    self.PendingLightAttack = false
    self.WaitingForNextInput = false
    self.ComboWindowOpen = false
    Ability:PlaySwordSheathe()
end

function AttackSystem:GetCurrentAttackMontage()
    return self.LightAttackMontages and self.LightAttackMontages[self.ComboIndex]
end

function AttackSystem:GetCurrentAttackTiming()
    return LightAttackTimings[self.ComboIndex]
end

function AttackSystem:OnLightAttackComboWindow(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= "Attacking"
        or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    -- 动作主体完成后就允许续接，不再等待动画尾部的自然混出。
    self.ComboWindowOpen = true
    if self.PendingLightAttack then
        self:ContinueLightAttack()
    end
end

function AttackSystem:OnLightAttackRecoveryReady(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= "Attacking" then
        return
    end

    if self.PendingLightAttack and self.ComboIndex < #self.LightAttackMontages then
        self:ContinueLightAttack()
    else
        Ability:StopCurrentAttack()
        self.WaitingForNextInput = true
        self.ComboWindowOpen = false
        Ability:WaitForComboInput(self.SwordSheatheDelay)
    end
end

function AttackSystem:ContinueLightAttack()
    if self.Destroyed or self.Phase ~= "Attacking" or not IsValid(self.ActiveAbility)
        or not self.PendingLightAttack or self.ComboIndex >= #self.LightAttackMontages then
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
    self.Phase = "Idle"
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
    self.Phase = "Idle"
    self.PendingLightAttack = false
    self.WaitingForNextInput = false
    self.ComboWindowOpen = false
    self.Owner = nil
    self.ASC = nil
    self.LightAttackAbilityClass = nil
    self.LightAttackAbilityHandle = nil
    self.LightAttackMontages = nil
    self.SwordDrawMontage = nil
    self.SwordSheatheMontage = nil
    self.ComboIndex = 0
end

return AttackSystem
