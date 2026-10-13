#pragma once

#include <cstdint>

enum EMessageTypeClientbound: uint16_t {
    EINIT_AUTH_RESULT = 0,
    eSpawnEntity = 1,
    eTeleportEntity = 2,
    eDestroyEntity = 3,
    eEquipItemEntity = 4,
    eEntityAction = 5,
    eEntityShoot = 6,
    eEntityHealth = 7,
    eEntityHitConfirmed = 8,
    eEntityScriptEvent = 9, // Vault Hunters co-op: relayed generic redscript event, see ScriptEvent.h
};