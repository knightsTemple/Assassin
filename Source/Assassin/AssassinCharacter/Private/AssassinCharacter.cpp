#include "../Public/AssassinCharacter.h"

#include "AbilitySystemComponent.h"
#include "../Public/AssassinAttributeSet.h"
#include "../../AssassinPlayerState/Public/AssassinPlayerState.h"

UAbilitySystemComponent* AAssassinCharacter::GetAbilitySystemComponent() const
{
	if (!IsValid(AbilitySystemComponent))
	{
		if (const AAssassinPlayerState* AssassinPlayerState = GetPlayerState<AAssassinPlayerState>())
		{
			return AssassinPlayerState->GetAbilitySystemComponent();
		}
	}

	return AbilitySystemComponent;
}

UAssassinAttributeSet* AAssassinCharacter::GetAssassinAttributeSet() const
{
	if (!IsValid(AttributeSet))
	{
		if (const AAssassinPlayerState* AssassinPlayerState = GetPlayerState<AAssassinPlayerState>())
		{
			return AssassinPlayerState->GetAssassinAttributeSet();
		}
	}

	return AttributeSet;
}

bool AAssassinCharacter::HasAbility(TSubclassOf<UGameplayAbility> AbilityClass) const
{
	const UAbilitySystemComponent* ASC = GetAbilitySystemComponent();
	return IsValid(ASC) && AbilityClass && ASC->FindAbilitySpecFromClass(AbilityClass) != nullptr;
}

void AAssassinCharacter::BeginPlay()
{
	Super::BeginPlay();

	InitializeAbilitySystem();
}

void AAssassinCharacter::PossessedBy(AController* NewController)
{
	Super::PossessedBy(NewController);

	InitializeAbilitySystem();
}

void AAssassinCharacter::UnPossessed()
{
	if (IsValid(AbilitySystemComponent))
	{
		if (IsValid(AttributeSet))
		{
			AbilitySystemComponent->GetGameplayAttributeValueChangeDelegate(AttributeSet->GetHealthAttribute())
				.RemoveAll(this);
		}

		if (AbilitySystemComponent->GetAvatarActor() == this)
		{
			AbilitySystemComponent->ClearActorInfo();
		}
	}

	AbilitySystemComponent = nullptr;
	AttributeSet = nullptr;
	bAbilitySystemInitialized = false;

	Super::UnPossessed();
}

void AAssassinCharacter::InitializeAbilitySystem()
{
	AAssassinPlayerState* AssassinPlayerState = GetPlayerState<AAssassinPlayerState>();
	if (!IsValid(AssassinPlayerState))
	{
		return;
	}

	UAbilitySystemComponent* PlayerAbilitySystemComponent = AssassinPlayerState->GetAbilitySystemComponent();
	UAssassinAttributeSet* PlayerAttributeSet = AssassinPlayerState->GetAssassinAttributeSet();
	if (!IsValid(PlayerAbilitySystemComponent) || !IsValid(PlayerAttributeSet))
	{
		return;
	}

	AbilitySystemComponent = PlayerAbilitySystemComponent;
	AttributeSet = PlayerAttributeSet;
	AbilitySystemComponent->InitAbilityActorInfo(AssassinPlayerState, this);

	if (bAbilitySystemInitialized || !HasActorBegunPlay())
	{
		return;
	}

	InitializeDefaultAttributes();
	BindAttributeDelegates();

	bAbilitySystemInitialized = true;
	OnGASInitialized(); //lua侧的代码
}

void AAssassinCharacter::InitializeDefaultAttributes()
{
	if (AAssassinPlayerState* AssassinPlayerState = GetPlayerState<AAssassinPlayerState>())
	{
		AssassinPlayerState->InitializeDefaultAttributesOnce(DefaultAttributesEffect, this);
	}
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
