#include "../Public/AssassinWeaponBase.h"

#include "../Public/AssassinWeaponStatsEffect.h"
#include "Components/SceneComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/Character.h"

AAssassinWeaponBase::AAssassinWeaponBase()
{
	PrimaryActorTick.bCanEverTick = false;
	WeaponRoot = CreateDefaultSubobject<USceneComponent>(TEXT("WeaponRoot"));
	SetRootComponent(WeaponRoot);
	WeaponMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("WeaponMesh"));
	WeaponMesh->SetupAttachment(WeaponRoot);
	WeaponRoot->SetMobility(EComponentMobility::Movable);
	WeaponMesh->SetMobility(EComponentMobility::Movable);
	WeaponMesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	WeaponMesh->SetSimulatePhysics(false);
	EquipmentStatsEffectClass = UAssassinWeaponStatsEffect::StaticClass();
}

FString AAssassinWeaponBase::GetModuleName_Implementation() const
{
	return LuaModuleName;
}

bool AAssassinWeaponBase::EquipToCharacter_Implementation(ACharacter* Character)
{
	UE_LOG(LogTemp, Warning, TEXT("Weapon Lua binding unavailable: %s"), *GetName());
	return false;
}

bool AAssassinWeaponBase::UnequipFromCharacter_Implementation()
{
	return false;
}

float AAssassinWeaponBase::GetMaxHealthBonus() const
{
	return 0.0f;
}

bool AAssassinWeaponBase::IsShieldWeapon() const
{
	return false;
}

FAssassinWeaponStats AAssassinWeaponBase::GetStatsAtLevel_Implementation(int32 Level) const
{
    return BaseStats;
}

FAssassinWeaponStats AAssassinWeaponBase::GetCurrentStats_Implementation() const
{
    return GetStatsAtLevel(WeaponLevel);
}

bool AAssassinWeaponBase::SetWeaponLevel_Implementation(int32 NewLevel)
{
    UE_LOG(LogTemp, Warning, TEXT("Weapon Lua binding unavailable: %s"), *GetName());
    return false;
}

bool AAssassinWeaponBase::RefreshEquipmentStats_Implementation()
{
    return false;
}
