-- 攻击流程与蒙太奇共用的阶段枚举；字符串值也用于动画任务名称。
---@enum AttackPhase
local AttackPhase = {
    Idle = "Idle",           -- 空闲
    Drawing = "Drawing",     -- 拔剑
    Attacking = "Attacking", -- 攻击（包含收招后的持剑等待）
    Sheathing = "Sheathing", -- 收剑
}

-- 攻击类型使用数值枚举，作为攻击模块的注册键。
---@enum AttackType
local AttackType = {
    Light = 1,         -- 轻攻击
    Heavy = 2,         -- 重攻击
    ChargedLight = 3,  -- 蓄力轻攻击
    ChargedHeavy = 4,  -- 蓄力重攻击
    Shooting = 5,      -- 射击
    Assassination = 6, -- 刺杀攻击
}

return {
    AttackPhase = AttackPhase,
    AttackType = AttackType,
}
