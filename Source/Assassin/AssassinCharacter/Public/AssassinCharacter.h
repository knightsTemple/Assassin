#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "AbilitySystemInterface.h"
#include "AssassinCharacter.generated.h"

class UAbilitySystemComponent;
class UAssassinAttributeSet;
class UGameplayAbility;
class UGameplayEffect;
struct FOnAttributeChangeData;

UCLASS()
class ASSASSIN_API AAssassinCharacter : public ACharacter, public IAbilitySystemInterface
{
	GENERATED_BODY()

public:
	virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;

	UFUNCTION(BlueprintPure, Category = "Abilities")
	UAssassinAttributeSet* GetAssassinAttributeSet() const;

	UFUNCTION(BlueprintPure, Category = "Abilities")
	bool HasAbility(TSubclassOf<UGameplayAbility> AbilityClass) const;

protected:
	virtual void BeginPlay() override;
	virtual void PossessedBy(AController* NewController) override;
	virtual void UnPossessed() override;

	void InitializeAbilitySystem();
	void InitializeDefaultAttributes();
	void BindAttributeDelegates();
	void HandleHealthChanged(const FOnAttributeChangeData& Data);

	UPROPERTY(VisibleInstanceOnly, BlueprintReadOnly, Transient, Category = "Abilities")
	TObjectPtr<UAbilitySystemComponent> AbilitySystemComponent;

	UPROPERTY(VisibleInstanceOnly, BlueprintReadOnly, Transient, Category = "Abilities")
	TObjectPtr<UAssassinAttributeSet> AttributeSet;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "GAS")
	TSubclassOf<UGameplayEffect> DefaultAttributesEffect;
	
	UFUNCTION(BlueprintImplementableEvent, Category = "GAS")
	void OnGASInitialized();

	UFUNCTION(BlueprintImplementableEvent, Category = "GAS|Attributes")
	void OnHealthChanged(float OldValue, float NewValue);

private:
	bool bAbilitySystemInitialized = false;
};
