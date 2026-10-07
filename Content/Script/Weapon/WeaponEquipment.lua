-- 角色侧统一管理武器栏位、装备 GE 和效果句柄；武器负责属性计算与模型挂接。
-- 使用已生成的武器 Actor，不在此处隐式生成或销毁武器。
---@alias WeaponSlot "HandheldWeapon"|"ShieldWeapon"|"BowWeapon"|"HiddenBladeWeapon"
---@class WeaponEquipment
---@field Owner BP_AssassinGirl_C
---@field WeaponClass any
---@field Records table<AssassinWeaponBase, table> 按武器保存 ASC、基础属性句柄和全部装备效果句柄
local WeaponEquipment = {}
WeaponEquipment.__index = WeaponEquipment

WeaponEquipment.Slots = {
    "HandheldWeapon", "ShieldWeapon", "BowWeapon", "HiddenBladeWeapon",
}
local ValidSlots = {}
for _, Slot in ipairs(WeaponEquipment.Slots) do
    ValidSlots[Slot] = true
end

-- 检查对象是否存在且仍是有效的 UE 对象。
local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

-- 规范效果等级使用的数值，排除非数字、无穷值和负值。
local function NonNegative(Value)
    if type(Value) ~= "number" or Value ~= Value or Value == math.huge or Value == -math.huge then return 0 end
    return math.max(0, Value)
end

-- 校验装备 GE 是否有效且不使用堆叠；基础属性要求无限持续，附加效果也可使用有限持续时间。
local function SupportsEquipmentEffect(EffectClass, MustBeInfinite)
    if not IsValid(EffectClass) then
        return false
    end
    local Defaults = EffectClass:GetDefaultObject()
    if not IsValid(Defaults) or Defaults.StackingType ~= UE.EGameplayEffectStackingType.None then
        return false
    end
    local Policy = Defaults.DurationPolicy
    if MustBeInfinite then
        return Policy == UE.EGameplayEffectDurationType.Infinite
    end
    -- Instant effects have no removable active handle and cannot represent equipment buffs.
    return Policy == UE.EGameplayEffectDurationType.Infinite
        or Policy == UE.EGameplayEffectDurationType.HasDuration
end

-- 从有效 ASC 中移除指定句柄对应的全部效果层数，供卸装和失败回滚使用。
local function RemoveEffects(ASC, Handles)
    if IsValid(ASC) then
        for _, Handle in ipairs(Handles or {}) do
            ASC:RemoveActiveGameplayEffect(Handle, -1)
        end
    end
end

-- 以当前武器为效果来源创建 GE Spec，并规范效果等级；创建失败时返回 nil。
function WeaponEquipment:MakeEquipmentSpec(Weapon, ASC, EffectClass)
    local Library = UE.UAssassinWeaponGASLibrary
    local Context = Library.MakeWeaponEffectContext(ASC, Weapon)
    local Spec = ASC:MakeOutgoingSpec(EffectClass, math.max(1.0, NonNegative(Weapon.EffectLevel)), Context)
    if not Library.IsSpecValid(Spec) then
        return nil
    end
    return Spec
end

-- 创建基础属性 GE Spec，并通过装备数据标签写入各项 SetByCaller 数值。
function WeaponEquipment:MakeBaseStatsSpec(Weapon, ASC)
    local Spec = self:MakeEquipmentSpec(Weapon, ASC, Weapon.EquipmentStatsEffectClass)
    if not Spec then
        return nil
    end
    local Values = Weapon:MakeBaseStatsValues()
    for Name, Value in pairs(Values) do
        local Tag = UE.UAssassinWeaponGASLibrary.GetEquipmentDataTag("Assassin.Data.Equipment." .. Name)
        Spec = UE.UAbilitySystemBlueprintLibrary.AssignTagSetByCallerMagnitude(Spec, Tag, Value)
    end
    return Spec
end

-- 为有效角色创建武器栏位管理器，并加载用于校验武器实例的基类。
function WeaponEquipment.New(Owner)
    if not IsValid(Owner) then return nil end
    return setmetatable({
        Owner = Owner, Busy = false, Destroyed = false, Records = {},
        WeaponClass = UE.UClass.Load("/Script/Assassin.AssassinWeaponBase"),
    }, WeaponEquipment)
end

-- 根据武器类型选择默认栏位；无法匹配时返回 nil，袖箭须由调用方显式指定栏位。
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

-- 通知蓝图装备事件；事件异常只记录日志，不打断已完成的装备事务。
local function Notify(Weapon, Event, Owner)
    if Weapon[Event] then
        local OK, Error = xpcall(function() Weapon[Event](Weapon, Owner) end, debug.traceback)
        if not OK then print("WeaponEquipment: " .. tostring(Error)) end
    end
end

-- 在换装锁内创建装备效果；失败或异常时撤销已应用效果及模型挂接。
function WeaponEquipment:EquipWeapon(Weapon)
    if self.Destroyed or Weapon._EquipmentEnding then return false end
    if self.Records[Weapon] then return Weapon.EquippedCharacter == self.Owner end
    if Weapon._EquipmentManager and Weapon._EquipmentManager ~= self then return false end
    local ASC = UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(self.Owner)
    if not IsValid(ASC) or not SupportsEquipmentEffect(Weapon.EquipmentStatsEffectClass, true) then return false end
    local Effects = {}
    for Index = 1, Weapon.AdditionalEffects:Num() do
        local Class = Weapon.AdditionalEffects:Get(Index)
        if IsValid(Class) then
            if not SupportsEquipmentEffect(Class, false) then return false end
            Effects[#Effects + 1] = Class
        end
    end
    local Record = { ASC = ASC, Handles = {} }
    -- 保存每次应用的句柄，确保后续失败也能逐个撤销。
    local function Apply(Spec)
        if not Spec then return nil end
        local Handle = ASC:BP_ApplyGameplayEffectSpecToSelf(Spec)
        if not UE.UAssassinWeaponGASLibrary.IsEffectHandleValid(Handle) then return nil end
        Record.Handles[#Record.Handles + 1] = Handle
        return Handle
    end
    local Attached = false
    local OK, Result = xpcall(function()
        Attached = Weapon:AttachForEquipment(self.Owner)
        if not Attached then return false end
        Record.BaseStatsHandle = Apply(self:MakeBaseStatsSpec(Weapon, ASC))
        if not Record.BaseStatsHandle then return false end
        for _, Class in ipairs(Effects) do
            if not Apply(self:MakeEquipmentSpec(Weapon, ASC, Class)) then return false end
        end
        return true
    end, debug.traceback)
    if not OK or not Result then
        RemoveEffects(ASC, Record.Handles)
        if Attached or Weapon.EquippedCharacter == self.Owner then Weapon:DetachForEquipment() end
        if not OK then print("WeaponEquipment: " .. tostring(Result)) end
        return false
    end
    self.Records[Weapon] = Record
    Weapon._EquipmentManager = self
    Notify(Weapon, "OnWeaponEquipped", self.Owner)
    return true
end

-- 移除本管理器记录的效果并解除挂接；强制清理用于生命周期结束，不受攻击状态限制。
function WeaponEquipment:RemoveWeapon(Weapon, Force)
    local Record = self.Records[Weapon]
    if not Record then return true end
    if IsValid(Weapon) and Weapon.EquippedCharacter == self.Owner then
        local OK, Detached = xpcall(function() return Weapon:DetachForEquipment() end, debug.traceback)
        if not OK then print("WeaponEquipment: " .. tostring(Detached)) end
        if (not OK or not Detached) and not Force then return false end
    end
    RemoveEffects(Record.ASC, Record.Handles)
    self.Records[Weapon] = nil
    if IsValid(Weapon) and Weapon._EquipmentManager == self then Weapon._EquipmentManager = nil end
    if IsValid(Weapon) and IsValid(self.Owner) then Notify(Weapon, "OnWeaponUnequipped", self.Owner) end
    return true
end

-- 根据记录更新基础属性效果，保留已有句柄和附加效果。
function WeaponEquipment:RefreshWeaponStats(Weapon)
    return self:Change(function()
        local Record = self.Records[Weapon]
        if not IsValid(Weapon) or Weapon.EquippedCharacter ~= self.Owner or not Record
            or not IsValid(Record.ASC)
            or UE.UAbilitySystemBlueprintLibrary.GetActiveGameplayEffectStackCount(Record.BaseStatsHandle) == 0 then
            return false
        end
        local Values = UE.TMap(UE.FGameplayTag, UE.float)
        for Name, Value in pairs(Weapon:MakeBaseStatsValues()) do
            Values:Add(UE.UAssassinWeaponGASLibrary.GetEquipmentDataTag("Assassin.Data.Equipment." .. Name), Value)
        end
        Record.ASC:UpdateActiveGameplayEffectSetByCallerMagnitudes(Record.BaseStatsHandle, Values)
        return true
    end)
end

-- 将武器上的蓝图卸装入口转为栏位操作，避免绕过攻击互斥检查。
function WeaponEquipment:UnequipWeaponFromSlot(Weapon)
    for _, Slot in ipairs(self.Slots) do
        if self.Owner and self.Owner[Slot] == Weapon then return self:Unequip(Slot) end
    end
    return self:Change(function() return self:RemoveWeapon(Weapon) end)
end

-- 武器销毁时按记录清除效果和栏位，即使 Actor 已被标记为无效也能移除 GE。
function WeaponEquipment:OnWeaponEndPlay(Weapon)
    local WasBusy = self.Busy
    self.Busy = true
    self:RemoveWeapon(Weapon, true)
    if self.Owner then
        for _, Slot in ipairs(self.Slots) do
            if self.Owner[Slot] == Weapon then self.Owner[Slot] = nil end
        end
    end
    self.Busy = WasBusy
end

-- 校验角色和管理器状态并加锁执行换装操作，防止回调重入；捕获异常并确保释放锁。
function WeaponEquipment:Change(Action)
    if self.Destroyed or self.Busy or not IsValid(self.Owner) then
        return false, "角色无效、管理器已销毁或正在换装"
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

-- 将武器装备到指定或自动匹配的栏位；替换时先卸下旧武器，新武器装备失败则尝试恢复旧武器。
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
    -- 在换装锁内检查归属和攻击状态，执行武器替换及失败后的恢复。
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
            -- 管理器记录保证幂等；也支持首次装配预先配置的 Actor。
            return self:EquipWeapon(Weapon)
        end
        if Previous and IsValid(Previous) and IsValid(Previous.EquippedCharacter)
            and Previous.EquippedCharacter ~= Owner then
            return false, "原栏位引用了其他角色的武器"
        end

        local WasEquipped = Previous ~= nil and IsValid(Previous) and Previous.EquippedCharacter == Owner
        if WasEquipped and Previous and not self:RemoveWeapon(Previous) then
            return false, "原武器卸装失败"
        end
        if Previous and not IsValid(Previous) then self:RemoveWeapon(Previous, true) end
        Owner[Slot] = nil
        if self:EquipWeapon(Weapon) then
            Owner[Slot] = Weapon
            return true
        end

        if WasEquipped then
            if Previous and IsValid(Previous) and self:EquipWeapon(Previous) then
                Owner[Slot] = Previous
                return false, "新武器装配失败，已恢复原武器"
            end
            return false, "新武器装配失败，原武器恢复失败，栏位已清空"
        end
        if IsValid(Previous) then Owner[Slot] = Previous end
        return false, "新武器装配失败"
    end)
end

-- 卸下指定栏位中属于当前角色的武器并清空引用；攻击期间禁止卸下手持武器。
---@param Slot WeaponSlot
---@return boolean, string?
function WeaponEquipment:Unequip(Slot)
    if not ValidSlots[Slot] then return false, "无效的武器栏位" end
    -- 在换装锁内执行卸装；过期引用或其他角色的武器引用只清除栏位。
    return self:Change(function()
        if Slot == "HandheldWeapon" and self.Owner.AttackSystem
            and self.Owner.AttackSystem.ActiveAttack then
            return false, "攻击期间不能卸下手持武器"
        end
        local Weapon = self.Owner[Slot]
        if IsValid(Weapon) and Weapon.EquippedCharacter == self.Owner
            and not self:RemoveWeapon(Weapon) then
            return false, "武器卸装失败"
        end
        if Weapon and self.Records[Weapon] then self:RemoveWeapon(Weapon) end
        -- 只清除过期/错误引用，不卸装其他角色的装备。
        self.Owner[Slot] = nil
        return true
    end)
end

-- 手持栏位为空或引用失效时，装备角色蓝图默认武器组件生成的 ChildActor；未配置组件则跳过。
function WeaponEquipment:EquipDefaultHandheld()
    if IsValid(self.Owner.HandheldWeapon) then return true end
    local Component = self.Owner.DefaultHandheldWeapon
    if not IsValid(Component) then return true end
    -- GetChildActor 是未反射的 C++ 方法，UnLua 使用 BlueprintReadOnly 属性。
    local Weapon = Component.ChildActor
    if not IsValid(Weapon) then return false, "默认武器组件尚未生成 Actor" end
    return self:Equip(Weapon, "HandheldWeapon")
end

-- GAS 就绪后逐栏装配角色预先配置的有效武器引用，记录失败原因并返回是否全部成功。
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

-- 结束管理器生命周期，按记录移除效果，即使角色或武器已失效也不遗留 GE。
function WeaponEquipment:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    local Weapons = {}
    for Weapon in pairs(self.Records) do Weapons[#Weapons + 1] = Weapon end
    for _, Weapon in ipairs(Weapons) do self:RemoveWeapon(Weapon, true) end
    if self.Owner then
        for _, Slot in ipairs(self.Slots) do self.Owner[Slot] = nil end
    end
    self.Owner = nil
end

return WeaponEquipment
