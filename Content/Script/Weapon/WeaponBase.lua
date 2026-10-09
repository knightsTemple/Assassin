-- 与 C++ 反射接口对应，供 Lua Language Server 识别 UE 注入的成员。
---@class AssassinWeaponStats
---@field AttackPower number
---@field AssassinationPower number
---@field CritDamageBonus number
---@field CritChance number
---@field Weight number

---@class AssassinEquipmentEffectArray
---@field Num fun(self: AssassinEquipmentEffectArray): integer
---@field Get fun(self: AssassinEquipmentEffectArray, Index: integer): any

---@class AssassinShieldWeaponBase : AssassinWeaponBase
---@field MaxShieldHealth number
---@field ShieldHealth number
---@field OnShieldHealthChanged fun(self: AssassinShieldWeaponBase, OldHealth: number, NewHealth: number)

---@class AssassinWeaponBase
---@field IsA fun(self: AssassinWeaponBase, Class: any): boolean
---@field BaseStats AssassinWeaponStats
---@field WeaponLevel integer
---@field StatGrowthCurves table<string, any>
---@field EffectLevel number
---@field EquipmentStatsEffectClass any
---@field AdditionalEffects AssassinEquipmentEffectArray
---@field EquipSocketName any 角色 SkeletalMesh 上的装备插槽名
---@field LightAttackMontages any 轻攻击蒙太奇数组，按连招顺序排列
---@field HeavyAttackMontages any 重攻击蒙太奇数组，暂未使用
---@field LightAttackTimings? table 每段轻攻击的可选时机配置
---@field DrawnSocketName any
---@field WeaponDrawAttachTime? number
---@field WeaponSheatheAttachTime? number
---@field DrawMontage any
---@field SheatheMontage any
---@field WeaponActionPlayRate? number
---@field WeaponDrawReadyTime? number
---@field WeaponSheatheDelay? number
---@field EquippedCharacter any
---@field _EquipmentManager? WeaponEquipment 装备生命周期由该管理器持有
---@field Overridden { ReceiveEndPlay: fun(self: AssassinWeaponBase, EndPlayReason: any) }
---@field IsShieldWeapon fun(self: AssassinWeaponBase): boolean
---@field GetMaxHealthBonus fun(self: AssassinWeaponBase): number
---@field GetName fun(self: AssassinWeaponBase): string
---@field K2_DetachFromActor fun(self: AssassinWeaponBase, LocationRule: any, RotationRule: any, ScaleRule: any)
---@field K2_AttachToComponent fun(self: AssassinWeaponBase, Parent: any, SocketName: any, LocationRule: any, RotationRule: any, ScaleRule: any, WeldSimulatedBodies: boolean): boolean
---@field SetOwner fun(self: AssassinWeaponBase, NewOwner: any)
---@field OnWeaponEquipped fun(self: AssassinWeaponBase, Character: any)
---@field OnWeaponUnequipped fun(self: AssassinWeaponBase, PreviousCharacter: any)
local M = UnLua.Class()
local EventDefine = require("Core.EventSubscribe.EventDefine")

-- 检查对象是否存在且仍是有效的 UE 对象。
local function IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

-- 将数值限制为非负有限数；非数字、NaN 和无穷值统一按零处理。
local function NonNegative(Value)
    if type(Value) ~= "number" or Value ~= Value or Value == math.huge or Value == -math.huge then
        return 0.0
    end
    return math.max(0.0, Value)
end


local StatNames = { "AttackPower", "AssassinationPower", "CritDamageBonus", "CritChance", "Weight" } --攻击力，刺杀攻击力，暴击伤害加成，暴击率，重量（加成）

-- 将等级向下取整并限制在 1～100 范围内，无效输入按等级 1 处理。
local function NormalizeLevel(Level)
    return math.max(1, math.min(100, math.floor(NonNegative(Level))))
end

-- 计算指定等级的武器属性：优先读取成长曲线，否则使用基础值，并限制暴击率不超过 1。
function M:GetStatsAtLevel(Level)
    local Stats = UE.FAssassinWeaponStats()
    Level = NormalizeLevel(Level)
    for _, Name in ipairs(StatNames) do
        local Curve = self.StatGrowthCurves[Name]
        local Value = IsValid(Curve) and Curve:GetFloatValue(Level) or self.BaseStats[Name]
        Stats[Name] = NonNegative(Value)
    end
    Stats.CritChance = math.min(1.0, Stats.CritChance)
    return Stats
end

-- 根据当前武器等级计算并返回武器属性。
function M:GetCurrentStats()
    return self:GetStatsAtLevel(self.WeaponLevel)
end

-- 将当前武器属性和最大生命值加成整理为数值表，供装备 GE 的 SetByCaller 参数使用。
function M:MakeBaseStatsValues()
    local Stats = self:GetCurrentStats()
    local Values = {}
    for _, Name in ipairs(StatNames) do
        Values[Name] = Stats[Name]
    end
    Values.MaxHealth = NonNegative(self:GetMaxHealthBonus())
    return Values
end

-- 通知装备管理器刷新角色加成；未装备时无需更新 GE。
function M:RefreshEquipmentStats()
    if self._ChangingEquipment then return false end
    local Equipment = self._EquipmentManager
    if Equipment then return Equipment:RefreshWeaponStats(self) end
    return not IsValid(self.EquippedCharacter)
end

-- 设置合法等级并刷新装备属性；刷新失败时恢复原等级。
function M:SetWeaponLevel(NewLevel)
    if self._ChangingEquipment or (self._EquipmentManager and self._EquipmentManager.Busy) then
        return false
    end
    local OldLevel = self.WeaponLevel
    self.WeaponLevel = NormalizeLevel(NewLevel)
    if not self:RefreshEquipmentStats() then
        self.WeaponLevel = OldLevel
        return false
    end
    return true
end

-- 初始化武器状态并规范等级；盾牌额外初始化为满耐久。
function M:ReceiveBeginPlay()
    self.WeaponLevel = NormalizeLevel(self.WeaponLevel)
    self._ChangingEquipment = false
    self._AttachedByEquipment = false
    if self:IsShieldWeapon() then
        ---@cast self AssassinShieldWeaponBase
        self.ShieldHealth = NonNegative(self.MaxShieldHealth)
    end
end

-- 保留蓝图装备入口，统一交由角色装备管理器处理栏位和效果。
function M:EquipToCharacter(Character)
    if not IsValid(Character) or not Character.WeaponEquipment then return false end
    for _, Slot in ipairs(Character.WeaponEquipment.Slots) do
        if Character[Slot] == self then return Character.WeaponEquipment:Equip(self, Slot) end
    end
    return Character.WeaponEquipment:Equip(self)
end

-- 保留蓝图卸装入口，统一经过装备管理器的状态检查。
function M:UnequipFromCharacter()
    local Equipment = self._EquipmentManager
    if Equipment then return Equipment:UnequipWeaponFromSlot(self) end
    return not IsValid(self.EquippedCharacter)
end

-- 仅供装备管理器调用：挂接模型并设置武器归属，不操作 GE。
function M:AttachForEquipment(Character)
    if self._ChangingEquipment or not IsValid(Character) then return false end
    if IsValid(self.EquippedCharacter) then return self.EquippedCharacter == Character end
    local Socket = tostring(self.EquipSocketName)
    local AttachMesh = Socket ~= "" and Socket ~= "None"
    if AttachMesh then
        if not IsValid(Character.Mesh) or not Character.Mesh:DoesSocketExist(self.EquipSocketName) then
            return false
        end
        if not self:K2_AttachToComponent(Character.Mesh, self.EquipSocketName,
            UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.SnapToTarget,
            UE.EAttachmentRule.KeepRelative, false) then return false end
    end
    self._AttachedByEquipment = AttachMesh
    self.EquippedCharacter = Character
    self:SetOwner(Character)
    self._WeaponDrawn = false
    return true
end

-- 仅供装备管理器调用：解除挂接归属，不操作 GE；表现模块在事务完成后接收通知。
function M:DetachForEquipment()
    if self._ChangingEquipment then return false end
    if self._AttachedByEquipment then
        self:K2_DetachFromActor(UE.EDetachmentRule.KeepWorld, UE.EDetachmentRule.KeepWorld, UE.EDetachmentRule.KeepWorld)
    end
    self._AttachedByEquipment = false
    self._WeaponDrawn = false
    self.EquippedCharacter = nil
    self:SetOwner(nil)
    return true
end

-- 切换插槽成功后发布拔出状态变化，武器不再直接依赖布料等表现模块。
function M:SetWeaponDrawn(Drawn)
    local HandSocket = self.DrawnSocketName
    if HandSocket == nil or tostring(HandSocket) == "" or tostring(HandSocket) == "None" then
        return true -- 未配置双插槽的武器保持原有行为。
    end
    local Character = self.EquippedCharacter
    if not IsValid(Character) or not IsValid(Character.Mesh) then
        return false
    end
    local Socket = Drawn and HandSocket or self.EquipSocketName
    if Socket == nil or tostring(Socket) == "" or tostring(Socket) == "None"
        or not Character.Mesh:DoesSocketExist(Socket) then
        return false
    end
    if not self:K2_AttachToComponent(Character.Mesh, Socket,
        UE.EAttachmentRule.SnapToTarget, UE.EAttachmentRule.SnapToTarget,
        UE.EAttachmentRule.KeepRelative, false) then
        return false
    end
    local WasDrawn = self._WeaponDrawn == true
    self._AttachedByEquipment = true
    self._WeaponDrawn = Drawn
    if WasDrawn ~= Drawn and Character.Events and not Character._EndingGameplay then
        Character.Events:Emit(EventDefine.WeaponDrawnChanged, {
            Character = Character, Weapon = self, Drawn = Drawn,
        })
    end
    return true
end

-- 扣除盾牌耐久，发生变化时触发通知，并返回实际扣除量。
function M:ApplyShieldDamage(Damage)
    if not self:IsShieldWeapon() then
        return 0.0
    end
    ---@cast self AssassinShieldWeaponBase
    local OldHealth = math.min(NonNegative(self.MaxShieldHealth), NonNegative(self.ShieldHealth))
    local NewHealth = math.max(0.0, OldHealth - NonNegative(Damage))
    self.ShieldHealth = NewHealth
    if OldHealth ~= NewHealth then
        self:OnShieldHealthChanged(OldHealth, NewHealth)
    end
    return OldHealth - NewHealth
end

-- 恢复盾牌耐久且不超过上限，发生变化时触发通知，并返回实际恢复量。
function M:RepairShield(Amount)
    if not self:IsShieldWeapon() then
        return 0.0
    end
    ---@cast self AssassinShieldWeaponBase
    local Maximum = NonNegative(self.MaxShieldHealth)
    local OldHealth = math.min(Maximum, NonNegative(self.ShieldHealth))
    local NewHealth = math.min(Maximum, OldHealth + NonNegative(Amount))
    self.ShieldHealth = NewHealth
    if OldHealth ~= NewHealth then
        self:OnShieldHealthChanged(OldHealth, NewHealth)
    end
    return NewHealth - OldHealth
end

-- 通知装备管理器清理本武器的效果和栏位，再调用父类 EndPlay。
function M:ReceiveEndPlay(EndPlayReason)
    self._EquipmentEnding = true
    if self._EquipmentManager then
        self._EquipmentManager:OnWeaponEndPlay(self)
    end
    self.Overridden.ReceiveEndPlay(self, EndPlayReason)
end

return M
