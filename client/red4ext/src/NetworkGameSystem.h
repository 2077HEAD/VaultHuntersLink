#ifndef NETWORKMANAGERCONTROLLER_H
#define NETWORKMANAGERCONTROLLER_H
#include "RED4ext/Api/v1/Sdk.hpp"
#include "RED4ext/SystemUpdate.hpp"

#include "RED4ext/Scripting/IScriptable.hpp"
#include "RED4ext/Scripting/Natives/Generated/ink/ISystemRequestsHandler.hpp"
#include "RED4ext/Scripting/Stack.hpp"

#include "PlayerActionTracker.h"
#include "RED4ext/Scripting/Natives/Generated/AI/Command.hpp"
#include "RED4ext/Scripting/Natives/Generated/Vector4.hpp"
#include "RED4ext/Scripting/Natives/entEntityID.hpp"

#include <RedLib.hpp>
#include <clientbound/WorldPacketsClientBound.h>
#include <map>
#include <steam/isteamnetworkingsockets.h>
#include <steam/steamnetworkingtypes.h>

#include <serverbound/WorldPacketsServerBound.h>

class NetworkGameSystem : public Red::IGameSystem
{
private:
    HSteamNetConnection m_hConnection;
    ISteamNetworkingSockets *m_pInterface;
    bool m_hasTriedToConnect = false;
    bool m_hasEnqueuedLoadLastCheckpoint = false;
    Red::Handle<Red::ink::ISystemRequestsHandler> m_systemRequestsHandler;
    bool m_gameRestored = false;
    std::map<uint64_t, RED4ext::ent::EntityID> m_networkedEntitiesLookup;

    // Per-remote-puppet movement bookkeeping (locomotion sync, AI-free): each network update
    // stores only the target pose + the velocity derived from the update interval; a per-frame
    // interpolation moves the puppet kinematically and the locomotion blendgraph is fed the
    // same feature data it normally receives from the movement AI (inputs "locomotion" and
    // "crowd_locomotion", verified against the humanoid.animgraph asset).
    struct MovementState
    {
        RED4ext::Vector4 targetPosition {};
        float targetYaw = 0.0f;
        float targetPitch = 0.0f;        // aim pitch (degrees) from TeleportEntity, drives upper-body LookAt
        RED4ext::Vector4 velocity {};    // world units/s toward target
        float speed = 0.0f;              // m/s magnitude, feeds the anim graph
        float timeSinceUpdate = 0.0f;    // accumulated frame dt since the last packet
        bool hasTarget = false;
        bool idleApplied = false;        // idle anim feed sent since arrival (send once)
        bool weaponDrawn = false;        // remote equip state (EquipItemEntity), gates the aim LookAt
        float lastAimYaw = 999.0f;       // last yaw/pitch applied as LookAt (999 = never applied,
        float lastAimPitch = 999.0f;     // forces the first apply once a weapon is drawn)
        float lastIdleYaw = 999.0f;      // last yaw applied while STANDING (idle path skips
                                         // teleports, so camera turns froze the body facing)
        // D3 lateral-clip unlock (2026-07-29): whether the AnimationControllerComponent
        // SetInputBool calls that make the combat locomotion animset loadable have been sent
        // for this puppet yet (send once — see DriveLocomotionFeed).
        bool animSetupInputsSet = false;
        // Set once per puppet, the first time we resolve its networkedEntityId to an entity
        // handle (eTeleportEntity case) -- lets redscript read the puppet's own networkedEntityId
        // back out (hit-feedback design §5: this mapping does not otherwise exist in redscript,
        // only forward in m_networkedEntitiesLookup here in C++).
        bool networkIdSet = false;
        // Virtual point advancing along the network path at `speed`, independent of the
        // puppet's actual position. Teleport commands always target this point, so AI ticks
        // that skip a command don't accumulate lag (the next executed command lands on the
        // correct current path point).
        RED4ext::Vector4 idealPos {};
        bool idealValid = false;
        // D1 walk-loop driver: the ActionAnimationScriptProxy currently playing the walk
        // anim on this puppet (null while idle) + poll accumulator for clip-end detection.
        RED4ext::Handle<RED4ext::IScriptable> walkAnim;
        float walkAnimPoll = 0.0f;
    };
    std::map<RED4ext::ent::EntityID, MovementState> m_movementState;

    // Equip packets that arrived before their entity finished its async spawn (measured
    // 2026-07-31: the track-start snapshot beats the spawn by design). Keyed by
    // networkedEntityId; the teleport path flushes them once the entity resolves.
    std::map<uint64_t, EquipItemEntity> m_pendingEquips;

    // Health snapshots hit the exact same spawn race as the equip snapshot above -- both are sent
    // from OnStartTrackingEntity right behind SpawnEntity. Same buffer, same flush point.
    std::map<uint64_t, EntityHealth> m_pendingHealth;

    // Last logged threat/shoot status PER SHOOTER, so a status only has to change for that puppet
    // to be logged again. These were `static` locals until 2026-08-07, i.e. one value shared by
    // every shooter in the process -- which made the diagnostic blind to exactly the case it was
    // needed for: a freshly spawned puppet whose status happens to equal the previous puppet's
    // last one logs nothing at all. A bot-harness restart produced 40 minutes of silence that way.
    // A new entity has no entry here, so its first status always reaches the log.
    std::map<uint64_t, int32_t> m_lastThreatStatus;
    std::map<uint64_t, int32_t> m_lastShootStatus;

    // Applies one EquipItemEntity to a resolved puppet: redscript TransactionSystem apply +
    // the movement-state bookkeeping (weaponDrawn, aim LookAt teardown on unequip).
    void ApplyEquipPacket(const Red::Handle<Red::Entity>& entity, RED4ext::ent::EntityID entityId,
                          const EquipItemEntity& equip);
    void ApplyHealthPacket(const Red::Handle<Red::Entity>& entity, const EntityHealth& health);
    std::map<RED4ext::ent::EntityID, RED4ext::Handle<RED4ext::AICommand>> m_LastTeleportCommand;
    float m_TimeSinceLastPlayerPositionSync;

private:
    void OnRegisterUpdates(RED4ext::UpdateRegistrar* aRegistrar) override;
    bool OnGameRestored() override;

private:
    bool ConnectToServer(const std::string& host, uint16_t port);
    static void ConnectionStatusChangedCallback(SteamNetConnectionStatusChangedCallback_t* pInfo);
    void OnNetworkUpdate(RED4ext::FrameInfo& frame_info, RED4ext::JobQueue& job_queue);
    void SetEntityPosition(RED4ext::ent::EntityID entityId, RED4ext::Vector4 worldPosition, float yaw);
    void UpdatePuppetInterpolation(float deltaTime);
    void DriveLocomotionFeed(const Red::Handle<Red::Entity>& entity, MovementState& state);

protected:
    void PollIncomingMessages();
    void TrackPlayerPosition(float deltaTime);

public:
    bool FullyConnected = false;
    Red::Handle<PlayerActionTracker> playerActionTracker = Red::Handle(new PlayerActionTracker());

    /// This is called by Redscript when the connection wasn't established as the UI had loaded the available savegames.
    /// Thus we will _enqueue_ the "LoadLastCheckpoint" call, that Redscript had otherwise done, had we connected fast enough.
    void EnqueueLoadLastCheckpoint(const Red::Handle<RED4ext::ink::ISystemRequestsHandler>& handler)
    {
        m_systemRequestsHandler = handler;
        m_hasEnqueuedLoadLastCheckpoint = true;
    }

    template<typename T>
    bool EnqueueMessage(uint8_t channel_id, T frame);

    /// Called from the plugin load and unload events
    static bool Load();
    /// Called from the plugin load and unload events
    static void Unload();
private:
    RTTI_IMPL_TYPEINFO(NetworkGameSystem);
    RTTI_IMPL_ALLOCATOR();
};

RTTI_DEFINE_CLASS(NetworkGameSystem, {
    RTTI_METHOD(EnqueueLoadLastCheckpoint);
    RTTI_PROPERTY(FullyConnected);
    RTTI_PROPERTY(playerActionTracker);
    RTTI_ALIAS("Cyberverse.Network.Managers.NetworkGameSystem");
});

// TODO: Thing about the concept of having EnqueueMessage public, it causes _this_, at least with templates: We need to
//  expliticly state template invocations for the code to be generated, as otherwise NetworkGameSystem.cpp doesn't know
//  about PlayerActionTracked. Maybe we could also inline the whole EnqueueMessage code, then it will be emited into the
//  relevant caller CU (but that may be more than one for the same packet, making template hell even worse).
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerActionTracked msg);
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerSpawnCar msg);
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerUnmountCar msg);
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerEquipItem msg);
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerShoot msg);
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerHealthUpdate msg);
template bool NetworkGameSystem::EnqueueMessage(uint8_t channel_id, PlayerWasHit msg);

#endif //NETWORKMANAGERCONTROLLER_H
