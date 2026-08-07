#pragma once

#include <cstdint>
#include <cstdio>
#include <limits>
#include <string>
#include <unordered_map>

#include <steam/isteamnetworkingsockets.h>
#include <steam/steamnetworkingsockets.h>

#include <zpp_bits.h>

#include "MessageFrame.h"

#include "Behavior.h"

// One fake client: a GameNetworkingSockets connection plus the Cyberverse protocol
// state machine (Connecting -> Authenticating -> Joining -> Running; terminal: Dead).
class BotClient
{
public:
    enum class State
    {
        Connecting,
        Authenticating,
        Joining,
        Running,
        Dead,
    };

    BotClient(int index, ISteamNetworkingSockets* iface, Behavior behavior);
    ~BotClient();

    bool Connect(const SteamNetworkingIPAddr& address);
    void PollIncomingMessages();
    void SendTick(float dt); // behavior update + PlayerPositionUpdate while Running
    void SendJump();         // PlayerActionTracked(jump) at the current position
    void SendShoot();        // PlayerShoot with the configured weapon at the current position
    void SendEquip();        // PlayerEquipItem drawing the configured weapon
    void Close(const char* reason);

    State GetState() const { return m_state; }
    const std::string& Name() const { return m_name; }
    uint64_t ConsumeTeleportCount()
    {
        const auto count = m_teleportsReceived;
        m_teleportsReceived = 0;
        return count;
    }
    uint64_t ConsumeActionCount()
    {
        const auto count = m_actionsReceived;
        m_actionsReceived = 0;
        return count;
    }
    uint64_t ConsumeSpawnCount()
    {
        const auto count = m_spawnsReceived;
        m_spawnsReceived = 0;
        return count;
    }
    uint64_t ConsumeDespawnCount()
    {
        const auto count = m_despawnsReceived;
        m_despawnsReceived = 0;
        return count;
    }
    uint64_t ConsumeEquipCount()
    {
        const auto count = m_equipsReceived;
        m_equipsReceived = 0;
        return count;
    }
    uint64_t ConsumeShotCount()
    {
        const auto count = m_shotsReceived;
        m_shotsReceived = 0;
        return count;
    }
    uint64_t ConsumeHealthCount()
    {
        const auto count = m_healthUpdatesReceived;
        m_healthUpdatesReceived = 0;
        return count;
    }

    // Damage sync: bots "bleed" from full to empty and back, purely to exercise the health
    // pipeline (report -> server state -> relay -> track-start snapshot) without a running game.
    // 0 disables it, which is the default.
    void SetBleedRate(const float percentPerSecond)
    {
        m_bleedRate = percentPerSecond;
    }

    // Damage sync: the damage-per-hit the bot claims for its weapon. A real client reads this off
    // its own weapon stats, so this is exactly the field a modified client would forge — which
    // makes it the only way to exercise the server's plausibility check. Deliberately accepts
    // absurd, negative and non-finite values; the harness is the attacker in that test.
    void SetDamagePerHit(const float damage)
    {
        m_damagePerHit = damage;
    }

    // Damage sync: aim yaw+pitch at a fixed world point instead of the pitch oscillation.
    // The oscillation exists to make the upper-body LookAt visible in screenshots; for a damage
    // test it is the opposite of what we want, because a shot at +-40 degrees pitch misses by
    // construction. Computed per tick from the bot's own position, so it stays correct while the
    // bot moves.
    void SetAimTarget(const Vector3 target)
    {
        m_aimTarget = target;
        m_hasAimTarget = true;
    }

    // Weapon sync: TweakDBID of the weapon this bot "draws" after joining (0 = unarmed).
    // equipDelay > 0 postpones the draw by that many seconds after entering Running —
    // isolates mid-spawn equip effects from equip-on-initialized-puppet (2026-07-31).
    void SetWeapon(const uint64_t weaponTdbid, const float equipDelay = 0.0f)
    {
        m_weaponTdbid = weaponTdbid;
        m_equipDelay = equipDelay;
    }

    // TweakDBID value for a record name: crc32(name) | (len << 32) — same packing as
    // RED4ext::TweakDBID {hash:u32, length:u8}. Lets the harness compute real record ids.
    static uint64_t TdbId(const char* name);

    // GNS delivers status changes through a single static callback; dispatch by handle.
    static void OnConnectionStatusChanged(SteamNetConnectionStatusChangedCallback_t* info);

private:
    void OnConnected();
    void HandleMessage(const void* data, size_t size);

    // Identical framing to the real client (NetworkGameSystem::EnqueueMessage):
    // zpp_bits-serialize the MessageFrame, then the content, send reliable.
    template <typename T>
    bool Send(T content)
    {
        auto frame = MessageFrame {};
        T::FillMessageFrame(frame);

        auto [data, out] = zpp::bits::data_out();
        if (zpp::bits::failure(out(frame)) || zpp::bits::failure(out(content)))
        {
            std::fprintf(stderr, "[%s] failed to serialize message type %u\n", m_name.c_str(), frame.message_type);
            return false;
        }

        const auto result = m_iface->SendMessageToConnection(
            m_conn, data.data(), static_cast<uint32_t>(data.size()), k_nSteamNetworkingSend_Reliable, nullptr);
        if (result != k_EResultOK)
        {
            std::fprintf(stderr, "[%s] send failed: %d\n", m_name.c_str(), result);
            return false;
        }
        return true;
    }

    int m_index;
    std::string m_name;
    ISteamNetworkingSockets* m_iface;
    HSteamNetConnection m_conn = k_HSteamNetConnection_Invalid;
    State m_state = State::Connecting;
    Behavior m_behavior;
    Pose m_lastPose {};
    uint64_t m_teleportsReceived = 0;
    uint64_t m_actionsReceived = 0;
    uint64_t m_spawnsReceived = 0;
    uint64_t m_despawnsReceived = 0;
    uint64_t m_equipsReceived = 0;
    uint64_t m_shotsReceived = 0;
    uint64_t m_healthUpdatesReceived = 0;
    uint64_t m_weaponTdbid = 0;
    Vector3 m_aimTarget {};
    bool m_hasAimTarget = false;
    float m_bleedRate = 0.0f;      // percent per second, 0 = don't report health at all
    float m_damagePerHit = 20.0f;  // claimed weapon damage; a plausible rifle value by default
    float m_health = 100.0f;
    float m_healthReportTimer = 0.0f;
    float m_equipDelay = 0.0f;   // seconds after Running before the equip is sent
    bool m_equipSent = false;
    float m_elapsed = 0.0f; // running time, drives the armed-bot aim-pitch oscillation

    static std::unordered_map<HSteamNetConnection, BotClient*> s_byConnection;
};
