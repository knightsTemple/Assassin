local AttackSystem = {}
AttackSystem.__index = AttackSystem

function AttackSystem.New(Owner)
    if not Owner then
        return nil
    end

    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(Owner)
    if not ASC then
        print("AttackSystem: ASC is nil")
        return nil
    end

    return setmetatable({
        Owner = Owner,
        ASC = ASC,
        ComboIndex = 0,
    }, AttackSystem)
end

function AttackSystem:LightAttack()
    -- TODO: Activate Assassin.Ability.Attack.Light through ASC when the ability exists.
end

function AttackSystem:HeavyAttack()
    -- TODO: Activate Assassin.Ability.Attack.Heavy through ASC when the ability exists.
end

function AttackSystem:ResetCombo()
    self.ComboIndex = 0
end

function AttackSystem:Destroy()
    self.Owner = nil
    self.ASC = nil
    self.ComboIndex = 0
end

return AttackSystem
