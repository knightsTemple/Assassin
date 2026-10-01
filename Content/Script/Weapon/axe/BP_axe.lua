---@class BP_axe_C : AssassinWeaponBase
---@field AxeCollision any
local M = UnLua.Class("Weapon.WeaponBase")
local WeaponBase = require("Weapon.WeaponBase")

-- 时间点使用动画原始时间（秒）；实际等待时长会除以播放速度。
-- ComboTime：有缓存输入时接下一段；RecoveryTime：没有输入时结束收招。
-- 第四段保留腾空、落地和短暂缓冲，避免在空中切回站姿。
local LightAttackTimings = {
    { PlayRate = 1.20, StartTime = 0.06, ComboTime = 0.72, RecoveryTime = 0.95 }, -- 下劈
    { PlayRate = 1.20, StartTime = 0.14, ComboTime = 0.80, RecoveryTime = 1.00 }, -- 上撩
    { PlayRate = 1.20, StartTime = 0.06, ComboTime = 0.85, RecoveryTime = 1.05 }, -- 踢击
    { PlayRate = 1.20, StartTime = 0.08, RecoveryTime = 1.45 },                -- 升龙斩
}

-- 动画资源由武器蓝图配置；Lua 只初始化连招时机，不覆盖资源选择。
function M:InitializeAttackTimings()
    self.LightAttackTimings = LightAttackTimings
    self.WeaponActionPlayRate = 1.0
    self.WeaponDrawReadyTime = 1.25
    self.WeaponSheatheDelay = 2.0
    -- 原始动画时间：右手碰柄后切手持，收回背部后再放手。
    self.WeaponDrawAttachTime = 0.35
    self.WeaponSheatheAttachTime = 1.1333333333
    -- 新字段未编译时也可作为 Lua 成员使用；蓝图显式配置优先。
    if self.DrawnSocketName == nil or tostring(self.DrawnSocketName) == "None"
        or tostring(self.DrawnSocketName) == "" then
        self.DrawnSocketName = "Axe_Hand_R"
    end
    return true
end

function M:ReceiveBeginPlay()
    WeaponBase.ReceiveBeginPlay(self)
    self.BackClothPhysicsAsset = UE.UObject.Load("/Game/AssassinGirl/Weapon/Axe/PA_Axe_BackCloth.PA_Axe_BackCloth")
    self:InitializeAttackTimings()
end

return M
