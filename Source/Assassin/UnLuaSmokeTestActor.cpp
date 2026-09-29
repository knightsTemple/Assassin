#include "UnLuaSmokeTestActor.h"

FString AUnLuaSmokeTestActor::GetModuleName_Implementation() const
{
	return TEXT("SmokeTest.UnLuaSmokeTestActor");
}

void AUnLuaSmokeTestActor::BeginPlay()
{
	Super::BeginPlay();

	const bool bLuaCalled = RunLuaSmokeTest();
	UE_LOG(LogTemp, Display, TEXT("UnLua smoke test: %s"), bLuaCalled ? TEXT("PASS") : TEXT("FAIL"));
}
