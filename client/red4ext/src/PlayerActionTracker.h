#pragma once

#include <RED4ext/RED4ext.hpp>
#include <RedLib.hpp>

#include "RED4ext/CName.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/Object.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/events/HitEvent.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/input/ActionType.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/mounting/MountingEvent.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/mounting/UnmountingEvent.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/projectile/ShootEvent.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/weapon/Object.hpp"

class PlayerActionTracker final : public Red::IScriptable
{
public:
    void RecordPlayerAction(RED4ext::CName actionName, RED4ext::gameinputActionType actionType, float value);
    /// Called from the JumpEvents.OnEnter wrap — fires on the actual locomotion jump, not the button.
    void TrackJump();
    void OnShoot(RED4ext::Handle<RED4ext::gameprojectileShootEvent> event);
    /// Called from the player PSM's ShootEvents.OnEnter wrap — the only path that covers
    /// hitscan weapons (BaseProjectile.OnShoot never fires for them, choomlink-77e8).
    void OnPlayerShoot(RED4ext::ItemID item, RED4ext::Vector4 startPoint);
    void OnHit(RED4ext::Handle<RED4ext::GameObject> gameObject, RED4ext::Handle<RED4ext::gameHitEvent> event);
    void OnMounting(RED4ext::Handle<RED4ext::game::mounting::MountingEvent> event);
    void OnUnmounting(RED4ext::Handle<RED4ext::game::mounting::UnmountingEvent> event);
    void OnItemEquipped(RED4ext::TweakDBID slot, RED4ext::ItemID item, bool isWeapon);
    void OnItemUnequipped(RED4ext::TweakDBID slot, RED4ext::ItemID item, bool isWeapon);
    /// Called from the local player's Health stat-pool listener (choomlink-2hum). Percent, and
    /// deliberately state-driven rather than damage-driven: healing, regeneration and items change
    /// health without any hit ever happening.
    void OnPlayerHealthChanged(float healthPercent, bool isDead);
private:
    RTTI_IMPL_TYPEINFO(PlayerActionTracker);
    RTTI_IMPL_ALLOCATOR();
};

RTTI_DEFINE_CLASS(PlayerActionTracker, {
    RTTI_METHOD(RecordPlayerAction);
    RTTI_METHOD(TrackJump);
    RTTI_METHOD(OnShoot);
    RTTI_METHOD(OnPlayerShoot);
    RTTI_METHOD(OnHit);
    RTTI_METHOD(OnMounting);
    RTTI_METHOD(OnUnmounting);
    RTTI_METHOD(OnItemEquipped);
    RTTI_METHOD(OnItemUnequipped);
    RTTI_METHOD(OnPlayerHealthChanged);
    RTTI_ALIAS("Cyberverse.Network.Managers.PlayerActionTracker");
});
