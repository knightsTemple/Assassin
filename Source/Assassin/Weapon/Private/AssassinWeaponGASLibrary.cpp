#include "../Public/AssassinWeaponGASLibrary.h"

#include "AbilitySystemComponent.h"
#include "GameFramework/Actor.h"

bool UAssassinWeaponGASLibrary::IsSpecValid(const FGameplayEffectSpecHandle& Spec)
{
	return Spec.IsValid();
}

bool UAssassinWeaponGASLibrary::IsEffectHandleValid(const FActiveGameplayEffectHandle& Handle)
{
	return Handle.IsValid();
}

FGameplayEffectContextHandle UAssassinWeaponGASLibrary::MakeWeaponEffectContext(UAbilitySystemComponent* ASC, AActor* Weapon)
{
	if (!IsValid(ASC) || !IsValid(Weapon))
	{
		return FGameplayEffectContextHandle();
	}
	FGameplayEffectContextHandle Context = ASC->MakeEffectContext();
	Context.AddSourceObject(Weapon);
	return Context;
}

FGameplayTag UAssassinWeaponGASLibrary::GetEquipmentDataTag(FName TagName)
{
	return FGameplayTag::RequestGameplayTag(TagName, false);
}
