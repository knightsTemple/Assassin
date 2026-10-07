local AttackBase = require("Combat.attack.AttackBase")
local AttackPhase = require("Combat.attack.AttackPhase").AttackPhase

-- 收剑等待的默认值和下限（秒）。
local DefaultSwordSheatheDelay = 10.0

---@class LightAttack : AttackBase
---@field AttackSystem AttackSystem
---@field Phase AttackPhase
---@field ActiveWeapon? AssassinWeaponBase
---@field SwordActionPlayRate number
---@field SwordDrawReadyTime? number
---@field SwordSheatheDelay number
local LightAttack = setmetatable({}, { __index = AttackBase })
LightAttack.__index = LightAttack

local IsValid = AttackBase.IsValid

-- 创建轻攻击模块，复用基类初始化，并设置连击、动画及收剑等待状态。
---@return LightAttack?
function LightAttack.New(AttackSystem)
    local Self = AttackBase.New(AttackSystem, LightAttack)
    if not Self then return nil end
    local State = {
        LightAttackMontages = {},
        LightAttackTimings = {},
        ActiveWeapon = nil,
        SwordDrawMontage = nil,
        SwordSheatheMontage = nil,
        SwordActionPlayRate = 1.0,
        SwordDrawReadyTime = nil,
        PendingLightAttack = false,
        CanAcceptNextAttack = false, -- 连击窗口或收招后的持剑等待期内，可立即开始下一刀
        -- 攻击收招结束后延迟收剑；期间可移动、续招或重新从第一刀开始。
        SwordSheatheDelay = DefaultSwordSheatheDelay,
        ComboIndex = 0,
    }
    for Key, Value in pairs(State) do Self[Key] = Value end
    return Self
end

-- 读取角色蓝图配置的轻攻击 GA 类，供基类初始化使用。
function LightAttack:GetAbilityClass()
    -- 在角色蓝图 Class Defaults 中配置 GameplayAbility 类引用。
    return self.Owner.LightAttackAbilityClass
end

-- 读取当前手持武器的攻击、拔剑和收剑动画及时间配置；武器或攻击动画无效时返回 false。
function LightAttack:LoadWeaponAnimations()
    ---@type AssassinWeaponBase?
    local Weapon = IsValid(self.Owner) and self.Owner.HandheldWeapon or nil
    if not Weapon or not IsValid(Weapon) or Weapon.EquippedCharacter ~= self.Owner then
        return false
    end
    local Source = Weapon.LightAttackMontages
    if not Source or Source:Num() == 0 then
        print("LightAttack: equipped weapon has no light attack montages")
        return false
    end
    local Montages, Timings = {}, {}
    for Index = 1, Source:Num() do
        local Montage = Source:Get(Index)
        if not IsValid(Montage) then return false end
        Montages[Index] = Montage
        local Config = Weapon.LightAttackTimings and Weapon.LightAttackTimings[Index]
        -- 其他武器未提供精细时机时，按完整动画播放，最后一段不续接。
        Timings[Index] = {
            PlayRate = Config and Config.PlayRate or 1.0,
            StartTime = Config and Config.StartTime or 0.0,
            ComboTime = Config and Config.ComboTime or nil,
            RecoveryTime = Config and Config.RecoveryTime or Montage:GetPlayLength(),
        }
    end
    self.ActiveWeapon = Weapon
    self.LightAttackMontages = Montages
    self.LightAttackTimings = Timings
    self.SwordDrawMontage = Weapon.DrawMontage
    self.SwordSheatheMontage = Weapon.SheatheMontage
    self.SwordActionPlayRate = math.max(0.1, Weapon.WeaponActionPlayRate or 1.0)
    self.SwordDrawReadyTime = Weapon.WeaponDrawReadyTime
    self.SwordSheatheDelay = math.max(DefaultSwordSheatheDelay, Weapon.WeaponSheatheDelay or DefaultSwordSheatheDelay)
    return true
end

-- 检查本轮攻击使用的武器是否仍有效，并且仍由当前角色持有。
function LightAttack:HasCurrentWeapon()
    local Weapon = self.ActiveWeapon
    return IsValid(self.Owner) and Weapon ~= nil and IsValid(Weapon)
        and self.Owner.HandheldWeapon == Weapon
        and Weapon.EquippedCharacter == self.Owner
end

-- 处理轻攻击输入：首次输入激活 GA，攻击中缓存或衔接连击，末段收招后允许重新起手。
function LightAttack:HandleInput()
    if self.Destroyed or not IsValid(self.ASC) or not IsValid(self.AbilityClass) then
        return false
    end

    if IsValid(self.ActiveAbility) then
        if not self:HasCurrentWeapon() then
            self.ActiveAbility:FinishLightAttack(true)
            return false
        end
        -- 收剑期间不重新激活同一个 GAS 技能，也不推进攻击段数。
        if self.Phase == AttackPhase.Sheathing then
            return false
        end
        if self.CanAcceptNextAttack and self.ComboIndex >= #self.LightAttackMontages then
            -- 最后一段结束后的等待期间可开始新一轮，不重复拔出武器。
            self.PendingLightAttack = false -- 输入缓存回答：玩家有没有提前按过下一刀？
            self.CanAcceptNextAttack = false -- 新一刀开始，重新等待允许衔接的时机
            self.ComboIndex = 1
            self.ActiveAbility:PlayCurrentAttack()
            return true
        end
        if self.ComboIndex >= #self.LightAttackMontages then
            return false
        end

        self.PendingLightAttack = true
        if self.Phase == AttackPhase.Attacking and self.CanAcceptNextAttack then
            self:ContinueLightAttack()
        end
        return true
    end

    return AttackBase.HandleInput(self)
end

-- 校验技能和武器配置，通过基类取得攻击占用后进入拔剑阶段，并初始化本轮连击。
function LightAttack:BeginAttack(Ability)
    if self.Destroyed or not IsValid(Ability) or IsValid(self.ActiveAbility) then
        return false
    end

    if not self:LoadWeaponAnimations() then
        return false
    end

    if not AttackBase.BeginAttack(self, Ability) then
        return false
    end

    self.Phase = AttackPhase.Drawing
    self.ComboIndex = 1                   -- 拔剑完成后自动播放第一段，无需再按一次
    self.PendingLightAttack = false       -- 拔剑期间的额外点击可缓存为第二段输入
    self.CanAcceptNextAttack = false     -- 连击窗口开启或收招结束后，才允许立即接下一刀
    return true
end

-- 响应当前技能的拔剑就绪回调，切换到攻击阶段并播放当前连击段。
function LightAttack:OnSwordDrawReady(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Drawing then
        return
    end
    self.Phase = AttackPhase.Attacking
    Ability:PlayCurrentAttack()
end

-- 从攻击阶段进入收剑阶段，清除连击输入并通知当前技能播放收剑动画。
function LightAttack:BeginSwordSheathe(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking then
        return
    end
    self.Phase = AttackPhase.Sheathing
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    Ability:PlaySwordSheathe()
end

-- 获取当前连击段的蒙太奇；本轮武器已失效或被替换时返回 nil。
function LightAttack:GetCurrentAttackMontage()
    if not self:HasCurrentWeapon() then return nil end
    return self.LightAttackMontages and self.LightAttackMontages[self.ComboIndex]
end

-- 获取当前连击段的播放速度、起播时间、连击窗口和收招时间配置。
function LightAttack:GetCurrentAttackTiming()
    return self.LightAttackTimings and self.LightAttackTimings[self.ComboIndex]
end

-- 响应连击窗口开启：允许衔接下一段，并立即消费已缓存的轻攻击输入。
function LightAttack:OnLightAttackComboWindow(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking
        or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    -- 动作主体完成后就允许续接，不再等待动画尾部的自然混出。
    self.CanAcceptNextAttack = true
    if self.PendingLightAttack then
        self:ContinueLightAttack()
    end
end

-- 响应收招完成：有缓存且存在下一段时继续连击，否则停止当前动作并等待输入或收剑超时。
function LightAttack:OnLightAttackRecoveryReady(Ability)
    if self.Destroyed or self.ActiveAbility ~= Ability or self.Phase ~= AttackPhase.Attacking then
        return
    end

    if self.PendingLightAttack and self.ComboIndex < #self.LightAttackMontages then
        self:ContinueLightAttack()
    else
        Ability:StopCurrentAttack()
        self.CanAcceptNextAttack = true -- 最后一段也在收招结束后允许重新起手
        Ability:WaitForComboInput(self.SwordSheatheDelay)
    end
end

-- 消费一次缓存输入，关闭当前连击窗口，推进段数并播放下一段攻击。
function LightAttack:ContinueLightAttack()
    if self.Destroyed or self.Phase ~= AttackPhase.Attacking or not IsValid(self.ActiveAbility)
        or not self.PendingLightAttack or self.ComboIndex >= #self.LightAttackMontages then
        return
    end

    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self.ComboIndex = self.ComboIndex + 1
    self.ActiveAbility:PlayCurrentAttack()
end

-- 响应当前技能结束，通过基类释放攻击占用，并清空连击状态及本轮武器动画缓存。
function LightAttack:OnAttackEnded(Ability)
    if not AttackBase.OnAttackEnded(self, Ability) then
        return
    end

    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self:ResetCombo()
    self.ActiveWeapon = nil
    self.LightAttackMontages = {}
    self.LightAttackTimings = {}
    self.SwordDrawMontage = nil
    self.SwordSheatheMontage = nil
end

-- 将连击段数归零，表示当前没有进行中的连击段。
function LightAttack:ResetCombo()
    self.ComboIndex = 0
end

-- 通过轻攻击 GA 的结束接口取消活动技能，触发其任务和攻击状态清理。
function LightAttack:CancelActiveAbility()
    if IsValid(self.ActiveAbility) then
        self.ActiveAbility:FinishLightAttack(true)
    end
end

-- 销毁模块：由基类取消活动技能并释放公共引用，再清理轻攻击专属状态；可重复调用。
function LightAttack:Destroy()
    if self.Destroyed then return end
    AttackBase.Destroy(self)
    self.PendingLightAttack = false
    self.CanAcceptNextAttack = false
    self.ActiveWeapon = nil
    self.LightAttackTimings = nil
    self.LightAttackMontages = nil
    self.SwordDrawMontage = nil
    self.SwordSheatheMontage = nil
    self.ComboIndex = 0
end

return LightAttack
