---@class GA_LightAttack_C
---@field AttackSystem? AttackSystem
---@field Ending boolean
---@field MontageTask? any
---@field ComboWaitTask? any
---@field MoveInputController? any
---@field GetAvatarActorFromActorInfo fun(self: GA_LightAttack_C): any
---@field K2_CommitAbility fun(self: GA_LightAttack_C): boolean
---@field K2_CancelAbility fun(self: GA_LightAttack_C)
---@field K2_EndAbility fun(self: GA_LightAttack_C)
local M = UnLua.Class()

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

function M:K2_ActivateAbility()
    self.Ending = false
    self.MontageTask = nil
    self.ComboWaitTask = nil
    self.MoveInputController = nil

    -- ASC Owner is PlayerState; animation and the Lua combat module belong to Avatar.
    local Avatar = self:GetAvatarActorFromActorInfo()
    ---@type AttackSystem?
    local CombatSystem = IsValid(Avatar) and Avatar.AttackSystem or nil
    self.AttackSystem = CombatSystem
    if not CombatSystem or not CombatSystem:BeginLightAttack(self) then
        self:FinishLightAttack(true)
        return
    end

    local Committed = self:K2_CommitAbility()
    if not Committed then
        self:FinishLightAttack(true)
        return
    end

    self:PlayCurrentAttack()
end

function M:PlayCurrentAttack()
    if self.Ending then
        return
    end

    self:ClearComboWaitTask()
    self:ClearMontageTask()

    local Montage = self.AttackSystem:GetCurrentAttackMontage()
    if not IsValid(Montage) then
        self:FinishLightAttack(true)
        return
    end

    local Task = UE.UAbilityTask_PlayMontageAndWait.CreatePlayMontageAndWaitProxy(
        self, "LightAttack", Montage, 1.0, "", true, 1.0, 0.0, true)
    if not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end

    self.MontageTask = Task
    Task.OnBlendOut:Add(self, self.OnMontageBlendOut)
    Task.OnCompleted:Add(self, self.OnMontageCompleted)
    Task.OnInterrupted:Add(self, self.OnMontageInterrupted)
    Task.OnCancelled:Add(self, self.OnMontageInterrupted)
    self:LockMoveInput()
    print("GA_LightAttack: play", self.AttackSystem.ComboIndex, Montage:GetName())
    Task:ReadyForActivation()
end

function M:OnMontageBlendOut()
    if not self.Ending and self.AttackSystem then
        self.AttackSystem:OnLightAttackBlendOut(self)
    end
end

function M:OnMontageCompleted()
    if self.Ending then
        return
    end

    self:ClearMontageTask()
    if self.AttackSystem then
        self.AttackSystem:OnLightAttackMontageCompleted(self)
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
    local Task = UE.UAbilityTask_WaitDelay.WaitDelay(self, Duration)
    if not IsValid(Task) then
        self:FinishLightAttack(true)
        return
    end

    self.ComboWaitTask = Task
    Task.OnFinish:Add(self, self.OnComboInputExpired)
    Task:ReadyForActivation()
end

function M:OnComboInputExpired()
    self:FinishLightAttack(false)
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
    local Task = self.MontageTask
    self.MontageTask = nil
    if IsValid(Task) then
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
    if IsValid(Task) then
        Task.OnFinish:Remove(self, self.OnComboInputExpired)
        Task:EndTask()
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
    self:ClearMontageTask(true)
    if self.AttackSystem then
        self.AttackSystem:OnLightAttackEnded(self)
    end
    self.AttackSystem = nil
    print("GA_LightAttack: ended", WasCancelled)
end

return M
