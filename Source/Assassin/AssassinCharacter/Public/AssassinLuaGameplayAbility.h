#pragma once

#include "CoreMinimal.h"
#include "Abilities/GameplayAbility.h"
#include "UnLuaInterface.h"
#include "AssassinLuaGameplayAbility.generated.h"

/** GAS lifecycle and UnLua binding only; attack rules live in Lua. */
UCLASS()
class ASSASSIN_API UAssassinLuaGameplayAbility : public UGameplayAbility, public IUnLuaInterface
{
    GENERATED_BODY()

public:
    virtual FString GetModuleName_Implementation() const override;

protected:
    UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Lua")
    FString LuaModuleName;
};
