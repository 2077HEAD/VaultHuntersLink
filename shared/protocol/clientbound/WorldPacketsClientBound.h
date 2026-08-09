#pragma once

#include "../MessageFrame.h"
#include "EMessageTypeClientbound.h"

// TODO: we need to find a solution for strings, as zpp::bits doesn't support char* and c# doesn't support std::string.
// constant arrays are wasteful. So we add yet another type just for the C# ABI
// Actually it can't be a char* there either, otherwise we _do_ need message type dependant deconstructors

struct SpawnEntity {
    uint64_t networkedEntityId = 0;
    uint64_t recordId;
    Vector3 spawnPosition {0, 0, 0};

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eSpawnEntity;
        frame.channel_id = 1; // TODO:
    }
};

struct DestroyEntity {
    uint64_t networkedEntityId = 0;

    inline static void FillMessageFrame(MessageFrame& frame) {
        frame.message_type = eDestroyEntity;
        frame.channel_id = 1; // TODO:
    }
};

// TODO: There will be better packets, containing target locations for interpolation, with timestamps.
struct TeleportEntity
{
    uint64_t networkedEntityId;
    Vector3 targetPosition;
    float yaw; // NPCs (i.e. players) only have a yaw that you can set anyway, not a full rotation.
    float pitch; // aim pitch in degrees, drives the puppet's upper-body LookAt (not the transform)

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eTeleportEntity;
        frame.channel_id = 1; // TODO:
    }
};

// Relays a serverbound PlayerActionTracked (jump, later swim/climb/...) to the other
// clients. `action` mirrors the serverbound PlayerAction enum.
struct EntityAction {
    uint64_t networkedEntityId;
    uint8_t action;
    Vector3 worldTransform;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eEntityAction;
        frame.channel_id = 1; // TODO
    }
};

struct EquipItemEntity {
    uint64_t networkedEntityId;
    uint64_t slot;
    uint64_t itemId;
    bool isWeapon;
    bool isUnequipping;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eEquipItemEntity;
        frame.channel_id = 0; // TODO
    }
};

// A player's health, as held by the server and pushed to everyone tracking that player's puppet.
// Sent both on change and as a snapshot when a viewer starts tracking the entity -- health is
// state, not an event log, so a late joiner needs the current value and not the hit history
// (same reasoning as EquipItemEntity).
struct EntityHealth {
    uint64_t networkedEntityId;
    float healthPercent; // 0..100
    bool isDead;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eEntityHealth;
        frame.channel_id = 0;
    }
};

// Relays a serverbound PlayerShoot to the clients tracking the shooter's puppet.
struct EntityShoot {
    uint64_t networkedEntityId;
    uint64_t itemIdWeapon;
    Vector3 startPoint;
    float charge;
    float damagePerHit; // see PlayerShoot::damagePerHit
    Vector3 aimPoint;   // see PlayerShoot::aimPoint — world-space aim point, zero = none

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eEntityShoot;
        frame.channel_id = 1;
    }
};

// Relays a serverbound PlayerWasHit back to the shooter that landed it — and ONLY to that
// one connection, not a tracker broadcast (see PlayerPacketHandler.HandlePlayerWasHit).
struct EntityHitConfirmed {
    uint64_t victimNetworkedEntityId;
    float damageDealt;
    bool isHeadshot;
    bool isDead;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = eEntityHitConfirmed;
        frame.channel_id = 0;
    }
};
