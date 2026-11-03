#include "AssassinAttackWindowNotifyState.h"
#include "../AssassinCharacter/Public/AssassinCharacter.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/World.h"

namespace
{
void Dispatch(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, UObject* Window, FName Source, uint8 Phase)
{
    if (!IsValid(Mesh) || !Mesh->GetWorld() || !Mesh->GetWorld()->IsGameWorld()) return;
    if (AAssassinCharacter* Character = Cast<AAssassinCharacter>(Mesh->GetOwner()))
        Character->OnAttackWindow(Window, Animation, Source, Phase);
}
}

void UAssassinAttackWindowNotifyState::NotifyBegin(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, float Duration, const FAnimNotifyEventReference& Reference)
{
    Dispatch(Mesh, Animation, this, AttackSource, 0);
}
void UAssassinAttackWindowNotifyState::NotifyTick(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, float DeltaTime, const FAnimNotifyEventReference& Reference)
{
    Dispatch(Mesh, Animation, this, AttackSource, 1);
}
void UAssassinAttackWindowNotifyState::NotifyEnd(USkeletalMeshComponent* Mesh, UAnimSequenceBase* Animation, const FAnimNotifyEventReference& Reference)
{
    Dispatch(Mesh, Animation, this, AttackSource, 2);
}

