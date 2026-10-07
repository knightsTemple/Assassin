-- 统一事件定义：订阅和广播均通过 EventDefine 的字段引用，避免手写字符串拼错。
-- 字符串只在这里维护，保留可读性，便于查看日志；业务模块不要修改这张表。
-- 新增事件时在这里补充枚举项，并约定发布时机及 Payload 的内容。
-- 这里只定义事件标识，实际广播由对应业务模块接入后执行。
---@enum EventDefine
local EventDefine = {
    PlayerDead = "Player.Dead",             -- 玩家死亡
    HealthChanged = "Player.HealthChanged", -- 生命值变化
    WeaponChanged = "Equipment.SlotChanged", -- 武器栏位最终状态变化
    QuestFinished = "Quest.Finished",       -- 任务完成
}

return EventDefine
