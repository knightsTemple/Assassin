#pragma once

#include "CoreMinimal.h"
#include "GameplayEffect.h"
#include "AssassinWeaponStatsEffect.generated.h"

/** Reversible equipment stats: additive modifiers supplied by Lua via SetByCaller. */
UCLASS(Blueprintable)
class ASSASSIN_API UAssassinWeaponStatsEffect : public UGameplayEffect
{
	GENERATED_BODY()

public:
	UAssassinWeaponStatsEffect();
};
