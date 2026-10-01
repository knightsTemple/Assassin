#pragma once

#include "CoreMinimal.h"
#include "GameplayEffectTypes.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "AssassinWeaponGASLibrary.generated.h"

class UAbilitySystemComponent;

/** Exposes GAS handle/context helpers that are not reflected for UnLua by the engine. */
UCLASS()
class ASSASSIN_API UAssassinWeaponGASLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	UFUNCTION(BlueprintPure, Category = "Weapon|GAS")
	static bool IsSpecValid(const FGameplayEffectSpecHandle& Spec);

	UFUNCTION(BlueprintPure, Category = "Weapon|GAS")
	static bool IsEffectHandleValid(const FActiveGameplayEffectHandle& Handle);

	UFUNCTION(BlueprintCallable, Category = "Weapon|GAS")
	static FGameplayEffectContextHandle MakeWeaponEffectContext(UAbilitySystemComponent* ASC, AActor* Weapon);

	UFUNCTION(BlueprintPure, Category = "Weapon|GAS")
	static FGameplayTag GetEquipmentDataTag(FName TagName);
};
