UE = {
    UKismetSystemLibrary = { IsValid = function(O) return O ~= nil and not O.Invalid end },
    UGameplayStatics = { BreakHitResult = function(H)
        return false, false, 0, 0, {}, {}, {}, {}, nil, H.Target
    end },
}
local Receiver = require("Combat.attack.AttackHitReceiver")
local Animation, Target, Weapon = {}, {}, {}
local Events = {}
local Owner = { HandheldWeapon = Weapon, Events = { Emit = function(_, _, P) Events[#Events+1] = P end } }
local Active = { ActiveAbility = {}, ComboIndex = 2 }
function Active:GetCurrentAttackMontage() return Animation end
Owner.AttackSystem = { ActiveAttack = Active }
local C = { WindowOpen = true, WindowSerial = 1, Window = {}, Animation = Animation, Source = 'MainWeapon', SourceWeapon = Weapon, LastHit = {Target = Target} }
local R = Receiver.New(Owner)
R:Receive(C); R:Receive(C); assert(#Events == 1)
C.WindowSerial = 2; C.Source = 'foot_l'; R:Receive(C)
assert(#Events == 2 and Events[2].Source == 'foot_l')
C.LastHit.Target = Owner; R:Receive(C); C.LastHit.Target = Weapon; R:Receive(C); assert(#Events == 2)
C.LastHit.Target = {}; C.WindowOpen = false; R:Receive(C); assert(#Events == 2)
C.WindowOpen = true; C.Animation = {}; R:Receive(C); assert(#Events == 2)
C.Animation = Animation; Active.ActiveAbility.Ending = true; R:Receive(C); assert(#Events == 2)
-- 更换为其他攻击模块，不依赖 LightAttack 类或固定连击段数。
local Heavy = { ActiveAbility = {}, GetCurrentAttackMontage = function() return Animation end }
Owner.AttackSystem.ActiveAttack = Heavy; C.WindowSerial = 3; R:Receive(C)
assert(#Events == 3 and Events[3].ComboIndex == nil)
Owner._EndingGameplay = true; C.WindowSerial = 4; R:Receive(C); assert(#Events == 3)
R:Clear(); assert(R.HitActors == nil)
print('AttackHitReceiver: PASS')
