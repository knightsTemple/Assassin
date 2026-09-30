# Assassin GameplayTag 中文对照表

本文档对应 `Config/DefaultGameplayTags.ini` 中显式定义的 46 个 `Assassin.*` GameplayTag。Tag 名称是项目中的实际标识；中文用于说明含义，不替代 Tag 名称。

## State：角色持续状态

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.State.Dead` | 死亡状态 |
| `Assassin.State.Attacking` | 正在攻击 |
| `Assassin.State.Assassinating` | 正在刺杀 |
| `Assassin.State.Stunned` | 眩晕状态 |
| `Assassin.State.Invincible` | 无敌状态 |
| `Assassin.State.Stealth` | 潜行状态 |
| `Assassin.State.Combat` | 战斗状态 |
| `Assassin.State.Airborne` | 空中／滞空状态 |

## Ability：能力分类

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.Ability.Attack` | 攻击类能力 |
| `Assassin.Ability.Attack.Light` | 轻攻击 |
| `Assassin.Ability.Attack.Heavy` | 重攻击 |
| `Assassin.Ability.Assassinate` | 刺杀能力 |
| `Assassin.Ability.Dodge` | 闪避能力 |
| `Assassin.Ability.Skill` | 特殊技能类能力 |
| `Assassin.Ability.Skill.SmokeBomb` | 烟雾弹技能 |
| `Assassin.Ability.Skill.ThrowKnife` | 飞刀技能 |

## Event：瞬时事件

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.Event.Hit` | 命中事件 |
| `Assassin.Event.Damage` | 伤害事件 |
| `Assassin.Event.Kill` | 击杀事件 |
| `Assassin.Event.Attack.Hit` | 攻击命中事件 |
| `Assassin.Event.Attack.Parried` | 攻击被招架事件 |
| `Assassin.Event.Assassination.Success` | 刺杀成功事件 |
| `Assassin.Event.Assassination.Failed` | 刺杀失败事件 |

## Effect：增益、减益与控制效果分类

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.Effect.Buff.AttackUp` | 攻击力提升增益效果 |
| `Assassin.Effect.Buff.SpeedUp` | 移动速度提升增益效果 |
| `Assassin.Effect.Buff.Invincible` | 无敌增益效果 |
| `Assassin.Effect.Debuff.Poison` | 中毒减益效果 |
| `Assassin.Effect.Debuff.Bleed` | 流血减益效果 |
| `Assassin.Effect.Debuff.Slow` | 减速减益效果 |
| `Assassin.Effect.CC.Stun` | 眩晕控制效果 |
| `Assassin.Effect.CC.Knockdown` | 击倒控制效果 |

## Damage：伤害类型

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.Damage.Physical` | 物理伤害 |
| `Assassin.Damage.Assassination` | 刺杀伤害 |
| `Assassin.Damage.Projectile` | 投射物伤害 |
| `Assassin.Damage.Fire` | 火焰伤害 |
| `Assassin.Damage.Poison` | 毒素伤害 |
| `Assassin.Damage.Bleed` | 流血伤害 |

## Weapon：武器类型

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.Weapon.Melee.Sword` | 近战武器：剑 |
| `Assassin.Weapon.Melee.Dagger` | 近战武器：匕首 |
| `Assassin.Weapon.Melee.HiddenBlade` | 近战武器：袖剑 |
| `Assassin.Weapon.Ranged.Bow` | 远程武器：弓 |
| `Assassin.Weapon.Ranged.ThrowingKnife` | 远程武器：飞刀 |

## Data：数值数据标识

这些 Tag 可用于 GAS 的 SetByCaller 等数值传递场景。

| GameplayTag | 中文含义 |
| --- | --- |
| `Assassin.Data.Damage` | 伤害数值 |
| `Assassin.Data.Heal` | 治疗数值 |
| `Assassin.Data.CritDamage` | 暴击伤害数值 |
| `Assassin.Data.AssassinationDamage` | 刺杀伤害数值 |
