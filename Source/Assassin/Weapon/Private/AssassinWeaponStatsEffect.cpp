#include "../Public/AssassinWeaponStatsEffect.h"

#include "../../AssassinCharacter/Public/AssassinAttributeSet.h"
#include "NativeGameplayTags.h"

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Equipment_AttackPower, "Assassin.Data.Equipment.AttackPower");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Equipment_AssassinationPower, "Assassin.Data.Equipment.AssassinationPower");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Equipment_CritDamageBonus, "Assassin.Data.Equipment.CritDamageBonus");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Equipment_CritChance, "Assassin.Data.Equipment.CritChance");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Equipment_Weight, "Assassin.Data.Equipment.Weight");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Equipment_MaxHealth, "Assassin.Data.Equipment.MaxHealth");

UAssassinWeaponStatsEffect::UAssassinWeaponStatsEffect()
{
	DurationPolicy = EGameplayEffectDurationType::Infinite;
	StackingType = EGameplayEffectStackingType::None;
	auto AddBonus = [this](const FGameplayAttribute& Attribute, const FGameplayTag& Tag)
	{
		FGameplayModifierInfo Modifier;
		Modifier.Attribute = Attribute;
		Modifier.ModifierOp = EGameplayModOp::AddBase;
		FSetByCallerFloat Caller;
		Caller.DataTag = Tag;
		Modifier.ModifierMagnitude = FGameplayEffectModifierMagnitude(Caller);
		Modifiers.Add(Modifier);
	};
	AddBonus(UAssassinAttributeSet::GetAttackPowerAttribute(), TAG_Equipment_AttackPower);
	AddBonus(UAssassinAttributeSet::GetAssassinationPowerAttribute(), TAG_Equipment_AssassinationPower);
	AddBonus(UAssassinAttributeSet::GetCritDamageBonusAttribute(), TAG_Equipment_CritDamageBonus);
	AddBonus(UAssassinAttributeSet::GetCritChanceAttribute(), TAG_Equipment_CritChance);
	AddBonus(UAssassinAttributeSet::GetWeightAttribute(), TAG_Equipment_Weight);
	AddBonus(UAssassinAttributeSet::GetMaxHealthAttribute(), TAG_Equipment_MaxHealth);
}
