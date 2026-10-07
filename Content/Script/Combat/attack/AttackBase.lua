local AttackPhase = require("Combat.attack.AttackPhase").AttackPhase

---@class AttackBase : AttackModule
---@field AttackSystem AttackSystem
---@field Owner any
---@field ASC any
---@field AbilityClass any
---@field AbilityHandle any
---@field ActiveAbility any
---@field Phase AttackPhase
---@field Destroyed boolean
local AttackBase = {}
AttackBase.__index = AttackBase

-- 检查对象是否存在且仍是有效的 UE 对象。
function AttackBase.IsValid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

-- 创建攻击实例，初始化公共状态并读取技能类配置；系统、角色、ASC 或配置无效时返回 nil。
-- Class 必须通过 __index 继承 AttackBase；配置和行为由子类重写。
function AttackBase.New(AttackSystem, Class)
    if not AttackSystem or AttackSystem.Destroyed
        or not AttackBase.IsValid(AttackSystem.Owner) or not AttackBase.IsValid(AttackSystem.ASC) then
        return nil
    end
    local Self = setmetatable({
        AttackSystem = AttackSystem,
        Owner = AttackSystem.Owner,
        ASC = AttackSystem.ASC,
        Phase = AttackPhase.Idle,
        Destroyed = false,
    }, Class or AttackBase)
    Self.AbilityClass = Self:GetAbilityClass()
    if not AttackBase.IsValid(Self.AbilityClass) then
        print("AttackBase: missing configured ability class")
        return nil
    end
    return Self
end

-- 提供技能类配置接口；子类需重写并返回蓝图配置的 GameplayAbility 类引用。
function AttackBase:GetAbilityClass()
    return nil -- 子类从蓝图配置读取 GameplayAbility Class Reference。
end

-- 向 ASC 授予配置的技能并保存句柄；已有该技能时直接返回成功，避免重复授予。
function AttackBase:GrantAbility()
    if self.Destroyed or not AttackBase.IsValid(self.Owner) or not AttackBase.IsValid(self.ASC)
        or not AttackBase.IsValid(self.AbilityClass) then
        return false
    end
    -- PlayerState ASC 在角色替换后可能已拥有该技能。
    if self.Owner:HasAbility(self.AbilityClass) then return true end
    local Handle = self.ASC:K2_GiveAbility(self.AbilityClass, 1)
    if not self.Owner:HasAbility(self.AbilityClass) then
        print("AttackBase: failed to grant configured ability")
        return false
    end
    self.AbilityHandle = Handle
    return true
end

-- 处理默认攻击输入：校验模块状态后请求 ASC 按配置的技能类激活 GA，并返回激活结果。
function AttackBase:HandleInput()
    if self.Destroyed or not AttackBase.IsValid(self.ASC) or not AttackBase.IsValid(self.AbilityClass) then
        return false
    end
    return self.ASC:TryActivateAbilityByClass(self.AbilityClass)
end

-- 校验技能实例并向攻击系统申请攻击占用；成功后记录活动技能，具体阶段由子类设置。
function AttackBase:BeginAttack(Ability)
    if self.Destroyed or not AttackBase.IsValid(Ability) or AttackBase.IsValid(self.ActiveAbility)
        or not self.AttackSystem:TryBeginAttack(self) then
        return false
    end
    self.ActiveAbility = Ability
    return true
end

-- 处理与活动技能匹配的结束回调，清除技能引用、恢复空闲阶段并释放攻击占用。
function AttackBase:OnAttackEnded(Ability)
    if self.ActiveAbility ~= Ability then return false end
    self.ActiveAbility = nil
    self.Phase = AttackPhase.Idle
    if self.AttackSystem then self.AttackSystem:EndAttack(self) end
    return true
end

-- 通过 GAS 接口取消有效的活动技能；子类可重写以执行专属结束流程。
function AttackBase:CancelActiveAbility()
    if AttackBase.IsValid(self.ActiveAbility) then
        self.ActiveAbility:K2_CancelAbility()
    end
end

-- 销毁攻击模块，取消活动技能、释放攻击占用并清空公共引用；可重复调用，不移除 ASC 已授予的技能。
function AttackBase:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    self:CancelActiveAbility()
    self.ActiveAbility = nil
    self.Phase = AttackPhase.Idle
    self.AttackSystem:EndAttack(self)
    self.AttackSystem = nil
    self.Owner = nil
    self.ASC = nil
    self.AbilityClass = nil
    self.AbilityHandle = nil
end

return AttackBase
