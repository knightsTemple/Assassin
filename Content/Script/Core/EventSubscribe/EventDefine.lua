-- 统一事件定义：订阅和广播均通过 EventDefine 的字段引用，避免手写字符串拼错。
-- 字符串只在这里维护，保留可读性，便于查看日志；业务模块不要修改这张表。
-- 新增事件时在这里补充枚举项，并约定发布时机及 Payload 的内容。
-- 武器栏位与拔出状态事件已接入业务；死亡、生命值及任务事件暂为预留定义。
-- 以下约定发布者的数据结构和发送时机，枚举本身不会执行任何业务。
-- 所有 Payload 按只读使用；数值代表发送当时的快照，对象字段仍是引用。
-- 引用 UE 对象的监听者在调用其方法前须检查有效性，尤其是已销毁的旧武器。
-- 类型注解只供编辑器提示，不会在运行时校验字段，也不会自动复制数据。

---@alias EventObject table|userdata

-- 玩家死亡通知的数据；仅在存活状态确实变为死亡后发送。
---@class PlayerDeadPayload
---@field Player EventObject 死亡的玩家角色
---@field Instigator? EventObject 导致死亡的责任对象；环境伤害等情况可以为空

-- 生命值变化通知的数据；OldHealth 和 NewHealth 使用相同单位，不是百分比。
---@class HealthChangedPayload
---@field Player EventObject 生命值所属的玩家角色
---@field OldHealth number 本次更新前的生命值
---@field NewHealth number 本次更新后的最终生命值
---@field MaxHealth number 本次更新后的最大生命值

---@alias WeaponChangedReason
---| 'Equip' # 装备或替换成功，包含初始装备
---| 'Unequip' # 主动卸装完成
---| 'WeaponDestroyed' # 武器销毁，所属栏位已清理
---| 'RollbackFailed' # 换装失败且旧武器恢复失败，栏位已清空

-- 栏位最终状态变化的数据；空栏位用 nil 表示，不使用无效的占位对象。
---@class WeaponChangedPayload
---@field Character BP_AssassinGirl_C 装备所属角色
---@field Slot WeaponSlot 发生变化的栏位
---@field OldWeapon? AssassinWeaponBase 变化前的武器；首次装备时为空，销毁时可能已失效
---@field NewWeapon? AssassinWeaponBase 最终装备的武器；卸装或恢复失败时为空
---@field Reason WeaponChangedReason 本次栏位变化的原因

-- 武器已成功切换至手持或收纳插槽，不表示整段拔出/收起动画已经结束。
---@class WeaponDrawnChangedPayload
---@field Character BP_AssassinGirl_C 武器所属角色
---@field Weapon AssassinWeaponBase 完成插槽切换的武器
---@field Drawn boolean true 为已拔出，false 为已收起

-- 任务完成通知的数据；奖励是否已领取不由这个事件表示。
---@class QuestFinishedPayload
---@field Player EventObject 完成任务的玩家角色
---@field QuestId string 任务配置中的唯一标识，不使用可变的显示名称

-- 通用接口接受的载荷类型集合；具体事件应使用下方指定的那一种类型。
-- 联合类型不会自动约束 Event 与 Payload 的一一对应，调用处应标注明确的载荷类型。
---@alias EventPayload PlayerDeadPayload|HealthChangedPayload|WeaponChangedPayload|WeaponDrawnChangedPayload|QuestFinishedPayload

---@enum EventDefine
local EventDefine = {
    -- 参数：PlayerDeadPayload；发布者：角色死亡状态的管理模块。
    -- 时机：死亡状态写入完成后，每次存活到死亡的转换只发送一次；复活后可再次发送。
    -- 不在每次受伤或 Actor EndPlay 时发送；若同次处理还发布生命值变化，应先发 HealthChanged。
    PlayerDead = "Player.Dead",

    -- 参数：HealthChangedPayload；发布者：角色属性模块（统一转接 GAS 属性变化）。
    -- 时机：生命值更新完成后，OldHealth 与 NewHealth 不同时发送，不发布尚未生效的伤害请求。
    -- 仅最大生命值变化不触发本事件；晚创建的 UI 主动查询当前属性，不依赖历史通知。
    HealthChanged = "Player.HealthChanged",

    -- 参数：WeaponChangedPayload；发布者：WeaponEquipment。
    -- 时机：整个装备事务完成，栏位、归属及 GE 记录已达到最终状态后发送。
    -- 成功替换只发一次；失败且恢复原状不发；恢复失败导致栏位清空则发 RollbackFailed。
    -- 同一武器重复装备不发；初始空栏位变为已装备要发，初始引用已配置但首次实际装配也要发。
    -- 武器销毁须先清理栏位再发；角色整体 EndPlay 清理不发布普通换装通知。
    -- 发送期间保留换装重入保护，监听者读取最终结果，不在回调中再次换装。
    WeaponChanged = "Equipment.SlotChanged",

    -- 参数：WeaponDrawnChangedPayload；发布者：WeaponBase.SetWeaponDrawn。
    -- 时机：插槽挂接成功、拔出状态更新且确实发生变化后；失败或重复状态不发。
    -- 初次装备和卸装由 WeaponChanged 表示；角色整体 EndPlay 不发此表现通知。
    WeaponDrawnChanged = "Weapon.DrawnChanged",

    -- 参数：QuestFinishedPayload；发布者：任务状态管理模块。
    -- 时机：任务状态首次从未完成变为已完成并写入后发送，不代表存档落盘或奖励到账。
    -- 重复检测、加载已有完成状态不发；可重复任务重置后再次完成可以发送。
    QuestFinished = "Quest.Finished",
}

return EventDefine
