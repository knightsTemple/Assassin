-- 在 Content/Script 目录运行：lua Tests/AttackSystem.spec.lua
-- 用 UE/GAS 替身验证模块协作；动画和引擎任务仍需在 UE 中验证。
local AbilityClass = {}
UE = {
    EAttachmentRule = { SnapToTarget = 0, KeepRelative = 1 },
    UKismetSystemLibrary = { IsValid = function(Object) return Object ~= nil end },
    UAbilitySystemBlueprintLibrary = {
        GetAbilitySystemComponent = function(Owner) return Owner.ASC end,
    },
    UClass = { Load = function(Path)
        assert(type(Path) == "string" and Path ~= "")
        return AbilityClass
    end },
    UObject = { Load = function(Path) return { Path = Path, GetPlayLength = function() return 2.0 end } end },
}
UnLua = { Class = function(SuperModule) return {} end }

local AttackSystem = require("Combat.attack.AttackSystem")
local AttackEnums = require("Combat.attack.AttackPhase")
local AttackPhase = AttackEnums.AttackPhase
local AttackType = AttackEnums.AttackType
local AbilityMethods = require("Abilities.GA_LightAttack")

local AxeMethods = require("Weapon.axe.BP_axe")
local function NewArray()
    local Array = {}
    function Array:Clear() for i = #self, 1, -1 do self[i] = nil end end
    function Array:Add(Value) self[#self + 1] = Value end
    function Array:Num() return #self end
    function Array:Get(Index) return self[Index] end
    return Array
end

local function NewConfiguredAxe(Owner)
    local ConfiguredAxe = { LightAttackMontages = NewArray(), EquippedCharacter = Owner }
    ConfiguredAxe.EquipSocketName = "Axe_Back"
    function ConfiguredAxe:K2_AttachToComponent(_, Socket)
        self.AttachedSocket = Socket
        return true
    end
    -- 模拟蓝图默认值，并验证 Lua 初始化不会覆盖手动选择。
    for Index = 1, 4 do
        ConfiguredAxe.LightAttackMontages:Add(UE.UObject.Load("blueprint_axe_attack_" .. Index))
    end
    ConfiguredAxe.DrawMontage = UE.UObject.Load("blueprint_axe_draw")
    ConfiguredAxe.SheatheMontage = UE.UObject.Load("blueprint_axe_sheathe")
    local First = ConfiguredAxe.LightAttackMontages:Get(1)
    local Draw, Sheathe = ConfiguredAxe.DrawMontage, ConfiguredAxe.SheatheMontage
    assert(AxeMethods.InitializeAttackTimings(ConfiguredAxe))
    assert(ConfiguredAxe.LightAttackMontages:Num() == 4 and ConfiguredAxe.LightAttackMontages:Get(1) == First)
    assert(ConfiguredAxe.DrawMontage == Draw and ConfiguredAxe.SheatheMontage == Sheathe)
    return ConfiguredAxe
end

local function NewFixture(CommitSucceeds)
    local Owner = { Granted = false, LightAttackAbilityClass = AbilityClass, Mesh = { DoesSocketExist = function() return true end } }
    local ASC = { GrantCount = 0 }
    Owner.ASC = ASC
    Owner.HandheldWeapon = NewConfiguredAxe(Owner)
    function Owner:HasAbility() return self.Granted end
    function ASC:K2_GiveAbility(Class)
        assert(Class == Owner.LightAttackAbilityClass, "Grant must use blueprint configuration")
        self.GrantCount = self.GrantCount + 1
        Owner.Granted = true
        return 1
    end
    local System = assert(AttackSystem.New(Owner))
    Owner.AttackSystem = System
    local Light = assert(System:GetAttack(AttackType.Light))
    local Ability = setmetatable({ Played = 0 }, { __index = AbilityMethods })
    function Ability:GetAvatarActorFromActorInfo() return Owner end
    function Ability:K2_CommitAbility() return CommitSucceeds ~= false end
    function Ability:PlaySwordDraw() self.Drew = true end
    function Ability:PlayCurrentAttack() self.Played = self.Played + 1 end
    function Ability:StopCurrentAttack() self.Stopped = true end
    function Ability:WaitForComboInput(Duration) self.WaitDuration = Duration end
    function Ability:PlaySwordSheathe() self.Sheathed = true end
    function Ability:K2_CancelAbility() self:K2_OnEndAbility(true) end
    function Ability:K2_EndAbility() self:K2_OnEndAbility(false) end
    function ASC:TryActivateAbilityByClass(Class)
        assert(Class == Owner.LightAttackAbilityClass, "Activation must use blueprint configuration")
        Ability:K2_ActivateAbility()
        return not Ability.Ending
    end
    return System, Light, Ability, ASC
end

local System, Light, Ability, ASC = NewFixture()
local AttackBase = require("Combat.attack.AttackBase")
local LightAttack = require("Combat.attack.LightAttack")
assert(Light.GrantAbility == AttackBase.GrantAbility)
assert(Light.AbilityClass == System.Owner.LightAttackAbilityClass)
assert(LightAttack.New({ Owner = {}, ASC = {} }) == nil,
    "Missing blueprint configuration must fail without a hardcoded fallback")
local OtherClass = {}
local Configured = assert(LightAttack.New({ Owner = { LightAttackAbilityClass = OtherClass }, ASC = {} }))
assert(Configured.AbilityClass == OtherClass, "Custom blueprint class must be preserved")
local SeenTypes = {}
local TypeCount = 0
for _, Type in pairs(AttackType) do
    assert(type(Type) == "number" and not SeenTypes[Type])
    SeenTypes[Type] = true
    TypeCount = TypeCount + 1
    if Type ~= AttackType.Light then
        assert(not System:RequestAttack(Type), "Unregistered attack types must fail cleanly")
    end
end
assert(TypeCount == 6)
assert(System:GrantAbilities() and System:GrantAbilities())
assert(ASC.GrantCount == 1, "Repeated initialization must not grant twice")
assert(not System:HeavyAttack(), "Unimplemented attacks must fail cleanly")
assert(System:LightAttack())
assert(System.ActiveAttack == Light and Ability.LightAttack == Light)
assert(Light.Phase == AttackPhase.Drawing and Ability.Drew)
assert(System:LightAttack() and Light.PendingLightAttack)
Light:OnSwordDrawReady(Ability)
assert(Light.ComboIndex == 1 and Ability.Played == 1)
Light:OnSwordDrawReady(Ability)
assert(Ability.Played == 1, "Duplicate draw callback must not replay")
Light:OnLightAttackComboWindow(Ability)
assert(Light.ComboIndex == 2 and Ability.Played == 2)
assert(not Light.PendingLightAttack and not Light.CanAcceptNextAttack)
Light:OnLightAttackRecoveryReady(Ability)
assert(Light.CanAcceptNextAttack and Ability.WaitDuration == Light.SwordSheatheDelay)
assert(System:LightAttack() and Light.ComboIndex == 3)
Light:OnLightAttackComboWindow(Ability)
assert(System:LightAttack() and Light.ComboIndex == 4)
Light:OnLightAttackComboWindow(Ability)
assert(not Light.CanAcceptNextAttack and not System:LightAttack())
Light:OnLightAttackRecoveryReady(Ability)
assert(System:LightAttack() and Light.ComboIndex == 1)
assert(not Light.CanAcceptNextAttack, "Restart must close the input window")
Light:OnLightAttackRecoveryReady(Ability)
Ability:OnComboInputExpired()
assert(Light.Phase == AttackPhase.Sheathing and Ability.Sheathed)
assert(not System:LightAttack())
Ability:FinishLightAttack(false)
assert(System.ActiveAttack == nil and Light.ActiveAbility == nil)
assert(Light.Phase == AttackPhase.Idle and Light.ComboIndex == 0)

-- 管理器支持另一种攻击模块，并对输入和直接技能激活都实施互斥。
local Heavy = { Inputs = 0 }
function Heavy:GrantAbility() return true end
function Heavy:HandleInput()
    self.Inputs = self.Inputs + 1
    return System:TryBeginAttack(self)
end
function Heavy:Destroy() self.Destroyed = true end
System.Attacks[AttackType.Heavy] = Heavy
assert(System:HeavyAttack() and System.ActiveAttack == Heavy)
assert(not System:LightAttack())
Ability:K2_ActivateAbility()
assert(Ability.Ending and System.ActiveAttack == Heavy)
assert(Light.ActiveAbility == nil, "Rejected activation must not claim Light")
System:EndAttack(Light)
assert(System.ActiveAttack == Heavy, "Wrong module must not release active attack")
System:EndAttack(Heavy)
assert(System:LightAttack())
assert(not System:HeavyAttack() and Heavy.Inputs == 1)
System:Destroy()
assert(Heavy.Destroyed and Light.Destroyed and Ability.Ending)
assert(System.ActiveAttack == nil and Light.ActiveAbility == nil)
assert(Ability.LightAttack == nil and not System:LightAttack())
assert(System:GetAttack(AttackType.Light) == nil and not System:GrantAbilities())
System:Destroy()
Light:Destroy()

-- 消耗提交失败和外部取消都必须释放管理器中的活动攻击。
local FailedSystem, FailedLight, FailedAbility = NewFixture(false)
assert(not FailedSystem:LightAttack())
assert(FailedAbility.Ending and FailedSystem.ActiveAttack == nil)
assert(FailedLight.ActiveAbility == nil and FailedLight.Phase == AttackPhase.Idle)
local CancelSystem, CancelLight, CancelAbility = NewFixture()
assert(CancelSystem:LightAttack())
CancelAbility:K2_OnEndAbility(true)
assert(CancelSystem.ActiveAttack == nil and CancelLight.ActiveAbility == nil)
assert(CancelSystem:LightAttack(), "Cancellation must permit a new attack")
CancelSystem:Destroy()
FailedSystem:Destroy()

print("PASS: grant, GAS callbacks, combos, restart, sheath, exclusion, failure and cleanup")

-- 当前武器决定动画、连段长度和时机，而不是通用模块的剑配置。
local RouteSystem, RouteLight, RouteAbility = NewFixture()
local RouteOwner = RouteSystem.Owner
RouteOwner.HandheldWeapon = nil
assert(not RouteSystem:LightAttack(), "Unarmed must not play sword attacks")
local Empty = { EquippedCharacter = RouteOwner, LightAttackMontages = NewArray() }
RouteOwner.HandheldWeapon = Empty
assert(not RouteSystem:LightAttack(), "Empty weapon combo must fail cleanly")

local AxeMontage1 = UE.UObject.Load("axe_attack_1")
local AxeMontage2 = UE.UObject.Load("axe_attack_2")
local AxeMontages = NewArray()
AxeMontages:Add(AxeMontage1)
AxeMontages:Add(AxeMontage2)
local Axe = { EquippedCharacter = RouteOwner, LightAttackMontages = AxeMontages }
RouteOwner.HandheldWeapon = Axe
RouteAbility.PlaySwordDraw = AbilityMethods.PlaySwordDraw
RouteAbility.PlaySwordSheathe = AbilityMethods.PlaySwordSheathe
assert(RouteSystem:LightAttack())
assert(RouteLight.Phase == AttackPhase.Attacking and RouteAbility.Played == 1,
    "Missing draw montage must enter the first attack")
assert(RouteLight:GetCurrentAttackMontage() == AxeMontage1)
assert(RouteLight:GetCurrentAttackTiming().RecoveryTime == 2.0)
assert(RouteLight:GetCurrentAttackTiming().PlayRate == 1.0)
assert(RouteSystem:LightAttack())
RouteLight:OnLightAttackComboWindow(RouteAbility)
assert(RouteLight.ComboIndex == 2 and RouteLight:GetCurrentAttackMontage() == AxeMontage2)
assert(not RouteSystem:LightAttack(), "Two-section weapon must not play configured axe sections 3 and 4")
RouteLight:OnLightAttackRecoveryReady(RouteAbility)
RouteAbility:OnComboInputExpired()
assert(RouteAbility.Ending and RouteSystem.ActiveAttack == nil,
    "Missing sheath montage must end the ability normally")

local ConfiguredAxe = NewConfiguredAxe(RouteOwner)
RouteOwner.HandheldWeapon = ConfiguredAxe
RouteAbility.PlaySwordDraw = function(self) self.Drew = true end
assert(RouteSystem:LightAttack())
assert(#RouteLight.LightAttackMontages == 4)
assert(RouteLight:GetCurrentAttackMontage() == ConfiguredAxe.LightAttackMontages:Get(1))
assert(RouteLight:GetCurrentAttackTiming().StartTime == 0.06)
assert(RouteLight.SwordDrawMontage == ConfiguredAxe.DrawMontage)
assert(RouteLight.SwordDrawReadyTime == 1.25)
-- 外部直接修改栏位时，不允许继续播放上一把武器的动画。
RouteOwner.HandheldWeapon = Axe
assert(RouteLight:GetCurrentAttackMontage() == nil)
assert(not RouteSystem:LightAttack() and RouteAbility.Ending)
assert(RouteSystem.ActiveAttack == nil)
RouteSystem:Destroy()
print("PASS: current weapon routing, variable combo length, axe timings, optional draw/sheath, missing weapon")

-- 挂接只改插槽，延时按动画播放速度换算；取消攻击恢复背部。
local AttachSystem, AttachLight, AttachAbility = NewFixture()
assert(AttachSystem:LightAttack())
local EquippedAxe = AttachSystem.Owner.HandheldWeapon
local CreatedTask
UE.UAbilityTask_WaitDelay = { WaitDelay = function(_, Duration)
    local Task = { Duration = Duration, OnFinish = {
        Add = function(self, Object, Callback)
            assert(Object ~= nil and type(Callback) == "function")
            self.Object, self.Callback = Object, Callback
        end,
        Remove = function(self, Object, Callback)
            if self.Object == Object and self.Callback == Callback then
                self.Object, self.Callback = nil, nil
            end
        end,
    } }
    function Task:ReadyForActivation() self.Ready = true end
    function Task:EndTask() self.Ended = true end
    CreatedTask = Task
    return Task
end }
local ActionMontage = { RateScale = 1.0, GetPlayLength = function() return 2.0 end }
AttachLight.SwordActionPlayRate = 2.0
AttachAbility:StartWeaponAttachTask(AttackPhase.Drawing, ActionMontage)
assert(math.abs(CreatedTask.Duration - 0.175) < 0.0001)
AttachAbility:OnWeaponAttachMoment()
assert(EquippedAxe.AttachedSocket == "Axe_Hand_R" and CreatedTask.Ended)
AttachAbility:StartWeaponAttachTask(AttackPhase.Sheathing, ActionMontage)
assert(math.abs(CreatedTask.Duration - 1.1333333333 / 2) < 0.0001)
AttachAbility:OnWeaponAttachMoment()
assert(EquippedAxe.AttachedSocket == "Axe_Back")
assert(AttachAbility:ApplyWeaponAttachment(true))
AttachAbility:FinishLightAttack(true)
assert(EquippedAxe.AttachedSocket == "Axe_Back")
assert(AttachSystem.ActiveAttack == nil)
AttachSystem:Destroy()
print("PASS: draw/sheath timed attachment, playback-rate conversion and cancellation cleanup")
