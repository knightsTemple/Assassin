#pragma once

#include "CoreMinimal.h"
#include "AbilitySystemInterface.h"
#include "GameFramework/PlayerState.h"
#include "AssassinPlayerState.generated.h"

class UAbilitySystemComponent;
class UAssassinAttributeSet;
class UGameplayEffect;

UCLASS()
class ASSASSIN_API AAssassinPlayerState : public APlayerState, public IAbilitySystemInterface
{
	GENERATED_BODY()

public:
	AAssassinPlayerState();

	virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;

	UFUNCTION(BlueprintPure, Category = "Abilities")
	UAssassinAttributeSet* GetAssassinAttributeSet() const;

	bool InitializeDefaultAttributesOnce(
		TSubclassOf<UGameplayEffect> DefaultAttributesEffect,
		UObject* SourceObject);

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Abilities")
	TObjectPtr<UAbilitySystemComponent> AbilitySystemComponent;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Abilities")
	TObjectPtr<UAssassinAttributeSet> AttributeSet;

private:
	bool bDefaultAttributesInitialized = false;
};
