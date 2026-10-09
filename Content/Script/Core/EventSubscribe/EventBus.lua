-- 纯 Lua 事件总线：每个角色或业务作用域单独创建，不依赖 UE，也不共享全局实例。
-- 使用方式：require("Core.EventSubscribe.EventBus").New()
-- 事件定义：local EventDefine = require("Core.EventSubscribe.EventDefine")
-- 订阅：Events:Subscribe(EventDefine.WeaponChanged, Listener, Listener.OnSlotChanged)
-- 广播：Events:Emit(EventDefine.WeaponChanged, Payload)
-- 回调统一接收 (Owner, Payload)，等价于 Owner:OnSlotChanged(Payload)。
-- Payload 由监听器按只读数据使用；事件不保存历史，也不负责网络同步。
local EventDefine = require("Core.EventSubscribe.EventDefine")

-- 从集中定义的枚举生成合法事件集合，订阅和广播不接受未定义的事件。
-- 枚举底层仍是字符串值；运行时校验值是否合法，无法区分同值字面量的来源。
local ValidEvents = {}
for _, Event in pairs(EventDefine) do
    ValidEvents[Event] = true
end

---@class EventSubscription

---@class EventListenerRecord
---@field Event EventDefine
---@field Handle EventSubscription
---@field Owner table|userdata|nil
---@field Callback function|nil
---@field Active boolean
---@field Once boolean

---@class EventBus
---@field private Listeners table<EventDefine, EventListenerRecord[]>
---@field private Subscriptions table<EventSubscription, EventListenerRecord>
---@field private DispatchDepth integer
---@field Destroyed boolean
local EventBus = {}
EventBus.__index = EventBus

-- 防止事件互相触发造成无限递归；不同事件之间的嵌套也计入深度。
local MaxDispatchDepth = 32

---@return EventBus
function EventBus.New()
    return setmetatable({
        Listeners = {},
        Subscriptions = {},
        DispatchDepth = 0,
        Destroyed = false,
    }, EventBus)
end

-- 注册时检查调用契约；同一回调可重复注册，每次返回独立句柄。
-- 总线销毁后不再接受订阅，返回 nil；Owner 须在自身销毁时主动退订。
---@param Event EventDefine
---@param Owner table|userdata
---@param Callback fun(Owner: any, Payload: any)
---@return EventSubscription?
function EventBus:Subscribe(Event, Owner, Callback)
    if self.Destroyed then return nil end
    assert(ValidEvents[Event] == true, "事件必须是 EventDefine 中已定义的枚举值")
    assert(type(Owner) == "table" or type(Owner) == "userdata", "订阅者必须是对象")
    assert(type(Callback) == "function", "事件回调必须是函数")

    local Handle = {}
    local Record = {
        Event = Event, Handle = Handle, Owner = Owner, Callback = Callback,
        Active = true, Once = false,
    }
    local List = self.Listeners[Event]
    if not List then
        List = {}
        self.Listeners[Event] = List
    end
    List[#List + 1] = Record
    self.Subscriptions[Handle] = Record
    return Handle
end

-- 在调用前移除一次性订阅，保证回调嵌套发送同一事件时不会再次触发。
---@param Event EventDefine
---@param Owner table|userdata
---@param Callback fun(Owner: any, Payload: any)
---@return EventSubscription?
function EventBus:Once(Event, Owner, Callback)
    local Handle = self:Subscribe(Event, Owner, Callback)
    if Handle then self.Subscriptions[Handle].Once = true end
    return Handle
end

-- 句柄只属于创建它的总线；重复退订或传入其他总线的句柄返回 false。
-- 立即释放对象和回调引用，外部保留旧句柄不会继续持有订阅者。
---@param Handle EventSubscription
---@return boolean
function EventBus:Unsubscribe(Handle)
    local Record = self.Subscriptions[Handle]
    if not Record then return false end
    self.Subscriptions[Handle] = nil
    Record.Active = false
    Record.Owner = nil
    Record.Callback = nil
    local List = self.Listeners[Record.Event]
    for Index, Item in ipairs(List) do
        if Item == Record then
            table.remove(List, Index)
            break
        end
    end
    if #List == 0 then self.Listeners[Record.Event] = nil end
    return true
end

-- 按对象身份清理其全部订阅；先收集句柄，再修改原表。
---@param Owner table|userdata
---@return integer Count 实际取消的订阅数量
function EventBus:UnsubscribeOwner(Owner)
    local Handles = {}
    for Handle, Record in pairs(self.Subscriptions) do
        if rawequal(Record.Owner, Owner) then Handles[#Handles + 1] = Handle end
    end
    for _, Handle in ipairs(Handles) do self:Unsubscribe(Handle) end
    return #Handles
end

-- 同步按订阅顺序分发：本轮新增不参与本轮，本轮取消的未执行回调直接跳过。
-- 嵌套 Emit 是独立的一轮，会读取当时的订阅状态；回调不得 yield 或修改 Payload。
-- 监听异常仅记录日志，不阻止其余监听器，也不能撤销发布者已经完成的业务操作。
-- 返回值表示本次分发是否完成，不代表所有监听器成功；无监听器也算完成。
---@param Event EventDefine
---@param Payload any
---@return boolean Success
---@return string? Reason
function EventBus:Emit(Event, Payload)
    if self.Destroyed then return false, "事件总线已销毁" end
    assert(ValidEvents[Event] == true, "事件必须是 EventDefine 中已定义的枚举值")
    if self.DispatchDepth >= MaxDispatchDepth then
        print("EventBus: 嵌套分发超过深度限制，已拒绝事件 " .. Event)
        return false, "事件嵌套超过深度限制"
    end
    local List = self.Listeners[Event]
    if not List then return true end
    local Snapshot = {}
    for Index, Record in ipairs(List) do Snapshot[Index] = Record end

    self.DispatchDepth = self.DispatchDepth + 1 --防止事件互相触发造成无限递归；不同事件之间的嵌套也计入深度。
    -- 外层保护确保意外错误也能恢复分发深度。
    local OK, Error = xpcall(function()
        for _, Record in ipairs(Snapshot) do
            if self.Destroyed then break end
            if Record.Active then
                local Owner, Callback = Record.Owner, Record.Callback
                if Record.Once then self:Unsubscribe(Record.Handle) end
                local Called, CallbackError = xpcall(function()
                    Callback(Owner, Payload)
                end, debug.traceback)
                if not Called then
                    print("EventBus: 事件 " .. Event .. "，订阅 " .. tostring(Record.Handle)
                        .. " 回调异常：" .. tostring(CallbackError))
                end
            end
        end
    end, debug.traceback)
    self.DispatchDepth = self.DispatchDepth - 1
    if not OK then return false, tostring(Error) end
    return true
end

-- 关闭总线并释放所有引用；分发中调用会停止剩余监听器，可重复调用。
function EventBus:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    for _, Record in pairs(self.Subscriptions) do
        Record.Active = false
        Record.Owner = nil
        Record.Callback = nil
    end
    self.Listeners = {}
    self.Subscriptions = {}
end

return EventBus
