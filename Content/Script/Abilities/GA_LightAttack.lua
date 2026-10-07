local WeaponBase = require("Weapon.WeaponBase")
local AttackEnums = require("Combat.attack.AttackPhase")
local AttackPhase = AttackEnums.AttackPhase
local AttackType = AttackEnums.AttackType

-- 显式描述 UnLua 委托接口，避免从测试替身推断生产代码的参数数量。
---@class AttackDelayDelegate
---@field Add fun(self: AttackDelayDelegate, Object: any, Callback: function)
---@field Remove fun(self: AttackDelayDelegate, Object: any, Callback: function)

---@class AttackDelayTask
---@field OnFinish AttackDelayDelegate
---@field ReadyForActivation fun(self: AttackDelayTask)
---@field EndTask fun(self: AttackDelayTask)

---@class GA_LightAttack_C
---@field LightAttack? LightAttack
---@field Ending boolean
---@field MontageTask? any
---@field MontagePhase? AttackPhase
---@field SwordDrawTask? AttackDelayTask
---@field WeaponAttachTask? AttackDelayTask
---@field ComboWaitTask? AttackDelayTask
---@field ComboWindowTask? AttackDelayTask
---@field AttackRecoveryTask? AttackDelayTask
---@field MoveInputController? any
---@field GetAvatarActorFromActorInfo fun(self: GA_LightAttack_C): any
---@field K2_CommitAbility fun(self: GA_LightAttack_C): boolean
---@field K2_CancelAbility fun(self: GA_LightAttack_C)
---@field K2_EndAbility fun(self: GA_LightAttack_C)
---@field MontageStop fun(self: GA_LightAttack_C, OverrideBlendOutTime: number)
local M = UnLua.Class()

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

function M:K2_ActivateAbility()
    self.Ending = false -- 技能是否已进入结束流程，防止重复结束或继续执行攻击流程
    self.MontageTask = nil -- 当前播放蒙太奇的技能任务
    self.MontagePhase = nil -- 当前蒙太奇阶段：拔剑、攻击或收剑
    self.WeaponAttachTask = nil
    self.PendingWeaponDrawn = nil
    self.SwordDrawTask = nil -- 拔剑达到可出招时刻的延时任务
    self.ComboWaitTask = nil -- 等待下一次连击输入的超时任务
    self.ComboWindowTask = nil -- 等待连击输入窗口开启的延时任务
    self.AttackRecoveryTask = nil -- 等待当前攻击恢复完成的延时任务
    self.MoveInputController = nil -- 被本技能锁定移动输入的控制器，用于结束时解锁

    -- ASC Owner is PlayerState; animation and the Lua combat module belong to Avatar.
    local Avatar = self:GetAvatarActorFromActorInfo()
    ---@type AttackSystem?
    local CombatSystem = IsValid(Avatar) and Avatar.AttackSystem or nil
    self.LightAttack = CombatSystem and CombatSystem:GetAttack(AttackType.Light) or nil
    if not self.LightAttack or not self.LightAttack:BeginAttack(self) then
        self:FinishLightAttack(true)
        return
    end

    local Committed = self:K2_CommitAbility()
    if not Committed then
        self:FinishLightAttack(true)
        return
    end

    self:PlaySwordDraw()
end

function M:PlaySwordDraw()
    if not self.Ending and self.LightAttack then
        self:PlaySwordAction(self.LightAttack.SwordDrawMontage, AttackPhase.Drawing)
    end
end

function M:PlaySwordSheathe()
    if not self.Ending and self.LightAttack then
        self:PlaySwordAction(self.LightAttack.SwordSheatheMontage, AttackPhase.Sheathing)
    end
end

---@param Phase AttackPhase
function M:PlaySwordAction(Montage, Phase)
    self:ClearComboWaitTask()
    self:ClearAttackTimingTasks()
    self:ClearMontageTask()
    if not self.LightAttack or not self.LightAttack:HasCurrentWeapon() then
        self:FinishLightAttack(true)
        return
    end
    if not IsValid(Montage) then
        -- 拔出/收起动画可选，没有配置的武器直接出招或正常结束。
        if Phase == AttackPhase.Drawing then
            self.LightAttack:OnSwordDrawReady(self)
        else
            self:FinishLightAttack(false)
        end
        return
    end
    local Task = UE.UAbilityTask_PlayMontageAndWait.CreatePlayMontageAndWaitProxy(
        self, Phase, Montage, self.LightAttack.SwordActionPlayRate, "", true, 1.0, 0.0, true)
    if not Task or not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end
    self.MontagePhase = Phase
    self.MontageTask = Task
    Task.OnBlendOut:Add(self, self.OnMontageBlendOut)
    Task.OnCompleted:Add(self, self.OnMontageCompleted)
    Task.OnInterrupted:Add(self, self.OnMontageInterrupted)
    Task.OnCancelled:Add(self, self.OnMontageInterrupted)
    -- 收拔剑只覆盖上半身，释放本技能持有的移动锁。
    self:UnlockMoveInput()
    print("GA_LightAttack: sword", Phase, Montage:GetName())
    Task:ReadyForActivation()
    if not self.Ending and self.MontageTask == Task then
        self:StartWeaponAttachTask(Phase, Montage)
    end
    if Phase == AttackPhase.Drawing and not self.Ending and self.MontageTask == Task then
        local ReadyTime = math.min(self.LightAttack.SwordDrawReadyTime or Montage:GetPlayLength(), Montage:GetPlayLength())
        local Rate = self.LightAttack.SwordActionPlayRate * math.max(0.1, Montage.RateScale)
        ---@type AttackDelayTask?
        local DrawTask = UE.UAbilityTask_WaitDelay.WaitDelay(self, math.max(0.01, ReadyTime / Rate))
        if not DrawTask or not IsValid(DrawTask) then
            self:FinishLightAttack(true)
            return
        end
        self.SwordDrawTask = DrawTask
        DrawTask.OnFinish:Add(self, self.OnSwordDrawTimedReady)
        DrawTask:ReadyForActivation()
    end
end

function M:ApplyWeaponAttachment(Drawn)
    local Weapon = self.LightAttack and self.LightAttack.ActiveWeapon
    if not Weapon or not IsValid(Weapon) then return false end
    return WeaponBase.SetWeaponDrawn(Weapon, Drawn)
end

function M:StartWeaponAttachTask(Phase, Montage)
    local LightAttack = self.LightAttack
    local Weapon = LightAttack and LightAttack.ActiveWeapon
    if not LightAttack or not Weapon or not IsValid(Weapon) then
        self:FinishLightAttack(true)
        return
    end
    local Drawn = Phase == AttackPhase.Drawing
    local Time
    if Drawn then Time = Weapon.WeaponDrawAttachTime else Time = Weapon.WeaponSheatheAttachTime end
    if Time == nil then return end
    local Rate = LightAttack.SwordActionPlayRate * math.max(0.1, Montage.RateScale)
    self.PendingWeaponDrawn = Drawn
    ---@type AttackDelayTask?
    local Task = UE.UAbilityTask_WaitDelay.WaitDelay(self,
        math.max(0.01, math.min(Time, Montage:GetPlayLength()) / Rate))
    if not Task or not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end
    self.WeaponAttachTask = Task
    Task.OnFinish:Add(self, self.OnWeaponAttachMoment)
    Task:ReadyForActivation()
end

function M:OnWeaponAttachMoment()
    local Drawn = self.PendingWeaponDrawn
    self:ClearWeaponAttachTask()
    if not self.Ending and (not self.LightAttack or not self.LightAttack:HasCurrentWeapon()
        or not self:ApplyWeaponAttachment(Drawn)) then
        self:FinishLightAttack(true)
    end
end

function M:ClearWeaponAttachTask()
    local Task = self.WeaponAttachTask
    self.WeaponAttachTask = nil
    self.PendingWeaponDrawn = nil
    if Task and IsValid(Task) then
        Task.OnFinish:Remove(self, self.OnWeaponAttachMoment)
        Task:EndTask()
    end
end

function M:OnSwordDrawTimedReady()
    self:ClearSwordDrawTask()
    if not self.Ending and self.MontagePhase == AttackPhase.Drawing and self.LightAttack then
        self.LightAttack:OnSwordDrawReady(self)
    end
end

function M:ClearSwordDrawTask()
    local Task = self.SwordDrawTask
    self.SwordDrawTask = nil
    if Task and IsValid(Task) then
        Task.OnFinish:Remove(self, self.OnSwordDrawTimedReady)
        Task:EndTask()
    end
end

function M:PlayCurrentAttack()
    if self.Ending then
        return
    end

    self:ClearComboWaitTask()
    self:ClearAttackTimingTasks()
    self:ClearMontageTask()

    local Montage = self.LightAttack:GetCurrentAttackMontage()
    if not Montage or not IsValid(Montage) then
        self:FinishLightAttack(true)
        return
    end

    if not self:ApplyWeaponAttachment(true) then
        self:FinishLightAttack(true)
        return
    end

    local Timing = self.LightAttack:GetCurrentAttackTiming()
    if not Timing then
        self:FinishLightAttack(true)
        return
    end
    local Length = Montage:GetPlayLength()
    local StartTime = math.max(0.0, math.min(Timing.StartTime, Length - 0.1))
    local PlayRate = math.max(0.1, Timing.PlayRate)
    local EffectiveRate = PlayRate * math.max(0.1, Montage.RateScale)
    local Task = UE.UAbilityTask_PlayMontageAndWait.CreatePlayMontageAndWaitProxy(
        self, "LightAttack", Montage, PlayRate, "", true, 1.0, StartTime, true)
    if not Task or not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end

    self.MontagePhase = AttackPhase.Attacking
    self.MontageTask = Task
    Task.OnBlendOut:Add(self, self.OnMontageBlendOut)
    Task.OnCompleted:Add(self, self.OnMontageCompleted)
    Task.OnInterrupted:Add(self, self.OnMontageInterrupted)
    Task.OnCancelled:Add(self, self.OnMontageInterrupted)
    self:LockMoveInput()
    print("GA_LightAttack: play", self.LightAttack.ComboIndex, Montage:GetName())
    Task:ReadyForActivation()
    -- 播放失败可能同步触发 OnCancelled，此时不能再创建计时任务。
    if not self.Ending and self.MontageTask == Task then
        self:StartAttackTimingTasks(Timing, StartTime, EffectiveRate, Length)
    end
end

function M:StartAttackTimingTasks(Timing, StartTime, PlayRate, Length)
    local RecoveryTime = math.min(Timing.RecoveryTime, Length)
    if Timing.ComboTime then
        local ComboTime = math.min(Timing.ComboTime, RecoveryTime)
        ---@type AttackDelayTask?
        local Task = UE.UAbilityTask_WaitDelay.WaitDelay(self, math.max(0.01, (ComboTime - StartTime) / PlayRate))
        if not Task or not IsValid(Task) then
            self:FinishLightAttack(true)
            return
        end
        self.ComboWindowTask = Task
        Task.OnFinish:Add(self, self.OnAttackComboWindowOpened)
        Task:ReadyForActivation()
    end

    ---@type AttackDelayTask?
    local Task = UE.UAbilityTask_WaitDelay.WaitDelay(self, math.max(0.01, (RecoveryTime - StartTime) / PlayRate))
    if not Task or not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end
    self.AttackRecoveryTask = Task
    Task.OnFinish:Add(self, self.OnAttackRecoveryReady)
    Task:ReadyForActivation()
end

function M:OnAttackComboWindowOpened()
    local Task = self.ComboWindowTask
    self.ComboWindowTask = nil
    if Task and IsValid(Task) then
        Task.OnFinish:Remove(self, self.OnAttackComboWindowOpened)
        Task:EndTask()
    end
    if not self.Ending and self.LightAttack then
        self.LightAttack:OnLightAttackComboWindow(self)
    end
end

function M:OnAttackRecoveryReady()
    self:ClearAttackTimingTasks()
    if not self.Ending and self.LightAttack then
        self.LightAttack:OnLightAttackRecoveryReady(self)
    end
end

function M:StopCurrentAttack()
    self:ClearAttackTimingTasks()
    -- 先移除旧任务回调，再停止蒙太奇，避免把主动截短后摇当成技能中断。
    self:ClearMontageTask()
    self:MontageStop(0.08)
end

function M:OnMontageBlendOut()
    if not self.Ending and self.LightAttack then
        if self.MontagePhase == AttackPhase.Drawing then
            -- 在拔剑最后的混出阶段接第一刀，避免回到站姿再起手。
            self.LightAttack:OnSwordDrawReady(self)
        elseif self.MontagePhase == AttackPhase.Attacking then
            self.LightAttack:OnLightAttackComboWindow(self)
        end
    end
end

function M:OnMontageCompleted()
    if self.Ending then
        return
    end

    local Phase = self.MontagePhase
    self:ClearAttackTimingTasks()
    self:ClearMontageTask()
    if self.LightAttack then
        if Phase == AttackPhase.Drawing then
            self.LightAttack:OnSwordDrawReady(self)
        elseif Phase == AttackPhase.Attacking then
            self.LightAttack:OnLightAttackRecoveryReady(self)
        elseif Phase == AttackPhase.Sheathing then
            self:FinishLightAttack(false)
        end
    end
end

function M:OnMontageInterrupted()
    self:FinishLightAttack(true)
end

function M:WaitForComboInput(Duration)
    if self.Ending then
        return
    end

    self:ClearComboWaitTask()
    -- Recovery is complete; movement is allowed while waiting for the next press.
    self:UnlockMoveInput()
    ---@type AttackDelayTask?
    local Task = UE.UAbilityTask_WaitDelay.WaitDelay(self, Duration)
    if not Task or not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end

    self.ComboWaitTask = Task
    Task.OnFinish:Add(self, self.OnComboInputExpired)
    Task:ReadyForActivation()
end

function M:OnComboInputExpired()
    if not self.Ending and self.LightAttack then
        self.LightAttack:BeginSwordSheathe(self)
    end
end

function M:LockMoveInput()
    if IsValid(self.MoveInputController) then
        return
    end

    local Avatar = self:GetAvatarActorFromActorInfo()
    if not IsValid(Avatar) then
        return
    end

    local Controller = Avatar:GetController()
    if IsValid(Controller) then
        Controller:SetIgnoreMoveInput(true)
        self.MoveInputController = Controller
    end

    Avatar:ConsumeMovementInputVector()
    local Movement = Avatar:GetMovementComponent()
    if IsValid(Movement) then
        Movement:StopMovementImmediately()
    end
end

function M:UnlockMoveInput()
    local Controller = self.MoveInputController
    self.MoveInputController = nil
    if IsValid(Controller) then
        -- SetIgnoreMoveInput stacks: release only the lock acquired by this ability.
        Controller:SetIgnoreMoveInput(false)
    end
end

function M:ClearMontageTask(AbilityEnding)
    self:ClearWeaponAttachTask()
    self:ClearSwordDrawTask()
    local Task = self.MontageTask
    self.MontageTask = nil
    self.MontagePhase = nil
    if Task and IsValid(Task) then
        Task.OnBlendOut:Remove(self, self.OnMontageBlendOut)
        Task.OnCompleted:Remove(self, self.OnMontageCompleted)
        Task.OnInterrupted:Remove(self, self.OnMontageInterrupted)
        Task.OnCancelled:Remove(self, self.OnMontageInterrupted)
        -- During OnEndAbility, GAS must call TaskOwnerEnded so StopWhenAbilityEnds is honored.
        if not AbilityEnding then
            Task:EndTask()
        end
    end
end

function M:ClearComboWaitTask()
    local Task = self.ComboWaitTask
    self.ComboWaitTask = nil
    if Task and IsValid(Task) then
        Task.OnFinish:Remove(self, self.OnComboInputExpired)
        Task:EndTask()
    end
end

function M:ClearAttackTimingTasks()
    local WindowTask = self.ComboWindowTask
    self.ComboWindowTask = nil
    if WindowTask and IsValid(WindowTask) then
        WindowTask.OnFinish:Remove(self, self.OnAttackComboWindowOpened)
        WindowTask:EndTask()
    end
    local RecoveryTask = self.AttackRecoveryTask
    self.AttackRecoveryTask = nil
    if RecoveryTask and IsValid(RecoveryTask) then
        RecoveryTask.OnFinish:Remove(self, self.OnAttackRecoveryReady)
        RecoveryTask:EndTask()
    end
end

function M:FinishLightAttack(Cancelled)
    if self.Ending then
        return
    end

    self.Ending = true
    if Cancelled then
        self:K2_CancelAbility()
    else
        self:K2_EndAbility()
    end
end

function M:K2_OnEndAbility(WasCancelled)
    self.Ending = true
    self:UnlockMoveInput()
    self:ClearComboWaitTask()
    self:ClearAttackTimingTasks()
    self:ClearMontageTask(true)
    if self.LightAttack then
        if self.LightAttack:HasCurrentWeapon() then
            self:ApplyWeaponAttachment(false)
        end
        self.LightAttack:OnAttackEnded(self)
    end
    self.LightAttack = nil
    print("GA_LightAttack: ended", WasCancelled)
end

return M
