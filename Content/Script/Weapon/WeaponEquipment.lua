-- 角色侧的武器栏位管理；模型挂接和属性 GE 由 WeaponBase 负责。
-- 使用已生成的武器 Actor，不在此处隐式生成或销毁武器。
---@alias WeaponSlot "HandheldWeapon"|"ShieldWeapon"|"BowWeapon"|"HiddenBladeWeapon"
---@class WeaponEquipment
---@field Owner BP_AssassinGirl_C
---@field WeaponClass any
local WeaponEquipment = {}
WeaponEquipment.__index = WeaponEquipment

WeaponEquipment.Slots = {
    "HandheldWeapon", "ShieldWeapon", "BowWeapon", "HiddenBladeWeapon",
}
local ValidSlots = {}
for _, Slot in ipairs(WeaponEquipment.Slots) do
    ValidSlots[Slot] = true
end

local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

function WeaponEquipment.New(Owner)
    if not IsValid(Owner) then return nil end
    return setmetatable({
        Owner = Owner, Busy = false, Destroyed = false,
        WeaponClass = UE.UClass.Load("/Script/Assassin.AssassinWeaponBase"),
    }, WeaponEquipment)
end

-- 袖箭尚无独立 WeaponType，调用方须显式传入 HiddenBladeWeapon。
function WeaponEquipment:ResolveSlot(Weapon)
    local Types = UE.EAssassinWeaponType
    if Weapon.WeaponType == Types.Shield then return "ShieldWeapon" end
    if Weapon.WeaponType == Types.Bow then return "BowWeapon" end
    if Weapon.WeaponType == Types.Sword or Weapon.WeaponType == Types.LongBlade
        or Weapon.WeaponType == Types.Axe then
        return "HandheldWeapon"
    end
    return nil
end

-- 防止装备回调再次进入换装流程；异常时也释放锁。
function WeaponEquipment:Change(Action)
    if self.Destroyed or self.Busy or not IsValid(self.Owner)
        or not self.Owner:HasAuthority() then
        return false, "角色无权限或正在换装"
    end
    self.Busy = true
    local OK, Result, Reason = xpcall(Action, debug.traceback)
    self.Busy = false
    if not OK then
        print("WeaponEquipment: " .. tostring(Result))
        return false, "装配异常，详见日志"
    end
    return Result, Reason
end

---@param Weapon AssassinWeaponBase
---@param Slot? WeaponSlot 默认根据武器类型选择；袖箭必须指定栏位
---@return boolean, string?
function WeaponEquipment:Equip(Weapon, Slot)
    if not IsValid(Weapon) or not IsValid(self.WeaponClass)
        or not Weapon:IsA(self.WeaponClass) then
        return false, "需要武器基类的有效 Actor 实例"
    end
    Slot = Slot or self:ResolveSlot(Weapon)
    if not Slot or not ValidSlots[Slot] then return false, "无效的武器栏位" end
    if Slot ~= "HiddenBladeWeapon" and Slot ~= self:ResolveSlot(Weapon) then
        return false, "武器类型与栏位不匹配"
    end
    return self:Change(function()
        local Owner = self.Owner
        if IsValid(Weapon.EquippedCharacter) and Weapon.EquippedCharacter ~= Owner then
            return false, "武器已由其他角色装备"
        end
        for _, OtherSlot in ipairs(WeaponEquipment.Slots) do
            if OtherSlot ~= Slot and Owner[OtherSlot] == Weapon then
                return false, "同一武器不能占用多个栏位"
            end
        end

        local Previous = Owner[Slot]
        if Slot == "HandheldWeapon" and Previous ~= Weapon
            and Owner.AttackSystem and Owner.AttackSystem.ActiveAttack then
            return false, "攻击期间不能更换手持武器"
        end
        if Previous == Weapon then
            -- 武器基类处理幂等装备；也支持首次装配预先配置的 Actor。
            return Weapon:EquipToCharacter(Owner)
        end
        if Previous and IsValid(Previous) and IsValid(Previous.EquippedCharacter)
            and Previous.EquippedCharacter ~= Owner then
            return false, "原栏位引用了其他角色的武器"
        end

        local WasEquipped = Previous ~= nil and IsValid(Previous) and Previous.EquippedCharacter == Owner
        if WasEquipped and Previous and not Previous:UnequipFromCharacter() then
            return false, "原武器卸装失败"
        end
        Owner[Slot] = nil
        if Weapon:EquipToCharacter(Owner) then
            Owner[Slot] = Weapon
            return true
        end

        if WasEquipped then
            if Previous and IsValid(Previous) and Previous:EquipToCharacter(Owner) then
                Owner[Slot] = Previous
                return false, "新武器装配失败，已恢复原武器"
            end
            return false, "新武器装配失败，原武器恢复失败，栏位已清空"
        end
        if IsValid(Previous) then Owner[Slot] = Previous end
        return false, "新武器装配失败"
    end)
end

---@param Slot WeaponSlot
---@return boolean, string?
function WeaponEquipment:Unequip(Slot)
    if not ValidSlots[Slot] then return false, "无效的武器栏位" end
    return self:Change(function()
        if Slot == "HandheldWeapon" and self.Owner.AttackSystem
            and self.Owner.AttackSystem.ActiveAttack then
            return false, "攻击期间不能卸下手持武器"
        end
        local Weapon = self.Owner[Slot]
        if IsValid(Weapon) and Weapon.EquippedCharacter == self.Owner
            and not Weapon:UnequipFromCharacter() then
            return false, "武器卸装失败"
        end
        -- 只清除过期/错误引用，不卸装其他角色的装备。
        self.Owner[Slot] = nil
        return true
    end)
end

-- 默认武器类由角色蓝图的 ChildActorComponent 选择，不在 Lua 写死资源路径。
function WeaponEquipment:EquipDefaultHandheld()
    if IsValid(self.Owner.HandheldWeapon) then return true end
    local Component = self.Owner.DefaultHandheldWeapon
    if not IsValid(Component) then return true end
    -- GetChildActor 是未反射的 C++ 方法，UnLua 使用 BlueprintReadOnly 属性。
    local Weapon = Component.ChildActor
    if not IsValid(Weapon) then return false, "默认武器组件尚未生成 Actor" end
    return self:Equip(Weapon, "HandheldWeapon")
end

-- GAS 就绪后装配角色实例中预先设置的武器引用。
function WeaponEquipment:EquipConfigured()
    local Success = true
    for _, Slot in ipairs(WeaponEquipment.Slots) do
        local Weapon = self.Owner[Slot]
        if IsValid(Weapon) then
            local OK, Reason = self:Equip(Weapon, Slot)
            if not OK then
                Success = false
                print("WeaponEquipment: " .. Slot .. ": " .. tostring(Reason))
            end
        end
    end
    return Success
end

function WeaponEquipment:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    local Owner = self.Owner
    -- EndPlay 时角色可能已被标记为无效，仍需移除 PlayerState ASC 上的装备效果。
    if Owner then
        for _, Slot in ipairs(WeaponEquipment.Slots) do
            local Weapon = Owner[Slot]
            if IsValid(Weapon) and Weapon.EquippedCharacter == Owner then
                Weapon:UnequipFromCharacter()
            end
            Owner[Slot] = nil
        end
    end
    self.Owner = nil
end

return WeaponEquipment
