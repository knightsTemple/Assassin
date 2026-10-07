-- 在 Content/Script 目录使用 Lua 5.4 运行，无需 UE 环境。
local EventBus = require("Core.EventSubscribe.EventBus")
local EventDefine = require("Core.EventSubscribe.EventDefine")
local Owner = {}

-- 有序分发、对象参数、载荷引用、重复订阅和句柄归属。
local Bus, Other = EventBus.New(), EventBus.New()
local Calls, Payload = {}, { Value = 10 }
local function Callback(Self, Data)
    assert(Self == Owner and Data == Payload)
    Calls[#Calls + 1] = "A"
end
local First = Bus:Subscribe(EventDefine.WeaponChanged, Owner, Callback)
local Second = Bus:Subscribe(EventDefine.WeaponChanged, Owner, Callback)
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() Calls[#Calls + 1] = "B" end)
assert(not Other:Unsubscribe(First))
assert(Other:Emit(EventDefine.WeaponChanged, Payload) and #Calls == 0)
assert(Bus:Emit(EventDefine.WeaponChanged, Payload) and table.concat(Calls) == "AAB")
assert(Bus:Unsubscribe(First) and not Bus:Unsubscribe(First))
assert(Bus:Unsubscribe(Second))
assert(Bus:UnsubscribeOwner(Owner) == 1)
assert(Bus:UnsubscribeOwner(Owner) == 0)
assert(Bus:Emit(EventDefine.WeaponChanged, Payload) and #Calls == 3)

-- 分发期间退订未执行监听器，并新增监听器：新增项只参加后续分发。
Bus = EventBus.New()
Calls = {}
local Removed, Added
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function()
    Calls[#Calls + 1] = "A"
    Bus:Unsubscribe(Removed)
    if not Added then
        Added = Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() Calls[#Calls + 1] = "C" end)
    end
end)
Removed = Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() error("已退订回调不应执行") end)
assert(Bus:Emit(EventDefine.WeaponChanged) and table.concat(Calls) == "A")
assert(Bus:Emit(EventDefine.WeaponChanged) and table.concat(Calls) == "AAC")

-- 一次性监听在执行前退订；嵌套分发不能再次触发该监听器。
Bus = EventBus.New()
local OnceCalls, RegularCalls = 0, 0
Bus:Once(EventDefine.WeaponChanged, Owner, function()
    OnceCalls = OnceCalls + 1
    assert(Bus:Emit(EventDefine.WeaponChanged))
end)
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() RegularCalls = RegularCalls + 1 end)
assert(Bus:Emit(EventDefine.WeaponChanged))
assert(OnceCalls == 1 and RegularCalls == 2)

-- 单个监听器异常不影响后续监听器；一次性监听抛错后仍已移除。
Bus = EventBus.New()
local ErrorCalls, AfterError = 0, 0
Bus:Once(EventDefine.WeaponChanged, Owner, function()
    ErrorCalls = ErrorCalls + 1
    error("测试预期异常")
end)
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() AfterError = AfterError + 1 end)
assert(Bus:Emit(EventDefine.WeaponChanged) and Bus:Emit(EventDefine.WeaponChanged))
assert(ErrorCalls == 1 and AfterError == 2)

-- 同一对象跨事件批量退订，不影响其他对象；可在分发中调用。
Bus = EventBus.New()
local OtherOwner, Remaining = {}, 0
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() assert(Bus:UnsubscribeOwner(Owner) == 3) end)
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() error("批量退订后不应执行") end)
Bus:Subscribe(EventDefine.HealthChanged, Owner, function() error("跨事件退订后不应执行") end)
Bus:Subscribe(EventDefine.WeaponChanged, OtherOwner, function() Remaining = Remaining + 1 end)
assert(Bus:Emit(EventDefine.WeaponChanged) and Bus:Emit(EventDefine.HealthChanged) and Remaining == 1)

-- 嵌套深度保护拒绝无限递归；退出后普通分发仍能正常执行。
Bus = EventBus.New()
local DepthCalls, Rejected = 0, false
local Recursive = Bus:Subscribe(EventDefine.WeaponChanged, Owner, function()
    DepthCalls = DepthCalls + 1
    local OK, Reason = Bus:Emit(EventDefine.WeaponChanged)
    if not OK then Rejected = type(Reason) == "string" end
end)
assert(Bus:Emit(EventDefine.WeaponChanged) and Rejected and DepthCalls == 32)
assert(Bus:Unsubscribe(Recursive))
Bus:Once(EventDefine.WeaponChanged, Owner, function() DepthCalls = DepthCalls + 1 end)
assert(Bus:Emit(EventDefine.WeaponChanged) and DepthCalls == 33)

-- 分发中销毁立即停止后续监听，旧句柄失效；重复销毁安全。
Bus = EventBus.New()
local DestroyCalls = 0
Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() Bus:Destroy() end)
local Stale = Bus:Subscribe(EventDefine.WeaponChanged, Owner, function() DestroyCalls = DestroyCalls + 1 end)
assert(Bus:Emit(EventDefine.WeaponChanged) and DestroyCalls == 0)
Bus:Destroy()
assert(not Bus:Emit(EventDefine.WeaponChanged))
assert(not Bus:Unsubscribe(Stale))
assert(Bus:UnsubscribeOwner(Owner) == 0)
assert(Bus:Subscribe(EventDefine.WeaponChanged, Owner, Callback) == nil)
assert(Bus:Once(EventDefine.WeaponChanged, Owner, Callback) == nil)

-- 无效注册参数及时暴露，避免悄悄创建无法匹配的事件。
Bus = EventBus.New()
-- 故意传入非法事件，验证枚举成员校验，而不只是字符串类型校验。
---@diagnostic disable: param-type-mismatch
assert(not pcall(function() Bus:Subscribe("", Owner, Callback) end))
assert(not pcall(function() Bus:Subscribe("Unknown.Event", Owner, Callback) end))
assert(not pcall(function() Bus:Once("Unknown.Event", Owner, Callback) end))
assert(not pcall(function() Bus:Emit("Unknown.Event") end))
assert(not pcall(function() Bus:Subscribe(nil, Owner, Callback) end))
assert(not pcall(function() Bus:Subscribe(EventDefine.WeaponChanged, nil, Callback) end))
assert(not pcall(function() Bus:Subscribe(EventDefine.WeaponChanged, Owner, nil) end))
assert(not pcall(function() Bus:Emit(123) end))
---@diagnostic enable: param-type-mismatch
print("PASS: EventBus 订阅、退订、隔离、重入、异常、深度限制及销毁")
