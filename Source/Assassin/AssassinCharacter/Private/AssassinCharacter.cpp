#include "../Public/AssassinCharacter.h"

#include "AbilitySystemComponent.h"

AAssassinCharacter::AAssassinCharacter()
{
	AbilitySystemComponent = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("AbilitySystemComponent"));
}

UAbilitySystemComponent* AAssassinCharacter::GetAbilitySystemComponent() const
{
	return AbilitySystemComponent;
}

void AAssassinCharacter::BeginPlay()
{
	Super::BeginPlay();

	AbilitySystemComponent->InitAbilityActorInfo(this, this);
}
