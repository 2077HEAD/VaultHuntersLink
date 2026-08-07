#pragma once

#include "../MessageFrame.h"
#include "EMessageTypeServerbound.h"

struct PlayerJoinWorld {
    Vector3 position;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = EPLAYER_JOIN_WORLD;
        frame.channel_id = 0; // TODO
    }
};

enum PlayerAction: uint8_t
{
    eACTION_JUMP,
    eACTION_RANGED_ATTACK,
};

struct PlayerActionTracked
{
    // TODO: bool buttonState? (We could trigger on press or release)
    // TODO: uint64_t networkTick (relative to the connect in relative server timestamps, because we probably get those batched and relay those batched)
    PlayerAction action;
    Vector3 worldTransform;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerActionTracked;
        frame.channel_id = 1; // TODO
    }
};

struct PlayerPositionUpdate
{
    // TODO: uint64_t networkTick (relative to the connect in relative server timestamps, because we probably get those batched and relay those batched)
    Vector3 worldTransform;
    float yaw;
    float pitch; // camera/aim pitch in degrees; puppets only carry yaw in their transform

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerPositionUpdate;
        frame.channel_id = 1; // TODO
    }
};

// TODO: Hook "call player car", then it's just a matter of tracking NPC cars.
struct PlayerSpawnCar {
    Vector3 worldTransform;
    float yaw;
    uint64_t recordId;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerSpawnCar;
        frame.channel_id = 0; // TODO
    }
};

struct PlayerUnmountCar {
    // TODO: NetworkedEntityId

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerUnmountCar;
        frame.channel_id = 0; // TODO
    }
};

struct PlayerEquipItem {
    uint64_t slot;
    uint64_t itemId;
    bool isWeapon;
    bool isUnequipping;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerEquipItem;
        frame.channel_id = 0; // TODO
    }
};

// The player's own health, reported by the client that owns it (damage/health sync design §1c).
// Percent, not points: the victim's client runs the real damage pipeline with the victim's real
// stats, and a remote puppet's maximum hit points differ from the player's anyway -- an absolute
// value would be meaningless at the other end.
struct PlayerHealthUpdate {
    float healthPercent; // 0..100
    bool isDead;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerHealthUpdate;
        frame.channel_id = 0; // state, like PlayerEquipItem
    }
};

struct PlayerShoot {
    // TODO: This should be the weaponId perspectively, not the TweakDBID
    uint64_t itemIdWeapon;
    Vector3 startPoint;
    float charge;
    // Weapon damage per hit, read from the shooter's own weapon (damage/health sync design
    // 2026-08-03). The shooter is the only machine where this weapon has real, rolled stats:
    // everywhere else it is an item handed to an NPC puppet, which carries none -- measured,
    // the puppet's weapon reports 0. The victim still runs its own armour and resistance math
    // on this number, so authority over the victim's health stays local.
    float damagePerHit;
    // Where the shot is aimed, in world space -- NOT a direction (aim-point relay, 2026-08-07).
    //
    // Relaying yaw/pitch and rebuilding a point from them cannot work, and the reason is
    // geometric rather than a tuning problem: the observer reconstructed the point as
    // `puppet position + direction * 50 m`, but the projectile leaves the MUZZLE, which sits
    // beside the body. Firing from the muzzle at a point derived from the body centre yields a
    // line parallel to the intended one, displaced by the muzzle offset -- about 23 cm sideways
    // at 3.7 m range. The user saw exactly that: "trifft leicht seitlich, manche Schuesse
    // treffen, manche nicht". A direction can never be turned back into the original ray while
    // the origin differs; moving the reference point only relocates the error.
    //
    // Zero means "no aim point available"; the observer then falls back to the old
    // direction-derived point rather than shooting at the world origin.
    Vector3 aimPoint;

    inline static void FillMessageFrame(MessageFrame& frame)
    {
        frame.message_type = ePlayerShoot;
        frame.channel_id = 0; // TODO
    }
};