#pragma once

#include "CoreMinimal.h"
#include "AssassinWeaponTypes.generated.h"

UENUM(BlueprintType)
enum class EAssassinWeaponType : uint8
{
	Sword UMETA(DisplayName = "剑"),
	LongBlade UMETA(DisplayName = "长刀"),
	Bow UMETA(DisplayName = "弓箭"),
	Shield UMETA(DisplayName = "盾牌"),
	Axe UMETA(DisplayName = "斧头")
};

/** Equipment contributions, not the character's final attribute values. */
USTRUCT(BlueprintType)
struct ASSASSIN_API FAssassinWeaponStats
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon", meta = (ClampMin = "0", DisplayName = "攻击力加成"))
	float AttackPower = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon", meta = (ClampMin = "0", DisplayName = "刺杀攻击力加成"))
	float AssassinationPower = 0.0f;

	/** 0.5 adds 50% critical damage, matching UAssassinAttributeSet. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon", meta = (ClampMin = "0", DisplayName = "暴击伤害倍率加成"))
	float CritDamageBonus = 0.0f;

	/** 0.1 adds ten percentage points of critical chance. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon", meta = (ClampMin = "0", ClampMax = "1", DisplayName = "暴击率加成"))
	float CritChance = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Weapon", meta = (ClampMin = "0", DisplayName = "重量"))
	float Weight = 0.0f;
};
