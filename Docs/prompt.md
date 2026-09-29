请继续修改当前 Assassin Unreal Engine 项目。

当前项目已经完成：

- GAS 接入
- UnLua 接入
- AAssassinCharacter / AbilitySystemComponent
- UAssassinAttributeSet
- GE_DefaultAttributes
- GameplayTag 基础体系
- BP_AssassinGirl.lua 与角色绑定
- OnGASInitialized() 已经可以在 Lua 中收到
- Lua 可以正常获取 ASC 和 AttributeSet

当前项目是单机游戏，不考虑网络同步。

现在开始正式建立角色的攻击模块。

本次不要实现 GameplayAbility、攻击动画、命中检测、伤害计算。

本次只完成“AttackSystem Lua 模块 + BP_AssassinGirl 持有 AttackSystem”这一层架构。

==================================================
一、创建攻击模块
==================================================

创建：

Content/Script/GAS/Combat/AttackSystem.lua

AttackSystem 是纯 Lua 逻辑模块，不是 UObject，也不是 UActorComponent。

它的定位类似以前 C++ 项目中的 CombatComponent / AttackComponent，但不需要 UE Component 能力。

它负责以后统一管理：

- 轻攻击请求
- 重攻击请求
- 连击状态
- 连击段数
- 攻击输入缓存
- 根据武器选择攻击
- 通过 ASC 激活对应 GameplayAbility

目前只建立结构，不实现完整攻击逻辑。

==================================================
二、AttackSystem 基础结构
==================================================

请使用清晰的 Lua module / object 写法。

结构可以类似：

local AttackSystem = {}
AttackSystem.__index = AttackSystem

function AttackSystem.New(Owner)
    ...
end

function AttackSystem:LightAttack()
    ...
end

function AttackSystem:HeavyAttack()
    ...
end

function AttackSystem:ResetCombo()
    ...
end

function AttackSystem:Destroy()
    ...
end

return AttackSystem

具体实现可以根据项目现有 Lua 编码风格调整。

==================================================
三、AttackSystem 持有的数据
==================================================

第一版至少包含：

Owner
ASC
ComboIndex

语义：

Owner
= 当前 BP_AssassinGirl UObject

ASC
= 当前角色的 UAbilitySystemComponent

ComboIndex
= 当前轻攻击连击段数

初始：

ComboIndex = 0

ASC 使用 UE 官方接口获取：

UE.UAbilitySystemBlueprintLibrary.GetAbilitySystemComponent(Owner)

不要直接访问：

Owner.AbilitySystemComponent

如果 ASC 获取失败，应该安全处理，不要 Crash。

==================================================
四、LightAttack
==================================================

本次 LightAttack 只建立正式函数入口。

例如：

function AttackSystem:LightAttack()
    ...
end

暂时不要：

- 播放 Montage
- 做 Trace
- 计算伤害
- 修改 Health
- 创建 GameplayEffect
- 手动修改 GameplayTag
- 实现连击跳转
- 激活不存在的 GameplayAbility

可以保留清晰的 TODO 注释，说明下一步这里会通过 ASC 激活：

Assassin.Ability.Attack.Light

但本次不要伪造 GA，也不要创建测试 GA。

LightAttack 当前只需要保证结构正确，并能够作为角色以后统一的轻攻击入口。

==================================================
五、HeavyAttack
==================================================

同样建立：

AttackSystem:HeavyAttack()

暂时只作为正式接口。

未来对应：

Assassin.Ability.Attack.Heavy

本次不实现实际 Heavy Attack Gameplay。

==================================================
六、Combo
==================================================

第一版 AttackSystem 内保留：

ComboIndex

以及：

ResetCombo()

ResetCombo() 将 ComboIndex 恢复为 0。

暂时不要实现：

- Combo Window
- Timer
- Montage Section
- 输入缓存
- 连击自动递增
- 连击超时

后续在真实轻攻击实现时再补。

==================================================
七、在 BP_AssassinGirl.lua 中创建 AttackSystem
==================================================

修改：

Content/Script/Character/BP_AssassinGirl.lua

在文件顶部：

require("Combat.AttackSystem")

不要把攻击逻辑直接写回 BP_AssassinGirl.lua。

由于 AttackSystem 依赖 ASC，因此在：

M:OnGASInitialized()

中创建 AttackSystem。

目标结构类似：

self.AttackSystem = AttackSystem.New(self)

不要在 ReceiveBeginPlay 中重复创建。

保证只创建一次。

如果 OnGASInitialized 因意外被重复调用，需要避免生成多个 AttackSystem 实例。

==================================================
八、角色 Lua 的职责
==================================================

BP_AssassinGirl.lua 以后应该保持轻量。

角色层只负责类似：

self.AttackSystem:LightAttack()
self.AttackSystem:HeavyAttack()

不要让 BP_AssassinGirl.lua 自己管理：

ComboIndex
攻击 Montage
攻击伤害
攻击 Trace

这些以后分别交给 Combat / Ability 等模块。

==================================================
九、生命周期
==================================================

如果 BP_AssassinGirl.lua 当前已经实现 UnLua 的销毁生命周期函数，则在合适的位置调用：

self.AttackSystem:Destroy()

并清理：

self.AttackSystem = nil

如果当前文件没有合适的 Lua 销毁生命周期，而且不确定 UnLua 当前版本对应的生命周期函数，不要猜函数名。

这种情况下先保留 AttackSystem:Destroy() 接口即可，并报告后续应该在哪里调用。

==================================================
十、目录结构
==================================================

本次完成后希望至少形成：

Content/Script/

Character/
└── BP_AssassinGirl.lua

Combat/
└── AttackSystem.lua

后续预计扩展：

Combat/
├── AttackSystem.lua
├── HitDetector.lua
└── DamageCalculator.lua

Ability/
├── GA_LightAttack.lua
└── GA_HeavyAttack.lua

但本次不要创建后面这些空文件。

==================================================
十一、不要修改
==================================================

本次不要修改：

- C++
- AttributeSet
- GE_DefaultAttributes
- GameplayTag 配置
- Blueprint
- Input Mapping
- GameplayAbility
- GameplayEffect
- Montage
- 动画
- Hit Detection
- Damage System
- WeaponSystem
- 网络逻辑

只修改 Lua AttackSystem 架构。

==================================================
十二、完成后检查
==================================================

完成后：

1. 确认 AttackSystem.lua 可以被 require。
2. 确认 OnGASInitialized 中成功创建 self.AttackSystem。
3. 确认 AttackSystem 能拿到 Owner。
4. 确认 AttackSystem 能拿到有效 ASC。
5. 确认 ComboIndex 初始值为 0。
6. 确认 BP_AssassinGirl.lua 没有被塞入攻击具体逻辑。
7. 确认 PIE 启动没有 Lua 报错。

最后汇报：

- 修改/创建了哪些文件
- AttackSystem 当前有哪些公开接口
- AttackSystem 当前保存哪些状态
- BP_AssassinGirl.lua 如何持有 AttackSystem
- 是否存在需要后续处理的生命周期问题

完成后停止。

不要继续实现 GA_LightAttack。