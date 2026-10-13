#pragma once

#include <cstdint>

enum EMessageTypeServerbound: uint16_t {
    EINIT_AUTH = 0,
    EPLAYER_JOIN_WORLD = 1,
    ePlayerActionTracked = 2,
    ePlayerPositionUpdate = 3,
    ePlayerSpawnCar = 4,
    ePlayerMountCar = 5, // TODO: Implement
    ePlayerUnmountCar = 6,
    ePlayerEquipItem = 7,
    ePlayerShoot = 8,
    ePlayerHealthUpdate = 9,
    ePlayerWasHit = 10,
    ePlayerScriptEvent = 11, // Vault Hunters co-op: generic redscript event, see ScriptEvent.h
    ePlayerSetAvatar = 12    // Vault Hunters co-op: which character record other players see us as
};