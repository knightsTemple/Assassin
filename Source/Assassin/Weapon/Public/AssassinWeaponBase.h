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

    /** Fixed values used for attributes without a growth curve. */
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Stats")
    FAssassinWeaponStats BaseStats;

    /** Initial level; use SetWeaponLevel at runtime to refresh equipped bonuses. */
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Weapon|Progression", meta = (ClampMin = "1", ClampMax = "100", UIMin = "1", UIMax = "100", DisplayName = "武器等级"))
    int32 WeaponLevel = 1;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Progression", meta = (DisplayName = "属性成长曲线"))
    FAssassinWeaponStatCurves StatGrowthCurves;

    UFUNCTION(BlueprintPure, BlueprintNativeEvent, Category = "Weapon|Stats")
    FAssassinWeaponStats GetStatsAtLevel(int32 Level) const;
    virtual FAssassinWeaponStats GetStatsAtLevel_Implementation(int32 Level) const;

    UFUNCTION(BlueprintPure, BlueprintNativeEvent, Category = "Weapon|Stats")
    FAssassinWeaponStats GetCurrentStats() const;
    virtual FAssassinWeaponStats GetCurrentStats_Implementation() const;

    UFUNCTION(BlueprintCallable, BlueprintNativeEvent, Category = "Weapon|Progression")
    bool SetWeaponLevel(int32 NewLevel);
    virtual bool SetWeaponLevel_Implementation(int32 NewLevel);

    /** Re-read curves/BaseStats and update only this weapon's existing equipment GE. */
    UFUNCTION(BlueprintCallable, BlueprintNativeEvent, Category = "Weapon|Stats")
    bool RefreshEquipmentStats();
    virtual bool RefreshEquipmentStats_Implementation();


	/** Equipment lifetime GE. Infinite duration and no stacking are required. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Weapon|GAS")
	TSubclassOf<UGameplayEffect> EquipmentStatsEffectClass;

	/** Persistent equipment buffs; Instant and stacking GEs are rejected by Lua. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|GAS")
	TArray<TSubclassOf<UGameplayEffect>> AdditionalEffects;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|GAS", meta = (ClampMin = "1"))
	float EffectLevel = 1.0f;

	/** Socket on the equipped character skeletal mesh; None applies attributes without attachment. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Equipment", meta = (DisplayName = "角色装备插槽"))
	FName EquipSocketName;

	/** Optional hand socket used after drawing the equipped weapon. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Equipment", meta = (DisplayName = "拔出后握持插槽"))
	FName DrawnSocketName;

	UPROPERTY(VisibleInstanceOnly, BlueprintReadWrite, Transient, Category = "Weapon|Equipment")
	TObjectPtr<ACharacter> EquippedCharacter;

	/** Ordered combo montages consumed by the equipped character light attack. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation", meta = (DisplayName = "轻攻击动画"))
	TArray<TObjectPtr<UAnimMontage>> LightAttackMontages;

	/** Reserved for the future heavy attack; no playback logic yet. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation", meta = (DisplayName = "重攻击动画"))
	TArray<TObjectPtr<UAnimMontage>> HeavyAttackMontages;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation", meta = (DisplayName = "拔出武器动画"))
	TObjectPtr<UAnimMontage> DrawMontage;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Animation", meta = (DisplayName = "收起武器动画"))
	TObjectPtr<UAnimMontage> SheatheMontage;

	UFUNCTION(BlueprintImplementableEvent, Category = "Weapon|Equipment")
	void OnWeaponEquipped(ACharacter* Character);

	UFUNCTION(BlueprintImplementableEvent, Category = "Weapon|Equipment")
	void OnWeaponUnequipped(ACharacter* PreviousCharacter);

protected:
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lua")
	FString LuaModuleName = TEXT("Weapon.WeaponBase");
};
