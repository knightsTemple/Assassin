#include "../Public/AssassinPlayerState.h"

#include "AbilitySystemComponent.h"
#include "GameplayEffect.h"
#include "../../AssassinCharacter/Public/AssassinAttributeSet.h"

AAssassinPlayerState::AAssassinPlayerState()
{
	AbilitySystemComponent = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("AbilitySystemComponent"));
	AttributeSet = CreateDefaultSubobject<UAssassinAttributeSet>(TEXT("AttributeSet"));
}

UAbilitySystemComponent* AAssassinPlayerState::GetAbilitySystemComponent() const
{
	return AbilitySystemComponent;
}

UAssassinAttributeSet* AAssassinPlayerState::GetAssassinAttributeSet() const
{
	return AttributeSet;
}

bool AAssassinPlayerState::InitializeDefaultAttributesOnce(
	TSubclassOf<UGameplayEffect> DefaultAttributesEffect,
	UObject* SourceObject)
{
	if (bDefaultAttributesInitialized)
	{
		return true;
	}

	if (!IsValid(AbilitySystemComponent) || !DefaultAttributesEffect)
	{
		return false;
	}

	FGameplayEffectContextHandle EffectContext = AbilitySystemComponent->MakeEffectContext();
	EffectContext.AddSourceObject(IsValid(SourceObject) ? SourceObject : this);

	const FGameplayEffectSpecHandle EffectSpec = AbilitySystemComponent->MakeOutgoingSpec(
		DefaultAttributesEffect,
		1.0f,
		EffectContext);

	if (!EffectSpec.IsValid())
	{
		return false;
	}

	AbilitySystemComponent->ApplyGameplayEffectSpecToSelf(*EffectSpec.Data.Get());
	bDefaultAttributesInitialized = true;
	return true;
}
