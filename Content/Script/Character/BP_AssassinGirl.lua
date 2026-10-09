--
-- DESCRIPTION
--
-- @COMPANY **
-- @AUTHOR **
-- @DATE ${date} ${time}
--

---@class BP_AssassinGirl_C
---@field AttackSystem? AttackSystem
---@field LightAttackAbilityClass any 蓝图配置的 GameplayAbility 类引用
---@field WeaponEquipment? WeaponEquipment
---@field Events? EventBus 当前角色独立持有的事件总线
---@field ClothCollision? BackClothCollision 布料碰撞表现监听器
---@field _EndingGameplay? boolean 阻止退出过程中重新初始化或发布普通业务事件
---@field DefaultHandheldWeapon? any
---@field HandheldWeapon? AssassinWeaponBase
---@field ShieldWeapon? AssassinWeaponBase
---@field BowWeapon? AssassinWeaponBase
---@field HiddenBladeWeapon? AssassinWeaponBase
---@field GetAssassinAttributeSet fun(self: BP_AssassinGirl_C): any
---@field Overridden any
local M = UnLua.Class()
local AttackSystem = require("Combat.attack.AttackSystem")
local WeaponEquipment = require("Weapon.WeaponEquipment")
local BackClothCollision = require("Weapon.BackClothCollision")
local EventBus = require("Core.EventSubscribe.EventBus")
local EnhancedInput = require("UnLua.EnhancedInput")

-- function M:Initialize(Initializer)
-- end

-- function M:UserConstructionScript()
-- end

function M:ReceiveBeginPlay()

end

function M:OnGASInitialized()
    if self._EndingGameplay then return end
    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(self)
    local AttributeSet = self:GetAssassinAttributeSet()

    if not ASC then
        return
    end

    if not AttributeSet then
        return
    end

    -- 先建立总线及监听，再执行初始装备；重复 GAS 初始化不重复订阅。
    if not self.Events then self.Events = EventBus.New() end
    if not self.ClothCollision then
        self.ClothCollision = BackClothCollision.New(self, self.Events)
    end
    if not self.WeaponEquipment then
        self.WeaponEquipment = WeaponEquipment.New(self, self.Events)
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
    self._EndingGameplay = true
    -- 先停止攻击，再清理表现和装备，最后释放总线，避免清理过程中继续触发业务。
    if self.AttackSystem then
        self.AttackSystem:Destroy()
        self.AttackSystem = nil
    end
    if self.ClothCollision then
        self.ClothCollision:Destroy()
        self.ClothCollision = nil
    end
    if self.WeaponEquipment then
        self.WeaponEquipment:Destroy()
        self.WeaponEquipment = nil
    end
    if self.Events then
        self.Events:Destroy()
        self.Events = nil
    end
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
end

-- 角色只转发生命周期；刷新间隔及具体碰撞处理由表现模块负责。
function M:ReceiveTick(DeltaSeconds)
    self.Overridden.ReceiveTick(self, DeltaSeconds)
    if self.ClothCollision then self.ClothCollision:Tick(DeltaSeconds) end
end

-- function M:ReceiveAnyDamage(Damage, DamageType, InstigatedBy, DamageCauser)
-- end

-- function M:ReceiveActorBeginOverlap(OtherActor)
-- end

-- function M:ReceiveActorEndOverlap(OtherActor)
-- end

return M
