-- 背部武器的布料碰撞表现；订阅角色事件，不参与装备事务及攻击逻辑。
local EventDefine = require("Core.EventSubscribe.EventDefine")
---@class BackClothCollision
---@field Owner BP_AssassinGirl_C?
---@field Events EventBus?
---@field Tracked table<AssassinWeaponBase, table> 缓存碰撞记录，用于无效 Actor 的清理
---@field RefreshTime number
---@field Destroyed? boolean
local M = {}
M.__index = M
local function Valid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

-- 独立保存碰撞源信息，使武器 Actor 已无效时仍能移除注册过的碰撞源。
local function ClearState(State)
    if not State then return end
    for _, Target in ipairs(State.Targets) do
        if Valid(Target) and Valid(State.Source) and Valid(State.Asset) then
            Target:RemoveClothCollisionSource(State.Source, State.Asset)
        end
    end
    print("BackClothCollision: removed", #State.Targets)
end

function M.Clear(Weapon)
    ClearState(Weapon._BackClothCollision)
    Weapon._BackClothCollision = nil
end

function M.Update(Weapon)
    local Character = Weapon.EquippedCharacter
    local Asset = Weapon.BackClothPhysicsAsset
    if not Valid(Character) or not Valid(Asset) or Weapon._WeaponDrawn then
        M.Clear(Weapon)
        return
    end
    local Source = Character.Mesh
    if not Valid(Source) then M.Clear(Weapon); return end
    local Targets, Seen = {}, {}
    local function Collect(Actor)
        local Components = Actor:K2_GetComponentsByClass(UE.USkeletalMeshComponent)
        for Index = 1, Components:Num() do
            local Component = Components:Get(Index)
            if Component ~= Source and not Seen[Component] then
                Seen[Component] = true
                Targets[#Targets + 1] = Component
            end
        end
    end
    Collect(Character)
    local Children = UE.TArray(UE.AActor)
    Character:GetAllChildActors(Children, true)
    for Index = 1, Children:Num() do Collect(Children:Get(Index)) end
    local State = Weapon._BackClothCollision
    if State and (State.Source ~= Source or State.Asset ~= Asset) then
        M.Clear(Weapon)
        State = nil
    end
    if not State then
        State = { Source = Source, Asset = Asset, Targets = {} }
        Weapon._BackClothCollision = State
    end
    -- Reconcile visual replacements without registering duplicates every tick.
    for Index = #State.Targets, 1, -1 do
        local Target = State.Targets[Index]
        if not Seen[Target] then
            if Valid(Target) then Target:RemoveClothCollisionSource(Source, Asset) end
            table.remove(State.Targets, Index)
        end
    end
    for _, Target in ipairs(Targets) do
        local Found = false
        for _, Existing in ipairs(State.Targets) do
            if Existing == Target then Found = true; break end
        end
        if not Found then
            Target:AddClothCollisionSource(Source, Asset)
            State.Targets[#State.Targets + 1] = Target
            print("BackClothCollision: added", Target:GetName())
        end
    end
end

-- 角色组装模块时先建立监听；支持晚创建时主动读取当前装备。
---@param Owner BP_AssassinGirl_C
---@param Events EventBus
---@return BackClothCollision
function M.New(Owner, Events)
    local Self = setmetatable({ Owner = Owner, Events = Events, Tracked = {}, RefreshTime = 0 }, M)
    Events:Subscribe(EventDefine.WeaponChanged, Self, Self.OnWeaponChanged)
    Events:Subscribe(EventDefine.WeaponDrawnChanged, Self, Self.OnWeaponDrawnChanged)
    Self:Refresh()
    return Self
end

-- 仅清理本实例持有的碰撞记录，不能误清理其他角色武器的表现。
function M:Forget(Weapon)
    local Entry = self.Tracked[Weapon]
    if not Entry then return end
    ClearState(Entry.State)
    if Valid(Weapon) and Weapon._BackClothCollision == Entry.State then
        Weapon._BackClothCollision = nil
    end
    self.Tracked[Weapon] = nil
end

function M:RefreshWeapon(Weapon)
    if not Valid(Weapon) or Weapon.EquippedCharacter ~= self.Owner then
        if Weapon then self:Forget(Weapon) end
        return
    end
    M.Update(Weapon)
    self.Tracked[Weapon] = { State = Weapon._BackClothCollision }
end

---@param Payload WeaponChangedPayload
function M:OnWeaponChanged(Payload)
    if self.Destroyed or Payload.Character ~= self.Owner then return end
    if Payload.OldWeapon then self:Forget(Payload.OldWeapon) end
    if Payload.NewWeapon then self:RefreshWeapon(Payload.NewWeapon) end
end

---@param Payload WeaponDrawnChangedPayload
function M:OnWeaponDrawnChanged(Payload)
    if self.Destroyed or Payload.Character ~= self.Owner then return end
    self:RefreshWeapon(Payload.Weapon)
end

-- 可视 ChildActor 可能延迟生成或替换，单靠换装通知覆盖不到，保留低频补偿刷新。
function M:Refresh()
    if self.Destroyed or not Valid(self.Owner) then return end
    local Present = {}
    for _, Slot in ipairs({ "HandheldWeapon", "ShieldWeapon", "BowWeapon", "HiddenBladeWeapon" }) do
        local Weapon = self.Owner[Slot]
        if Valid(Weapon) and Weapon.EquippedCharacter == self.Owner then Present[Weapon] = true end
    end
    local Removed = {}
    for Weapon in pairs(self.Tracked) do
        if not Present[Weapon] then Removed[#Removed + 1] = Weapon end
    end
    for _, Weapon in ipairs(Removed) do self:Forget(Weapon) end
    for Weapon in pairs(Present) do self:RefreshWeapon(Weapon) end
end

function M:Tick(DeltaSeconds)
    if self.Destroyed then return end
    self.RefreshTime = self.RefreshTime + DeltaSeconds
    if self.RefreshTime < 0.25 then return end
    self.RefreshTime = 0
    self:Refresh()
end

-- 先退订，再移除所有碰撞源；不依赖普通卸装事件完成角色退出清理。
function M:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    self.Events:UnsubscribeOwner(self)
    local Weapons = {}
    for Weapon in pairs(self.Tracked) do Weapons[#Weapons + 1] = Weapon end
    for _, Weapon in ipairs(Weapons) do self:Forget(Weapon) end
    self.Owner = nil
    self.Events = nil
end
return M
