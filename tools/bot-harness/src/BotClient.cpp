#include "BotClient.h"

#include <cmath>

#include "serverbound/AuthPacketsServerBound.h"
#include "serverbound/WorldPacketsServerBound.h"
#include "clientbound/AuthPacketsClientBound.h"
#include "clientbound/WorldPacketsClientBound.h"

std::unordered_map<HSteamNetConnection, BotClient*> BotClient::s_byConnection;

uint64_t BotClient::TdbId(const char* name)
{
    // Standard reflected CRC-32 (poly 0xEDB88320), the hash the RED engine uses for TweakDBIDs.
    uint32_t crc = 0xFFFFFFFFu;
    size_t len = 0;
    for (const char* p = name; *p != '\0'; ++p, ++len)
    {
        crc ^= static_cast<uint8_t>(*p);
        for (int bit = 0; bit < 8; ++bit)
        {
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
        }
    }
    crc ^= 0xFFFFFFFFu;
    return static_cast<uint64_t>(crc) | (static_cast<uint64_t>(len & 0xFF) << 32);
}

BotClient::BotClient(const int index, ISteamNetworkingSockets* iface, Behavior behavior)
    : m_index(index), m_iface(iface), m_behavior(behavior)
{
    char name[16];
    std::snprintf(name, sizeof(name), "Bot%02d", index + 1);
    m_name = name;
}

BotClient::~BotClient()
{
    Close("destroyed");
}

bool BotClient::Connect(const SteamNetworkingIPAddr& address)
{
    SteamNetworkingConfigValue_t opt = {};
    opt.SetPtr(k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,
               reinterpret_cast<void*>(OnConnectionStatusChanged));

    m_conn = m_iface->ConnectByIPAddress(address, 1, &opt);
    if (m_conn == k_HSteamNetConnection_Invalid)
    {
        std::fprintf(stderr, "[%s] could not create connection\n", m_name.c_str());
        m_state = State::Dead;
        return false;
    }

    s_byConnection[m_conn] = this;
    return true;
}

void BotClient::OnConnectionStatusChanged(SteamNetConnectionStatusChangedCallback_t* info)
{
    const auto it = s_byConnection.find(info->m_hConn);
    if (it == s_byConnection.end())
    {
        return;
    }
    BotClient* bot = it->second;

    switch (info->m_info.m_eState)
    {
    case k_ESteamNetworkingConnectionState_Connected:
        bot->OnConnected();
        break;

    case k_ESteamNetworkingConnectionState_ClosedByPeer:
    case k_ESteamNetworkingConnectionState_ProblemDetectedLocally:
        std::fprintf(stderr, "[%s] connection lost (%d): %s\n", bot->m_name.c_str(), info->m_info.m_eState,
                     info->m_info.m_szEndDebug);
        bot->Close("connection lost");
        break;

    default:
        break; // Connecting/FindingRoute etc. — nothing to do
    }
}

void BotClient::OnConnected()
{
    std::printf("[%s] socket connected, authenticating\n", m_name.c_str());

    InitAuthServerBound auth = {};
    auth.username = m_name;
    auth.protocol_version = PROTOCOL_VERSION_CURRENT;
    if (Send(auth))
    {
        m_state = State::Authenticating;
    }
}

void BotClient::PollIncomingMessages()
{
    if (m_state == State::Dead || m_conn == k_HSteamNetConnection_Invalid)
    {
        return;
    }

    while (true)
    {
        ISteamNetworkingMessage* msg = nullptr;
        const auto numMsgs = m_iface->ReceiveMessagesOnConnection(m_conn, &msg, 1);
        if (numMsgs == 0)
        {
            break;
        }
        if (numMsgs < 0)
        {
            std::fprintf(stderr, "[%s] error polling messages: %d\n", m_name.c_str(), numMsgs);
            return;
        }

        HandleMessage(msg->GetData(), msg->GetSize());
        msg->Release();
    }
}

void BotClient::HandleMessage(const void* data, const size_t size)
{
    auto [buffer, in] = zpp::bits::data_in();
    const auto begin = static_cast<const std::byte*>(data);
    buffer.assign(begin, begin + size);

    MessageFrame frame = {};
    if (zpp::bits::failure(in(frame)))
    {
        std::fprintf(stderr, "[%s] faulty packet\n", m_name.c_str());
        return;
    }

    switch (frame.message_type)
    {
    case EINIT_AUTH_RESULT:
    {
        AuthResultClientBound result = {};
        if (zpp::bits::failure(in(result)))
        {
            std::fprintf(stderr, "[%s] faulty packet: AuthResultClientBound\n", m_name.c_str());
            return;
        }

        if (result.auth_result == EAuthResult_Ok)
        {
            const auto [position, yaw, pitch] = m_behavior.Spawn();
            std::printf("[%s] login accepted, joining world at (%.1f, %.1f, %.1f)\n", m_name.c_str(), position.x,
                        position.y, position.z);

            PlayerJoinWorld join = {};
            join.position = position;
            if (Send(join))
            {
                m_state = State::Running;

                // Weapon sync: draw the configured weapon after joining (immediately, or after
                // m_equipDelay seconds — see SendTick). Same reliable stream as the join packet,
                // so the server sees the puppet first.
                if (m_weaponTdbid != 0 && m_equipDelay <= 0.0f)
                {
                    SendEquip();
                }
            }
        }
        else
        {
            std::fprintf(stderr, "[%s] login rejected: %d (protocol %u vs server %u)\n", m_name.c_str(),
                         result.auth_result, PROTOCOL_VERSION_CURRENT, result.protocol_version);
            Close("auth rejected");
        }
    }
    break;

    case eSpawnEntity:
    {
        SpawnEntity spawn = {};
        if (zpp::bits::failure(in(spawn)))
        {
            std::fprintf(stderr, "[%s] faulty packet: SpawnEntity\n", m_name.c_str());
            return;
        }
        m_spawnsReceived++;
        std::printf("[%s] peer entity spawned: networkId %llu (record %llu) at (%.1f, %.1f, %.1f)\n", m_name.c_str(),
                    static_cast<unsigned long long>(spawn.networkedEntityId),
                    static_cast<unsigned long long>(spawn.recordId), spawn.spawnPosition.x, spawn.spawnPosition.y,
                    spawn.spawnPosition.z);
    }
    break;

    case eTeleportEntity:
    {
        TeleportEntity teleport = {};
        if (zpp::bits::failure(in(teleport)))
        {
            std::fprintf(stderr, "[%s] faulty packet: TeleportEntity\n", m_name.c_str());
            return;
        }
        // counted, not logged — 8 bots x 7 peers x 10 Hz would flood the console
        m_teleportsReceived++;
    }
    break;

    case eEntityAction:
    {
        EntityAction entityAction = {};
        if (zpp::bits::failure(in(entityAction)))
        {
            std::fprintf(stderr, "[%s] faulty packet: EntityAction\n", m_name.c_str());
            return;
        }
        m_actionsReceived++;
    }
    break;

    case eDestroyEntity:
    {
        DestroyEntity destroy = {};
        if (zpp::bits::failure(in(destroy)))
        {
            std::fprintf(stderr, "[%s] faulty packet: DestroyEntity\n", m_name.c_str());
            return;
        }
        m_despawnsReceived++;
        std::printf("[%s] peer entity destroyed: networkId %llu\n", m_name.c_str(),
                    static_cast<unsigned long long>(destroy.networkedEntityId));
    }
    break;

    case eEntityShoot:
    {
        EntityShoot shot = {};
        if (zpp::bits::failure(in(shot)))
        {
            std::fprintf(stderr, "[%s] faulty packet: EntityShoot\n", m_name.c_str());
            return;
        }
        // counted, not logged — a shooting crowd would flood the console
        m_shotsReceived++;
    }
    break;

    case eEquipItemEntity:
    {
        EquipItemEntity equip = {};
        if (zpp::bits::failure(in(equip)))
        {
            std::fprintf(stderr, "[%s] faulty packet: EquipItemEntity\n", m_name.c_str());
            return;
        }
        m_equipsReceived++;
        std::printf("[%s] peer equip: entity %llu slot %llu item %llu unequip=%d\n", m_name.c_str(),
                    static_cast<unsigned long long>(equip.networkedEntityId),
                    static_cast<unsigned long long>(equip.slot),
                    static_cast<unsigned long long>(equip.itemId), equip.isUnequipping ? 1 : 0);
    }
    break;

    case eEntityHealth:
    {
        EntityHealth health = {};
        if (zpp::bits::failure(in(health)))
        {
            std::fprintf(stderr, "[%s] faulty packet: EntityHealth\n", m_name.c_str());
            return;
        }
        m_healthUpdatesReceived++;
        std::printf("[%s] peer health: entity %llu %.1f%% dead=%d\n", m_name.c_str(),
                    static_cast<unsigned long long>(health.networkedEntityId), health.healthPercent,
                    health.isDead ? 1 : 0);
    }
    break;

    default:
        break;
    }
}

void BotClient::SendTick(const float dt)
{
    if (m_state != State::Running)
    {
        return;
    }

    m_lastPose = m_behavior.Tick(dt);

    // Armed bots oscillate their aim pitch (+/-40 deg, ~6.3 s period) so the client-side
    // upper-body LookAt has something visible to track in screenshot bursts (Task 8).
    m_elapsed += dt;
    if (m_weaponTdbid != 0 && !m_equipSent && m_equipDelay > 0.0f && m_elapsed >= m_equipDelay)
    {
        SendEquip();
    }
    if (m_hasAimTarget)
    {
        // Same yaw convention as the client's AimTargetFor: 0 = +Y, counter-clockwise positive,
        // so forward = (-sin(yaw), cos(yaw)). Inverting that gives yaw = atan2(-dx, dy).
        const float dx = m_aimTarget.x - m_lastPose.position.x;
        const float dy = m_aimTarget.y - m_lastPose.position.y;
        const float dz = m_aimTarget.z - m_lastPose.position.z;
        constexpr float RAD2DEG = 57.2957795f;
        m_lastPose.yaw = std::atan2(-dx, dy) * RAD2DEG;
        const float horizontal = std::sqrt(dx * dx + dy * dy);
        m_lastPose.pitch = horizontal > 0.001f ? std::atan2(dz, horizontal) * RAD2DEG : 0.0f;
    }
    else if (m_weaponTdbid != 0)
    {
        m_lastPose.pitch = 40.0f * std::sin(m_elapsed);
    }

    const PlayerPositionUpdate update = { m_lastPose.position, m_lastPose.yaw, m_lastPose.pitch };
    Send(update);

    if (m_bleedRate > 0.0f)
    {
        m_health -= m_bleedRate * dt;
        if (m_health <= 0.0f)
        {
            m_health = 100.0f; // wrap rather than stay dead, so a long run keeps exercising the path
        }
        // Reported at 2 Hz regardless of the tick rate: health is state, and the real client
        // rate-limits it too (0.5 percent threshold in the redscript listener).
        m_healthReportTimer += dt;
        if (m_healthReportTimer >= 0.5f)
        {
            m_healthReportTimer = 0.0f;
            PlayerHealthUpdate health = {};
            health.healthPercent = m_health;
            health.isDead = false;
            Send(health);
        }
    }
}

void BotClient::SendJump()
{
    if (m_state != State::Running)
    {
        return;
    }

    PlayerActionTracked action = {};
    action.action = eACTION_JUMP;
    action.worldTransform = m_lastPose.position;
    Send(action);
}

void BotClient::SendEquip()
{
    PlayerEquipItem equip = {};
    equip.slot = TdbId("AttachmentSlots.WeaponRight");
    equip.itemId = m_weaponTdbid;
    equip.isWeapon = true;
    equip.isUnequipping = false;
    if (Send(equip))
    {
        m_equipSent = true;
        std::printf("[%s] drew weapon %llu (%.0fs after join)\n", m_name.c_str(),
                    static_cast<unsigned long long>(m_weaponTdbid), m_elapsed);
    }
}

void BotClient::SendShoot()
{
    if (m_state != State::Running || m_weaponTdbid == 0)
    {
        return;
    }

    PlayerShoot shoot = {};
    shoot.itemIdWeapon = m_weaponTdbid;
    shoot.startPoint = m_lastPose.position;
    shoot.charge = 1.0f;
    Send(shoot);
}

void BotClient::Close(const char* reason)
{
    if (m_conn != k_HSteamNetConnection_Invalid)
    {
        m_iface->CloseConnection(m_conn, 0, reason, false);
        s_byConnection.erase(m_conn);
        m_conn = k_HSteamNetConnection_Invalid;
    }
    m_state = State::Dead;
}
