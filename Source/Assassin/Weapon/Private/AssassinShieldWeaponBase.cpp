#include "../Public/AssassinShieldWeaponBase.h"

AAssassinShieldWeaponBase::AAssassinShieldWeaponBase()
{
	WeaponType = EAssassinWeaponType::Shield;
}

float AAssassinShieldWeaponBase::GetMaxHealthBonus() const
{
	return MaxHealthBonus;
}

bool AAssassinShieldWeaponBase::IsShieldWeapon() const
{
	return true;
}

float AAssassinShieldWeaponBase::ApplyShieldDamage_Implementation(float Damage)
{
	return 0.0f;
}

float AAssassinShieldWeaponBase::RepairShield_Implementation(float Amount)
{
	return 0.0f;
}
