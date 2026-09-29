#include "../Public/AssassinAttributeSet.h"

#include "GameplayEffectExtension.h"

void UAssassinAttributeSet::PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue)
{
	Super::PreAttributeChange(Attribute, NewValue);

	if (Attribute == GetHealthAttribute())
	{
		NewValue = FMath::Clamp(NewValue, 0.0f, GetMaxHealth());
	}
	else if (Attribute == GetMaxHealthAttribute() || Attribute == GetMaxAdrenalineAttribute())
	{
		NewValue = FMath::Max(NewValue, 0.0f);
	}
	else if (Attribute == GetAdrenalineAttribute())
	{
		NewValue = FMath::Clamp(NewValue, 0.0f, GetMaxAdrenaline());
	}
	else if (Attribute == GetAttackPowerAttribute()
		|| Attribute == GetAssassinationPowerAttribute()
		|| Attribute == GetDefenseAttribute()
		|| Attribute == GetCritChanceAttribute()
		|| Attribute == GetCritDamageBonusAttribute()
		|| Attribute == GetMoveSpeedAttribute())
	{
		NewValue = FMath::Max(NewValue, 0.0f);
	}
}

void UAssassinAttributeSet::PostAttributeChange(const FGameplayAttribute& Attribute, float OldValue, float NewValue)
{
	Super::PostAttributeChange(Attribute, OldValue, NewValue);

	if (Attribute == GetMaxHealthAttribute())
	{
		SetHealth(FMath::Clamp(GetHealth(), 0.0f, NewValue));
	}
	else if (Attribute == GetMaxAdrenalineAttribute())
	{
		SetAdrenaline(FMath::Clamp(GetAdrenaline(), 0.0f, NewValue));
	}
}

void UAssassinAttributeSet::PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data)
{
	Super::PostGameplayEffectExecute(Data);

	ClampCurrentAttributes();
}

void UAssassinAttributeSet::ClampCurrentAttributes()
{
	SetMaxHealth(FMath::Max(GetMaxHealth(), 0.0f));
	SetHealth(FMath::Clamp(GetHealth(), 0.0f, GetMaxHealth()));

	SetAttackPower(FMath::Max(GetAttackPower(), 0.0f));
	SetAssassinationPower(FMath::Max(GetAssassinationPower(), 0.0f));
	SetDefense(FMath::Max(GetDefense(), 0.0f));
	SetCritChance(FMath::Max(GetCritChance(), 0.0f));
	SetCritDamageBonus(FMath::Max(GetCritDamageBonus(), 0.0f));
	SetMoveSpeed(FMath::Max(GetMoveSpeed(), 0.0f));

	SetMaxAdrenaline(FMath::Max(GetMaxAdrenaline(), 0.0f));
	SetAdrenaline(FMath::Clamp(GetAdrenaline(), 0.0f, GetMaxAdrenaline()));
}
