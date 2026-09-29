#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "UnLuaInterface.h"
#include "UnLuaSmokeTestActor.generated.h"

UCLASS()
class ASSASSIN_API AUnLuaSmokeTestActor : public AActor, public IUnLuaInterface
{
	GENERATED_BODY()

public:
	virtual FString GetModuleName_Implementation() const override;

protected:
	virtual void BeginPlay() override;

	UFUNCTION(BlueprintImplementableEvent, Category = "Lua")
	bool RunLuaSmokeTest();
};
