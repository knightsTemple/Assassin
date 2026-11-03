local AttackType = require("Combat.attack.AttackPhase").AttackType
local LightAttack = require("Combat.attack.LightAttack")

---@class AttackModule
---@field GrantAbility fun(self: AttackModule): boolean
---@field HandleInput fun(self: AttackModule): boolean
---@field Destroy fun(self: AttackModule)

---@class AttackSystem
---@field Owner any
---@field ASC any
---@field Attacks table<AttackType, AttackModule>
---@field ActiveAttack? AttackModule
---@field Destroyed boolean
local AttackSystem = {}
AttackSystem.__index = AttackSystem

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

    local System = setmetatable({
        Owner = Owner,
        ASC = ASC,
        Attacks = {},
        ActiveAttack = nil,
        Destroyed = false,
    }, AttackSystem)

    local Light = LightAttack.New(System)
    if not Light then
        System:Destroy()
        return nil
    end
    System.Attacks[AttackType.Light] = Light
    return System
end

---@param Type AttackType
---@return AttackModule?
function AttackSystem:GetAttack(Type)
    if self.Destroyed then
        return nil
    end
    return self.Attacks[Type]
end

---@return boolean
function AttackSystem:GrantAbilities()
    if self.Destroyed then
        return false
    end

    local Granted = true
    for _, Attack in pairs(self.Attacks) do
        if not Attack:GrantAbility() then
            Granted = false
        end
    end
    return Granted
end

---@param Type AttackType
---@return boolean
function AttackSystem:RequestAttack(Type)
    local Attack = self:GetAttack(Type)
    if not Attack or (self.ActiveAttack and self.ActiveAttack ~= Attack) then
        return false
    end
    return Attack:HandleInput()
end

-- 技能激活时向攻击系统申请互斥占用
---@param Attack AttackModule
---@return boolean
function AttackSystem:TryBeginAttack(Attack)
    if self.Destroyed or not Attack or self.ActiveAttack then
        return false
    end
    self.ActiveAttack = Attack
    return true
end

---@param Attack AttackModule
function AttackSystem:EndAttack(Attack)
    if self.ActiveAttack == Attack then
        self.ActiveAttack = nil
    end
end

function AttackSystem:LightAttack()
    return self:RequestAttack(AttackType.Light)
end

function AttackSystem:HeavyAttack()
    return self:RequestAttack(AttackType.Heavy)
end

function AttackSystem:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for _, Attack in pairs(self.Attacks) do
        Attack:Destroy()
    end
    self.Attacks = {}
    self.ActiveAttack = nil
    self.Owner = nil
    self.ASC = nil
end

return AttackSystem
