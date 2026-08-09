#include "PlayerActionTracker.h"
#include "Main.h"
#include "RED4ext/Api/v1/Sdk.hpp"

#include "NetworkGameSystem.h"
#include "RED4ext/Scripting/Natives/Generated/game/MountEventData.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/damage/AttackData.hpp"
#include "RED4ext/Scripting/Natives/Generated/game/mounting/MountingRequest.hpp"
#include "Utils.h"

#include <serverbound/WorldPacketsServerBound.h>

void PlayerActionTracker::RecordPlayerAction(RED4ext::CName actionName, RED4ext::gameinputActionType actionType,
                                             float value)
{
    const auto name = std::string(actionName.ToString());
    // SDK->logger->InfoF(PLUGIN, "Player Action %s (%d) -> %f", name.c_str(), actionType, value);

    // We ignore movement inputs like Forward, MoveX, MoveY for now, because we don't care about animations but just
    // want the most recent position And for that, those inputs are very unreliable due to physics/collision etc anyway.
    if (actionType == RED4ext::game::input::ActionType::RELATIVE_CHANGE)
    {
        // think about mouse movements, at least mouse_x is important as yaw.
        // alternatively CameraMouseX.
    }
    // NOTE: Jump used to be tracked here via BUTTON_RELEASED, but that fires even when no jump
    // happens (menus, blocked states). It now comes from the locomotion state machine instead
    // (JumpEvents.OnEnter wrap -> TrackJump), fixing the upstream-noted false positives.
}

void PlayerActionTracker::TrackJump()
{
    const auto player = Cyberverse::Utils::GetPlayer();
    const auto [X, Y, Z, W] = Cyberverse::Utils::Entity_GetWorldPosition(player);

    PlayerActionTracked tracked = {};
    tracked.action = eACTION_JUMP;
    tracked.worldTransform = { X, Y, Z };

    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(1, tracked);
}

void PlayerActionTracker::OnShoot(RED4ext::Handle<RED4ext::gameprojectileShootEvent> event)
{
    // Local-shot filtering happens in the redscript wrapper (Cyberverse.reds OnShoot): the
    // projectile owner is the wielder for some weapons but the WEAPON object for others, and
    // that check is natural in reds (TransactionSystem slot compare). Everything arriving
    // here is already attributed to the local player.

    // Weapon identity from the event (upstream left this TODO; the comment used to swallow
    // the EnqueueMessage line as the assignment's right-hand side).
    uint64_t weaponTdbid = 0;
    if (const auto weapon = event->weapon.Lock())
    {
        RED4ext::ItemID itemId = {};
        Red::CallVirtual(weapon, "GetItemID", itemId);
        weaponTdbid = itemId.tdbid.value;
    }

    PlayerShoot player_shoot = {};
    player_shoot.charge = event->params.charge;
    player_shoot.startPoint = Vector3 { event->startPoint.X, event->startPoint.Y, event->startPoint.Z };
    player_shoot.itemIdWeapon = weaponTdbid;
    SDK->logger->InfoF(PLUGIN, "diag: local shot captured, weapon %llu", weaponTdbid);
    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, player_shoot);
}

void PlayerActionTracker::OnPlayerShoot(const RED4ext::ItemID item, const RED4ext::Vector4 startPoint,
                                        const float damagePerHit, const RED4ext::Vector4 aimPoint)
{
    // Comes from the player state machine's shoot state (vanilla weaponTransitions.script:1895
    // ShootEvents.OnEnter) — that PSM only ever runs for the local player, so no owner filter
    // is needed here, and unlike BaseProjectile.OnShoot it also covers hitscan weapons.
    PlayerShoot player_shoot = {};
    player_shoot.charge = 1.0f;
    player_shoot.startPoint = Vector3 { startPoint.X, startPoint.Y, startPoint.Z };
    player_shoot.itemIdWeapon = item.tdbid.value;
    player_shoot.damagePerHit = damagePerHit;
    player_shoot.aimPoint = Vector3 { aimPoint.X, aimPoint.Y, aimPoint.Z };
    SDK->logger->InfoF(PLUGIN, "diag: local shot (PSM), weapon %llu dmg %.1f aim (%.2f, %.2f, %.2f)",
                       item.tdbid.value, damagePerHit, aimPoint.X, aimPoint.Y, aimPoint.Z);
    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, player_shoot);
}

void PlayerActionTracker::OnPlayerHealthChanged(const float healthPercent, const bool isDead)
{
    // Rate limiting lives on the redscript side (a change threshold), not here: this native is the
    // dumb transport end, and the listener already fires only on actual changes.
    PlayerHealthUpdate health = {};
    health.healthPercent = healthPercent;
    health.isDead = isDead;
    SDK->logger->InfoF(PLUGIN, "diag: local health %.1f%% dead=%d", healthPercent, isDead ? 1 : 0);
    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, health);
}

void PlayerActionTracker::OnPlayerWasHit(const uint64_t shooterNetworkedEntityId, const float damageDealt,
                                         const bool isHeadshot, const bool isDead)
{
    PlayerWasHit was_hit = {};
    was_hit.shooterNetworkedEntityId = shooterNetworkedEntityId;
    was_hit.damageDealt = damageDealt;
    was_hit.isHeadshot = isHeadshot;
    was_hit.isDead = isDead;
    SDK->logger->InfoF(PLUGIN, "diag: local hit taken, shooter %llu dmg %.1f headshot=%d dead=%d",
                       shooterNetworkedEntityId, damageDealt, isHeadshot ? 1 : 0, isDead ? 1 : 0);
    // Queued, not sent directly (root-caused 2026-08-09): this function is reached from
    // OnDamageReceived, a reaction to processing an incoming EntityShoot inside THIS SAME
    // TICK's PollIncomingMessages(). A direct SendMessageToConnection from here reported full
    // success at every step (valid GameSystem pointer, successful serialize, k_EResultOK) and
    // the server never received a single one -- a reentrant-send signature. NetworkGameSystem
    // flushes this queue right after PollIncomingMessages() returns, same tick, outside its
    // call stack. See NetworkGameSystem::m_pendingHitConfirms for the full writeup.
    const auto networkSystem = Red::GetGameSystem<NetworkGameSystem>();
    if (networkSystem)
    {
        networkSystem->QueuePlayerWasHit(was_hit);
    }
}

void PlayerActionTracker::LogDiag(const int32_t code, const float value)
{
    SDK->logger->InfoF(PLUGIN, "diag: reds code=%d value=%.2f", code, value);
}

void PlayerActionTracker::OnHit(RED4ext::Handle<RED4ext::GameObject> gameObject,
                                RED4ext::Handle<RED4ext::gameHitEvent> event)
{
    SDK->logger->InfoF(PLUGIN, "OnHit! %d", event->attackData->attackType);
}

void PlayerActionTracker::OnMounting(RED4ext::Handle<RED4ext::game::mounting::MountingEvent> event)
{
    if (event->relationship.otherMountableType != RED4ext::game::MountingObjectType::Vehicle)
    {
        // mountingSubType would tell us whether bike or car.
        return;
    }

    if (event->relationship.relationshipType != RED4ext::game::MountingRelationshipType::Parent)
    {
        // If the car mounts us, do nothing
        return;
    }

    if (event->relationship.otherObject.Expired())
    {
        SDK->logger->Warn(PLUGIN,
                          "Cannot Process PlayerActionTracker::OnMounting as the vehicle's weak ref has expried");
        return;
    }

    // Keep alive as long as the derived vehicleInstance
    const auto strongLock = event->relationship.otherObject.Lock();
    // TODO: if you figure out how to inline that, you're welcome to do so.
    const RED4ext::game::Object* ptr = strongLock;
    const auto vehicleInstance = RED4ext::Handle((RED4ext::VehicleObject*)ptr);

    // TODO: vehicles.swift, there is VehicleObject.GetRecordID(), but there is also GameObject::GetTDBID(go) which is
    // more generic and handles casting, so it works for puppets, devices _and_ vehicles. Question is if we should here
    // just implement both so we can avoid casting and misleading?

    const auto recordId = Cyberverse::Utils::VehicleObject_GetRecordID(vehicleInstance);
    const auto [X, Y, Z, W] = Cyberverse::Utils::Entity_GetWorldPosition(vehicleInstance);
    const auto orientation = Cyberverse::Utils::Entity_GetWorldOrientation(vehicleInstance);
    const auto [Roll, Pitch, Yaw] = Cyberverse::Utils::Quaternion_ToEulerAngles(orientation);

    PlayerSpawnCar spawnCar = {};
    spawnCar.recordId = recordId.value;
    spawnCar.worldTransform = Vector3{X, Y, Z};
    spawnCar.yaw = Yaw;

    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, spawnCar);
}

void PlayerActionTracker::OnUnmounting(RED4ext::Handle<RED4ext::game::mounting::UnmountingEvent> event)
{
    if (event->relationship.otherMountableType != RED4ext::game::MountingObjectType::Vehicle)
    {
        // mountingSubType would tell us whether bike or car.
        return;
    }

    if (event->relationship.relationshipType != RED4ext::game::MountingRelationshipType::Parent)
    {
        // If the car mounts us, do nothing
        return;
    }

    if (event->relationship.otherObject.Expired())
    {
        SDK->logger->Warn(PLUGIN, "Cannot Process PlayerActionTracker::OnUnmounting as the vehicle's weak ref "
                                  "has expried");
        return;
    }

    // Keep alive as long as the derived vehicleInstance
    const auto strongLock = event->relationship.otherObject.Lock();
    // TODO: if you figure out how to inline that, you're welcome to do so.
    const RED4ext::game::Object* ptr = strongLock;
    const auto vehicleInstance = RED4ext::Handle((RED4ext::VehicleObject*)ptr);

    // TODO: Read the networkedEntityId from the entity, so we can be precise and the server doesn't need to guess.
    const PlayerUnmountCar unmount_car = {};
    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, unmount_car);
}

void PlayerActionTracker::OnItemEquipped(const RED4ext::TweakDBID slot, const RED4ext::ItemID item, const bool isWeapon)
{
    SDK->logger->InfoF(PLUGIN, "Item Equipped at slot %llu with item %llu", slot.value, item.tdbid.value);
    PlayerEquipItem player_equip = {};
    player_equip.slot = slot.value;
    player_equip.itemId = item.tdbid.value;
    player_equip.isWeapon = isWeapon;
    player_equip.isUnequipping = false;
    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, player_equip);
}

void PlayerActionTracker::OnItemUnequipped(const RED4ext::TweakDBID slot, const RED4ext::ItemID item, const bool isWeapon)
{
    SDK->logger->InfoF(PLUGIN, "Item Unequipped at slot %llu with item %llu", slot.value, item.tdbid.value);
    PlayerEquipItem player_equip = {};
    player_equip.slot = slot.value;
    player_equip.itemId = item.tdbid.value;
    player_equip.isWeapon = isWeapon;
    player_equip.isUnequipping = true;
    Red::GetGameSystem<NetworkGameSystem>()->EnqueueMessage(0, player_equip);
}
