local function Array(Items)
    Items = Items or {}
    function Items:Num() return #self end
    function Items:Get(Index) return self[Index] end
    return Items
end
UE = { UKismetSystemLibrary = { IsValid = function(O) return O ~= nil and not O.Invalid end },
    USkeletalMeshComponent = {}, AActor = {}, TArray = function() return Array() end }
local Collision = require("Weapon.BackClothCollision")
local Added, Removed = 0, 0
local function Target()
    return {
        GetName = function() return "Cape" end,
        AddClothCollisionSource = function() Added = Added + 1 end,
        RemoveClothCollisionSource = function() Removed = Removed + 1 end,
    }
end
local Cape = Target()
local Visual = { K2_GetComponentsByClass = function() return Array({Cape}) end }
local Character = { Mesh = {} }
function Character:K2_GetComponentsByClass() return Array({self.Mesh}) end
function Character:GetAllChildActors(Out, Recursive) assert(Recursive); Out[1] = Visual end
local Weapon = { EquippedCharacter = Character, BackClothPhysicsAsset = {} }
Collision.Update(Weapon); assert(Added == 1)
Collision.Update(Weapon); assert(Added == 1, "duplicate registration")
Weapon._WeaponDrawn = true
Collision.Update(Weapon); assert(Removed == 1 and not Weapon._BackClothCollision)
Collision.Update(Weapon); assert(Removed == 1)
Weapon._WeaponDrawn = false
Collision.Update(Weapon); assert(Added == 2)
Cape = Target()
Collision.Update(Weapon); assert(Added == 3 and Removed == 2, "visual replacement")
Weapon.EquippedCharacter = nil
Collision.Update(Weapon); assert(Removed == 3 and not Weapon._BackClothCollision)
Collision.Clear(Weapon); assert(Removed == 3)
Collision.Update({}); assert(Added == 3, "unconfigured weapon")
print("PASS: registration, idempotence, draw/sheath, visual replacement, unequip and cleanup")
