#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "AbilitySystemInterface.h"
#include "AssassinCharacter.generated.h"

class UAbilitySystemComponent;
class UAssassinAttributeSet;
class UGameplayEffect;
struct FOnAttributeChangeData;

UCLASS()
class ASSASSIN_API AAssassinCharacter : public ACharacter, public IAbilitySystemInterface
{
	GENERATED_BODY()

public:
	AAssassinCharacter();

	virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;

	UFUNCTION(BlueprintPure, Category = "Abilities")
	UAssassinAttributeSet* GetAssassinAttributeSet() const;

protected:
	virtual void BeginPlay() override;
	void InitializeDefaultAttributes();
	void BindAttributeDelegates();
	void HandleHealthChanged(const FOnAttributeChangeData& Data);

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Abilities")
	UAbilitySystemComponent* AbilitySystemComponent;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Abilities")
	UAssassinAttributeSet* AttributeSet;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "GAS")
	TSubclassOf<UGameplayEffect> DefaultAttributesEffect;
	
	UFUNCTION(BlueprintImplementableEvent, Category = "GAS")
	void OnGASInitialized();

	UFUNCTION(BlueprintImplementableEvent, Category = "GAS|Attributes")
	void OnHealthChanged(float OldValue, float NewValue);
};
