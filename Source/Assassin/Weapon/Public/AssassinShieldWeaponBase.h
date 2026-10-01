#pragma once

#include "CoreMinimal.h"
#include "AssassinWeaponBase.h"
#include "AssassinShieldWeaponBase.generated.h"

/** Shield health belongs to the shield actor; MaxHealthBonus belongs to its wearer. */
UCLASS(BlueprintType, Blueprintable)
class ASSASSIN_API AAssassinShieldWeaponBase : public AAssassinWeaponBase
{
	GENERATED_BODY()

public:
	AAssassinShieldWeaponBase();
	virtual float GetMaxHealthBonus() const override;
	virtual bool IsShieldWeapon() const override;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Shield", meta = (ClampMin = "0", DisplayName = "盾牌最大血量"))
	float MaxShieldHealth = 100.0f;

	UPROPERTY(VisibleInstanceOnly, BlueprintReadWrite, Transient, Category = "Weapon|Shield", meta = (DisplayName = "盾牌当前血量"))
	float ShieldHealth = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon|Shield", meta = (ClampMin = "0", DisplayName = "角色最大生命值加成"))
	float MaxHealthBonus = 0.0f;

	UFUNCTION(BlueprintCallable, BlueprintNativeEvent, Category = "Weapon|Shield")
	float ApplyShieldDamage(float Damage);
	virtual float ApplyShieldDamage_Implementation(float Damage);

	UFUNCTION(BlueprintCallable, BlueprintNativeEvent, Category = "Weapon|Shield")
	float RepairShield(float Amount);
	virtual float RepairShield_Implementation(float Amount);

	UFUNCTION(BlueprintImplementableEvent, Category = "Weapon|Shield")
	void OnShieldHealthChanged(float OldHealth, float NewHealth);
};
