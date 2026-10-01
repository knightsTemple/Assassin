#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "UnLuaInterface.h"
#include "AssassinWeaponTypes.h"
#include "AssassinWeaponBase.generated.h"

class ACharacter;
class UAnimMontage;
class UGameplayEffect;
class USceneComponent;
class UStaticMeshComponent;

/** Reflected data and components only. Equipment rules live in Weapon.WeaponBase.lua. */
UCLASS(BlueprintType, Blueprintable)
class ASSASSIN_API AAssassinWeaponBase : public AActor, public IUnLuaInterface
{
	GENERATED_BODY()

public:
	AAssassinWeaponBase();
	virtual FString GetModuleName_Implementation() const override;

	UFUNCTION(BlueprintCallable, BlueprintNativeEvent, Category = "Weapon|Equipment")
	bool EquipToCharacter(ACharacter* Character);
	virtual bool EquipToCharacter_Implementation(ACharacter* Character);

	UFUNCTION(BlueprintCallable, BlueprintNativeEvent, Category = "Weapon|Equipment")
	bool UnequipFromCharacter();
	virtual bool UnequipFromCharacter_Implementation();

	UFUNCTION(BlueprintPure, Category = "Weapon|Stats")
	virtual float GetMaxHealthBonus() const;

	UFUNCTION(BlueprintPure, Category = "Weapon|Shield")
	virtual bool IsShieldWeapon() const;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Weapon|Mesh")
	TObjectPtr<USceneComponent> WeaponRoot;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Weapon|Mesh")
	TObjectPtr<UStaticMeshComponent> WeaponMesh;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Identity")
	FName WeaponId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Identity")
	FText DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Identity")
	EAssassinWeaponType WeaponType = EAssassinWeaponType::Sword;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Stats")
	FAssassinWeaponStats BaseStats;

	/** Equipment lifetime GE. Infinite duration and no stacking are required. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Weapon|GAS")
	TSubclassOf<UGameplayEffect> EquipmentStatsEffectClass;

	/** Persistent equipment buffs; Instant and stacking GEs are rejected by Lua. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|GAS")
	TArray<TSubclassOf<UGameplayEffect>> AdditionalEffects;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|GAS", meta = (ClampMin = "1"))
	float EffectLevel = 1.0f;

	/** None permits attribute-only testing; configure a real socket to attach the mesh. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Equipment")
	FName EquipSocketName;

	UPROPERTY(VisibleInstanceOnly, BlueprintReadWrite, Transient, Category = "Weapon|Equipment")
	TObjectPtr<ACharacter> EquippedCharacter;

	/** Per-weapon animation configuration, consumed when attack routing is integrated. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation")
	TArray<TObjectPtr<UAnimMontage>> LightAttackMontages;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation")
	TObjectPtr<UAnimMontage> DrawMontage;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation")
	TObjectPtr<UAnimMontage> SheatheMontage;

	UFUNCTION(BlueprintImplementableEvent, Category = "Weapon|Equipment")
	void OnWeaponEquipped(ACharacter* Character);

	UFUNCTION(BlueprintImplementableEvent, Category = "Weapon|Equipment")
	void OnWeaponUnequipped(ACharacter* PreviousCharacter);

protected:
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lua")
	FString LuaModuleName = TEXT("Weapon.WeaponBase");
};
