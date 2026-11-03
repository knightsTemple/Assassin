#pragma once

#include "CoreMinimal.h"
#include "Animation/AnimNotifies/AnimNotifyState.h"
#include "AssassinAttackWindowNotifyState.generated.h"

/** Native reflection bridge only. Per-character detection and lifecycle live in Lua. */
UCLASS(Blueprintable)
class ASSASSIN_API UAssassinAttackWindowNotifyState : public UAnimNotifyState
{
    GENERATED_BODY()
public:
    virtual void NotifyBegin(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, float Duration, const FAnimNotifyEventReference& Reference) override;
    virtual void NotifyTick(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, float DeltaTime, const FAnimNotifyEventReference& Reference) override;
    virtual void NotifyEnd(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, const FAnimNotifyEventReference& Reference) override;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Attack Window")
    FName AttackSource = TEXT("Axe");
};
