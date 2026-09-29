#include "../Public/AssassinCharacter.h"

#include "AbilitySystemComponent.h"
#include "GameplayEffect.h"
#include "../Public/AssassinAttributeSet.h"

AAssassinCharacter::AAssassinCharacter()
{
	AbilitySystemComponent = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("AbilitySystemComponent"));

	AttributeSet = CreateDefaultSubobject<UAssassinAttributeSet>(TEXT("AttributeSet"));
}

UAbilitySystemComponent* AAssassinCharacter::GetAbilitySystemComponent() const
{
	return AbilitySystemComponent;
}

UAssassinAttributeSet* AAssassinCharacter::GetAssassinAttributeSet() const
{
	return AttributeSet;
}

void AAssassinCharacter::BeginPlay()
{
	Super::BeginPlay();

	AbilitySystemComponent->InitAbilityActorInfo(this, this);
	InitializeDefaultAttributes();
	BindAttributeDelegates();

	OnGASInitialized();
}

void AAssassinCharacter::InitializeDefaultAttributes()
{
	if (!IsValid(AbilitySystemComponent) || !DefaultAttributesEffect)
	{
		return;
	}

	FGameplayEffectContextHandle EffectContext = AbilitySystemComponent->MakeEffectContext();
	EffectContext.AddSourceObject(this);

	const FGameplayEffectSpecHandle EffectSpec = AbilitySystemComponent->MakeOutgoingSpec(
		DefaultAttributesEffect,
		1.0f,
		EffectContext);

	if (!EffectSpec.IsValid())
	{
		return;
	}

	AbilitySystemComponent->ApplyGameplayEffectSpecToSelf(*EffectSpec.Data.Get());
}

void AAssassinCharacter::BindAttributeDelegates()
{
	if (!IsValid(AbilitySystemComponent) || !IsValid(AttributeSet))
	{
		return;
	}

	FOnGameplayAttributeValueChange& HealthChangedDelegate =
		AbilitySystemComponent->GetGameplayAttributeValueChangeDelegate(AttributeSet->GetHealthAttribute());

	HealthChangedDelegate.RemoveAll(this);
	HealthChangedDelegate.AddUObject(this, &AAssassinCharacter::HandleHealthChanged);
}

void AAssassinCharacter::HandleHealthChanged(const FOnAttributeChangeData& Data)
{
	OnHealthChanged(Data.OldValue, Data.NewValue);
}
