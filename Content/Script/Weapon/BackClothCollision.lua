-- Extra cloth-only collision for a weapon stored on the character's back.
local M = {}
local function Valid(Object)
    return Object ~= nil and UE.UKismetSystemLibrary.IsValid(Object)
end

function M.Clear(Weapon)
    local State = Weapon._BackClothCollision
    if not State then return end
    for _, Target in ipairs(State.Targets) do
        if Valid(Target) and Valid(State.Source) and Valid(State.Asset) then
            Target:RemoveClothCollisionSource(State.Source, State.Asset)
        end
    end
    Weapon._BackClothCollision = nil
    print("BackClothCollision: removed", #State.Targets)
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
return M
