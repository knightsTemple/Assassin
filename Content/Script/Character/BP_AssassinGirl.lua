--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@class BP_AssassinGirl_C
---@field HasAuthority fun(self: BP_AssassinGirl_C): boolean
---@field AttackSystem? AttackSystem
---@field WeaponEquipment? WeaponEquipment
---@field DefaultHandheldWeapon? any
---@field HandheldWeapon? AssassinWeaponBase
---@field ShieldWeapon? AssassinWeaponBase
---@field BowWeapon? AssassinWeaponBase
---@field HiddenBladeWeapon? AssassinWeaponBase
---@field GetAssassinAttributeSet fun(self: BP_AssassinGirl_C): any
---@field Overridden any
local M = UnLua.Class()
local AttackSystem = require("Combat.AttackSystem")
local WeaponEquipment = require("Weapon.WeaponEquipment")
local BackClothCollision = require("Weapon.BackClothCollision")
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

    if not self.WeaponEquipment then
        self.WeaponEquipment = WeaponEquipment.New(self)
    end
    if self.WeaponEquipment then
        self.WeaponEquipment:EquipConfigured()
        local Equipped, Reason = self.WeaponEquipment:EquipDefaultHandheld()
        if not Equipped then
            print("BP_AssassinGirl: default weapon equip failed", Reason)
        end
    end

    if not self.AttackSystem then
        self.AttackSystem = AttackSystem.New(self)
    end

    if self.AttackSystem then
        self.AttackSystem:GrantAbilities()
    end
end

-- Lua 调用：self:EquipWeapon(WeaponActor)，剑/斧头自动进入手持栏位。
-- 袖箭：self:EquipWeapon(WeaponActor, "HiddenBladeWeapon")。
---@param Weapon AssassinWeaponBase
---@param Slot? WeaponSlot
---@return boolean, string?
function M:EquipWeapon(Weapon, Slot)
    if not self.WeaponEquipment then return false, "角色 GAS 尚未就绪" end
    return self.WeaponEquipment:Equip(Weapon, Slot)
end

---@param Slot WeaponSlot
---@return boolean, string?
function M:UnequipWeapon(Slot)
    if not self.WeaponEquipment then return false, "角色 GAS 尚未就绪" end
    return self.WeaponEquipment:Unequip(Slot)
end

function M:OnLightAttackStarted()
    if self.AttackSystem then
        self.AttackSystem:LightAttack()
    end
end

EnhancedInput.BindAction(M, "/Game/Input/IA_LightAttack.IA_LightAttack", "Started", M.OnLightAttackStarted)

function M:ReceiveEndPlay(EndPlayReason)
    if self.WeaponEquipment then
        self.WeaponEquipment:Destroy()
        self.WeaponEquipment = nil
    end
    if self.AttackSystem then
        self.AttackSystem:Destroy()
        self.AttackSystem = nil
    end
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
end

-- The visual child actor may initialize after GAS or change during play.
function M:ReceiveTick(DeltaSeconds)
    self.Overridden.ReceiveTick(self, DeltaSeconds)
    self._ClothRefreshTime = (self._ClothRefreshTime or 0) + DeltaSeconds
    if self._ClothRefreshTime < 0.25 then return end
    self._ClothRefreshTime = 0
    local Weapon = self.HandheldWeapon
    if Weapon and UE.UKismetSystemLibrary.IsValid(Weapon) then
        BackClothCollision.Update(Weapon)
    end
end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
