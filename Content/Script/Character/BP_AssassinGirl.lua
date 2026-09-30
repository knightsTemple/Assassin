--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@class BP_AssassinGirl_C
---@field AttackSystem? AttackSystem
---@field GetAssassinAttributeSet fun(self: BP_AssassinGirl_C): any
---@field Overridden any
local M = UnLua.Class()
local AttackSystem = require("Combat.AttackSystem")
local EnhancedInput = require("UnLua.EnhancedInput")

-- function M:Initialize(Initializer)
-- end

-- function M:UserConstructionScript()
-- end

function M:ReceiveBeginPlay()

end

function M:OnGASInitialized()
    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(self)
    local AttributeSet = self:GetAssassinAttributeSet()

    if not ASC then
        return
    end

    if not AttributeSet then
        return
    end

    if not self.AttackSystem then
        self.AttackSystem = AttackSystem.New(self)
    end

    if self.AttackSystem then
        self.AttackSystem:GrantLightAttack()
    end
end

function M:OnLightAttackStarted()
    if self.AttackSystem then
        self.AttackSystem:LightAttack()
    end
end

EnhancedInput.BindAction(M, "/Game/Input/IA_LightAttack.IA_LightAttack", "Started", M.OnLightAttackStarted)

function M:ReceiveEndPlay(EndPlayReason)
    if self.AttackSystem then
        self.AttackSystem:Destroy()
        self.AttackSystem = nil
    end
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
end

-- function M:ReceiveTick(DeltaSeconds)
-- end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
