#pragma once

#include "CoreMinimal.h"
#include "AttributeSet.h"
#include "AbilitySystemComponent.h"
#include "AssassinAttributeSet.generated.h"

#define ATTRIBUTE_ACCESSORS(ClassName, PropertyName) \
	GAMEPLAYATTRIBUTE_PROPERTY_GETTER(ClassName, PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_GETTER(PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_SETTER(PropertyName) \
	GAMEPLAYATTRIBUTE_VALUE_INITTER(PropertyName)

struct FGameplayEffectModCallbackData;

UCLASS(BlueprintType)
class ASSASSIN_API UAssassinAttributeSet : public UAttributeSet
{
	GENERATED_BODY()

public:
	virtual void PreAttributeChange(const FGameplayAttribute& Attribute, float& NewValue) override;
	virtual void PostAttributeChange(const FGameplayAttribute& Attribute, float OldValue, float NewValue) override;
	virtual void PostGameplayEffectExecute(const FGameplayEffectModCallbackData& Data) override;

	/** 当前生命值。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Health")
	FGameplayAttributeData Health;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, Health)

	/** 最大生命值。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Health")
	FGameplayAttributeData MaxHealth;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, MaxHealth)

	/** 普通攻击力。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Combat")
	FGameplayAttributeData AttackPower;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, AttackPower)

	/** 刺杀攻击力。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Combat")
	FGameplayAttributeData AssassinationPower;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, AssassinationPower)

	/** 防御力。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Combat")
	FGameplayAttributeData Defense;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, Defense)

	/** 暴击率，0.2 表示 20%。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Combat")
	FGameplayAttributeData CritChance;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, CritChance)

	/** 暴击额外伤害倍率，0.5 表示额外增加 50%。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Combat")
	FGameplayAttributeData CritDamageBonus;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, CritDamageBonus)

	/** 当前移动速度。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Movement")
	FGameplayAttributeData MoveSpeed;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, MoveSpeed)

	/** 当前技能能量（肾上腺素格）。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Adrenaline")
	FGameplayAttributeData Adrenaline;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, Adrenaline)

	/** 最大技能能量。 */
	UPROPERTY(BlueprintReadOnly, Category = "Attributes|Adrenaline")
	FGameplayAttributeData MaxAdrenaline;
	ATTRIBUTE_ACCESSORS(UAssassinAttributeSet, MaxAdrenaline)

private:
	void ClampCurrentAttributes();
};

#undef ATTRIBUTE_ACCESSORS
