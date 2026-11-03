-- 蓝图完成扫掠；这里仅处理攻击有效性、自身过滤、窗口去重和业务事件。
local EventDefine = require("Core.EventSubscribe.EventDefine")

---@class AttackTraceComponent
---@field WindowOpen boolean
---@field Window any
---@field WindowSerial integer
---@field Animation any
---@field Source any
---@field SourceWeapon any
---@field LastHit any
---@field ClearWindow fun(self: AttackTraceComponent)

---@class AttackHitReceiver
local M = {}
M.__index = M

local function Valid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

---@return AttackHitReceiver
function M.New(Owner)
    return setmetatable({ Owner = Owner }, M)
end

function M:Clear()
    self.Component, self.Serial, self.HitActors = nil, nil, nil
end

---@param Component AttackTraceComponent?
function M:Receive(Component)
    local Owner = self.Owner
    if not Valid(Owner) or Owner._EndingGameplay or not Valid(Component) or not Component.WindowOpen then
        return
    end

    local Attack = Owner.AttackSystem and Owner.AttackSystem.ActiveAttack
    if not Attack or not Valid(Attack.ActiveAbility) or Attack.ActiveAbility.Ending then
        return
    end

    -- 由具体攻击模块校验动画归属；没有提供当前动画接口的模块不接受命中。
    if not Attack.GetCurrentAttackMontage or Attack:GetCurrentAttackMontage() ~= Component.Animation then
        return
    end

    local Hit = Component.LastHit
    local Target = select(10, UE.UGameplayStatics.BreakHitResult(Hit))
    if not Valid(Target) or Target == Owner or Target == Component.SourceWeapon then
        return
    end

    -- 排除角色持有的武器插槽，直接比较避免在热路径中临时分配 table
    if Target == Owner.HandheldWeapon or Target == Owner.ShieldWeapon
        or Target == Owner.BowWeapon or Target == Owner.HiddenBladeWeapon then
        return
    end

    if self.Component ~= Component or self.Serial ~= Component.WindowSerial then
        self.Component, self.Serial, self.HitActors = Component, Component.WindowSerial, {}
    end

    if self.HitActors[Target] then
        return
    end
    self.HitActors[Target] = true

    if Owner.Events then
        Owner.Events:Emit(EventDefine.AttackHit, {
            Character = Owner,
            Target = Target,
            Weapon = Component.SourceWeapon,
            Source = tostring(Component.Source),
            ComboIndex = Attack.ComboIndex,
            Hit = Hit,
            Window = Component.Window,
            WindowSerial = Component.WindowSerial,
        })
    end
end

return M
