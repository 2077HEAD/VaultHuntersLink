#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include <steam/isteamnetworkingsockets.h>
#include <steam/isteamnetworkingutils.h>
#include <steam/steamnetworkingsockets.h>

#include "Behavior.h"

#ifndef _WIN32
#define sscanf_s sscanf // MSVC-only name; the harness also builds on Linux (VH co-op CI)
#endif
#include "BotClient.h"

namespace
{
std::atomic<bool> g_stop = false;

void OnSignal(int)
{
    g_stop = true;
}

struct Options
{
    std::string server = "127.0.0.1";
    uint16_t port = 1337;
    int count = 8;
    Behavior::Pattern pattern = Behavior::Pattern::Circle;
    Vector3 center = { -2102.0f, 446.0f, 36.0f }; // verified Stage-A player position
    float hz = 10.0f;
    float jumpEvery = 0.0f; // seconds between jump actions per bot; 0 = never
    float boundaryDistance = 440.0f; // oscillation center distance for the boundary pattern
    uint64_t weaponTdbid = 0; // weapon each bot draws after joining; 0 = unarmed
    float shootEvery = 0.0f;  // seconds between PlayerShoot per bot; 0 = never (needs --weapon)
    float equipDelay = 0.0f;  // seconds after join before drawing the weapon; 0 = immediately
    float bleedRate = 0.0f;   // percent health lost per second; 0 = don't report health at all
    float damagePerHit = 20.0f;  // claimed weapon damage per shot; forge it to test the server cap
    Vector3 aimTarget {};     // world point every bot aims at (yaw+pitch), instead of oscillating
    bool hasAimTarget = false;
    float scriptEvery = 0.0f;   // Vault Hunters co-op: seconds between test script events; 0 = never
    uint64_t avatarTdbid = 0;   // Vault Hunters co-op: class avatar record sent after joining
    float avatarDelay = 0.0f;   // seconds after everyone is running before the avatar is sent
};

bool ParseArgs(const int argc, char** argv, Options& options)
{
    for (int i = 1; i < argc; i++)
    {
        const std::string arg = argv[i];
        const auto next = [&]() -> const char* {
            if (i + 1 >= argc)
            {
                std::fprintf(stderr, "missing value for %s\n", arg.c_str());
                return nullptr;
            }
            return argv[++i];
        };

        if (arg == "--server")
        {
            const auto value = next();
            if (!value) return false;
            options.server = value;
        }
        else if (arg == "--port")
        {
            const auto value = next();
            if (!value) return false;
            options.port = static_cast<uint16_t>(std::atoi(value));
        }
        else if (arg == "--count")
        {
            const auto value = next();
            if (!value) return false;
            options.count = std::atoi(value);
        }
        else if (arg == "--pattern")
        {
            const auto value = next();
            if (!value) return false;
            if (std::strcmp(value, "circle") == 0)
            {
                options.pattern = Behavior::Pattern::Circle;
            }
            else if (std::strcmp(value, "random") == 0)
            {
                options.pattern = Behavior::Pattern::Random;
            }
            else if (std::strcmp(value, "boundary") == 0)
            {
                options.pattern = Behavior::Pattern::Boundary;
            }
            else if (std::strcmp(value, "static") == 0)
            {
                options.pattern = Behavior::Pattern::Static;
            }
            else if (std::strcmp(value, "strafe") == 0)
            {
                options.pattern = Behavior::Pattern::Strafe;
            }
            else if (std::strcmp(value, "backpedal") == 0)
            {
                options.pattern = Behavior::Pattern::Backpedal;
            }
            else
            {
                std::fprintf(stderr, "unknown pattern \"%s\" (circle|random|boundary|static|strafe|backpedal)\n", value);
                return false;
            }
        }
        else if (arg == "--center")
        {
            const auto value = next();
            if (!value) return false;
            if (sscanf_s(value, "%f,%f,%f", &options.center.x, &options.center.y, &options.center.z) != 3)
            {
                std::fprintf(stderr, "invalid --center \"%s\", expected x,y,z\n", value);
                return false;
            }
        }
        else if (arg == "--hz")
        {
            const auto value = next();
            if (!value) return false;
            options.hz = static_cast<float>(std::atof(value));
        }
        else if (arg == "--jump-every")
        {
            const auto value = next();
            if (!value) return false;
            options.jumpEvery = static_cast<float>(std::atof(value));
        }
        else if (arg == "--distance")
        {
            const auto value = next();
            if (!value) return false;
            options.boundaryDistance = static_cast<float>(std::atof(value));
        }
        else if (arg == "--weapon")
        {
            const auto value = next();
            if (!value) return false;
            // Numeric (decimal/0x-hex) TweakDBID value, or a record name like
            // "Items.Preset_Ajax_Default" which gets hashed the way the RED engine does.
            char* end = nullptr;
            options.weaponTdbid = std::strtoull(value, &end, 0);
            if (end == value || *end != '\0')
            {
                options.weaponTdbid = BotClient::TdbId(value);
                std::printf("weapon record \"%s\" -> tdbid %llu\n", value,
                            static_cast<unsigned long long>(options.weaponTdbid));
            }
        }
        else if (arg == "--script-every")
        {
            const auto value = next();
            if (!value) return false;
            options.scriptEvery = static_cast<float>(std::atof(value));
        }
        else if (arg == "--avatar")
        {
            const auto value = next();
            if (!value) return false;
            options.avatarTdbid = BotClient::TdbId(value);
            std::printf("avatar record \"%s\" -> tdbid %llu\n", value,
                        static_cast<unsigned long long>(options.avatarTdbid));
        }
        else if (arg == "--avatar-delay")
        {
            const auto value = next();
            if (!value) return false;
            options.avatarDelay = static_cast<float>(std::atof(value));
        }
        else if (arg == "--shoot-every")
        {
            const auto value = next();
            if (!value) return false;
            options.shootEvery = static_cast<float>(std::atof(value));
        }
        else if (arg == "--aim-at")
        {
            const auto value = next();
            if (!value) return false;
            if (sscanf_s(value, "%f,%f,%f", &options.aimTarget.x, &options.aimTarget.y, &options.aimTarget.z) != 3)
            {
                std::fprintf(stderr, "invalid --aim-at \"%s\", expected x,y,z\n", value);
                return false;
            }
            options.hasAimTarget = true;
        }
        else if (arg == "--damage")
        {
            const auto value = next();
            if (!value) return false;
            options.damagePerHit = static_cast<float>(std::atof(value));
        }
        else if (arg == "--bleed")
        {
            const auto value = next();
            if (!value) return false;
            options.bleedRate = static_cast<float>(std::atof(value));
        }
        else if (arg == "--equip-delay")
        {
            const auto value = next();
            if (!value) return false;
            options.equipDelay = static_cast<float>(std::atof(value));
        }
        else
        {
            std::fprintf(stderr,
                         "usage: bot-harness [--server 127.0.0.1] [--port 1337] [--count 8]\n"
                         "                   [--pattern circle|random|boundary|static|strafe|backpedal] [--center x,y,z] [--hz 10]\n"
                         "                   [--jump-every <seconds>] [--distance <m, boundary pattern>]\n"
                         "                   [--weapon <tdbid-u64 | record name, e.g. Items.Preset_Ajax_Default>]\n"
                         "                   [--shoot-every <seconds, needs --weapon>] [--equip-delay <seconds>]\n"
                         "                   [--damage <claimed damage per hit, default 20; forge it to test the server cap>]\n"
                         "                   [--bleed <percent per second, exercises the health pipeline>]\n"
                         "                   [--aim-at x,y,z  aim yaw+pitch at a world point instead of oscillating]\n");
            return false;
        }
    }

    return options.count > 0 && options.hz > 0.0f;
}

const char* StateName(const BotClient::State state)
{
    switch (state)
    {
    case BotClient::State::Connecting: return "connecting";
    case BotClient::State::Authenticating: return "authenticating";
    case BotClient::State::Joining: return "joining";
    case BotClient::State::Running: return "running";
    case BotClient::State::Dead: return "DEAD";
    }
    return "?";
}
} // namespace

int main(const int argc, char** argv)
{
    // Stats/diagnostics get tailed live from a redirected log; a pipe-buffered stdout
    // loses everything on a hard kill (observed 2026-07-31: empty logs after Stop-Process).
    setvbuf(stdout, nullptr, _IONBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);

    Options options;
    if (!ParseArgs(argc, argv, options))
    {
        return 2;
    }

    std::signal(SIGINT, OnSignal);

    if (SteamDatagramErrMsg errMsg; !GameNetworkingSockets_Init(nullptr, errMsg))
    {
        std::fprintf(stderr, "could not initialize GameNetworkingSockets: %s\n", errMsg);
        return 1;
    }

    ISteamNetworkingSockets* iface = SteamNetworkingSockets();

    char connectionString[64];
    std::snprintf(connectionString, sizeof(connectionString), "%s:%u", options.server.c_str(), options.port);
    SteamNetworkingIPAddr address = {};
    if (!address.ParseString(connectionString))
    {
        std::fprintf(stderr, "failed to parse server address \"%s\"\n", connectionString);
        return 2;
    }

    const char* patternName = options.pattern == Behavior::Pattern::Circle     ? "circle"
                              : options.pattern == Behavior::Pattern::Boundary ? "boundary"
                              : options.pattern == Behavior::Pattern::Static   ? "static"
                              : options.pattern == Behavior::Pattern::Strafe   ? "strafe"
                              : options.pattern == Behavior::Pattern::Backpedal ? "backpedal"
                                                                               : "random";
    std::printf("bot-harness: %d bot(s) -> %s, pattern %s, %.0f Hz, center (%.1f, %.1f, %.1f)\n", options.count,
                connectionString, patternName, options.hz, options.center.x, options.center.y, options.center.z);

    std::vector<std::unique_ptr<BotClient>> bots;
    for (int i = 0; i < options.count; i++)
    {
        auto bot = std::make_unique<BotClient>(i, iface,
                                               Behavior(options.pattern, options.center, i, options.boundaryDistance));
        bot->SetWeapon(options.weaponTdbid, options.equipDelay);
        bot->SetBleedRate(options.bleedRate);
        bot->SetDamagePerHit(options.damagePerHit);
        if (options.hasAimTarget)
        {
            bot->SetAimTarget(options.aimTarget);
        }
        bot->Connect(address);
        bots.push_back(std::move(bot));
    }

    const auto sendInterval = 1.0f / options.hz;
    float sendAccumulator = 0.0f;
    float statsAccumulator = 0.0f;
    float jumpAccumulator = 0.0f;
    float shootAccumulator = 0.0f;
    float scriptAccumulator = 0.0f;
    bool avatarSent = false;
    float avatarWait = 0.0f;
    auto lastTime = std::chrono::steady_clock::now();

    while (!g_stop)
    {
        const auto now = std::chrono::steady_clock::now();
        const float dt = std::chrono::duration<float>(now - lastTime).count();
        lastTime = now;

        iface->RunCallbacks();
        for (const auto& bot : bots)
        {
            bot->PollIncomingMessages();
        }

        sendAccumulator += dt;
        if (sendAccumulator >= sendInterval)
        {
            for (const auto& bot : bots)
            {
                bot->SendTick(sendAccumulator);
            }
            sendAccumulator = 0.0f;
        }

        if (options.jumpEvery > 0.0f)
        {
            jumpAccumulator += dt;
            if (jumpAccumulator >= options.jumpEvery)
            {
                jumpAccumulator = 0.0f;
                for (const auto& bot : bots)
                {
                    bot->SendJump();
                }
            }
        }

        if (options.shootEvery > 0.0f)
        {
            shootAccumulator += dt;
            if (shootAccumulator >= options.shootEvery)
            {
                shootAccumulator = 0.0f;
                for (const auto& bot : bots)
                {
                    bot->SendShoot();
                }
            }
        }

        if (options.avatarTdbid != 0 && !avatarSent)
        {
            bool allRunning = true;
            for (const auto& bot : bots)
            {
                allRunning = allRunning && bot->GetState() == BotClient::State::Running;
            }
            if (allRunning)
            {
                avatarWait += dt;
            }
            if (allRunning && avatarWait >= options.avatarDelay)
            {
                avatarSent = true;
                for (const auto& bot : bots)
                {
                    bot->SendAvatar(options.avatarTdbid);
                }
            }
        }

        if (options.scriptEvery > 0.0f)
        {
            scriptAccumulator += dt;
            if (scriptAccumulator >= options.scriptEvery)
            {
                scriptAccumulator = 0.0f;
                for (const auto& bot : bots)
                {
                    char text[64];
                    std::snprintf(text, sizeof(text), "hello from %s", bot->Name().c_str());
                    bot->SendScriptEvent("vh.ping", text, 1.5f);
                }
            }
        }

        statsAccumulator += dt;
        if (statsAccumulator >= 1.0f)
        {
            statsAccumulator = 0.0f;

            int running = 0, dead = 0;
            uint64_t teleports = 0, actions = 0, spawns = 0, despawns = 0, equips = 0, shots = 0, healths = 0, hitConfirms = 0;
            for (const auto& bot : bots)
            {
                if (bot->GetState() == BotClient::State::Running) running++;
                if (bot->GetState() == BotClient::State::Dead) dead++;
                teleports += bot->ConsumeTeleportCount();
                actions += bot->ConsumeActionCount();
                spawns += bot->ConsumeSpawnCount();
                despawns += bot->ConsumeDespawnCount();
                equips += bot->ConsumeEquipCount();
                shots += bot->ConsumeShotCount();
                healths += bot->ConsumeHealthCount();
                hitConfirms += bot->ConsumeHitConfirmCount();
            }
            std::printf("stats: %d/%zu running, %d dead, %llu teleports, %llu actions, %llu spawns, %llu despawns, %llu equips, %llu shots, %llu health received/s, %llu hit confirms\n",
                        running, bots.size(), dead, static_cast<unsigned long long>(teleports),
                        static_cast<unsigned long long>(actions), static_cast<unsigned long long>(spawns),
                        static_cast<unsigned long long>(despawns), static_cast<unsigned long long>(equips),
                        static_cast<unsigned long long>(shots), static_cast<unsigned long long>(healths),
                        static_cast<unsigned long long>(hitConfirms));

            if (dead == static_cast<int>(bots.size()))
            {
                std::fprintf(stderr, "all bots dead, exiting\n");
                GameNetworkingSockets_Kill();
                return 1;
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(15));
    }

    std::printf("shutting down, closing %zu connection(s)\n", bots.size());
    for (const auto& bot : bots)
    {
        bot->Close("harness shutdown");
    }
    iface->RunCallbacks();

    GameNetworkingSockets_Kill();
    return 0;
}
