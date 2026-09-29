--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@type BP_AssassinGirl_C
local M = UnLua.Class()
local AttackSystem = require("Combat.AttackSystem")

-- function M:Initialize(Initializer)
-- end

-- function M:UserConstructionScript()
-- end

function M:ReceiveBeginPlay()

end

function M:OnGASInitialized()
    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(self)
    local AttributeSet = self:GetAssassinAttributeSet()

    print("GAS Initialized")

    if not ASC then
        print("ASC is nil")
        return
    end
    print("ASC valid:", ASC)

    if not AttributeSet then
        print("AttributeSet is nil")
        return
    end
    print("AttributeSet valid:", AttributeSet)

    if not self.AttackSystem then
        self.AttackSystem = AttackSystem.New(self)
        if self.AttackSystem then
            print("AttackSystem initialized:", self.AttackSystem.Owner, self.AttackSystem.ASC, self.AttackSystem.ComboIndex)
        end
    end

    local AttributeNames = {
        "Health",
        "MaxHealth",
        "AttackPower",
        "AssassinationPower",
        "Defense",
        "CritChance",
        "CritDamageBonus",
        "MoveSpeed",
        "Adrenaline",
        "MaxAdrenaline",
    }

    for _, Name in ipairs(AttributeNames) do
        local AttributeData = AttributeSet[Name]
        if AttributeData then
            print(Name .. " = " .. tostring(AttributeData.CurrentValue))
        else
            print(Name .. " is nil")
        end
    end
end

function M:OnHealthChanged(OldValue, NewValue)
    print("Health Changed:", OldValue, "->", NewValue)
end

-- function M:ReceiveEndPlay()
-- end

-- function M:ReceiveTick(DeltaSeconds)
-- end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
