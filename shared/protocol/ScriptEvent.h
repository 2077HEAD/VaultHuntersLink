#pragma once

#include <cstdint>

#include <zpp_bits.h>

// A generic, game-mode-agnostic event that the redscript layer can send to the other players
// (Vault Hunters co-op, 2026-10-13). The native layers never interpret it: they only move it.
// This is the one packet that lets gameplay features (classes, shared encounters, XP share,
// party state, ...) be written entirely in redscript and C# without touching the C++ client or
// the native server again -- adding a typed packet costs seven edits across four projects.
//
// Layout is fixed-size and trivially copyable on purpose: the native server hands packets to C#
// with a plain memcpy (GameServer::AddToRecvQueue) and C# reads them with Marshal.PtrToStructure,
// so the struct must have the same layout on both sides. 6 x u64 + 8 x f32 + 128 x char = 208
// bytes, every member naturally aligned, no padding anywhere.
//
// Field meaning is defined per channel by whoever owns the channel (see the redscript side).
struct ScriptEventData
{
    uint64_t channel; // FNV-1a 64 hash of the channel name, i.e. the CName hash ("vh.class", ...)
    uint64_t sender;  // networkedEntityId of the sender's puppet. Set by the SERVER; clients send 0.
    uint64_t target;  // 0 = every other player; otherwise the networkedEntityId of one player's puppet.
    uint64_t u0;
    uint64_t u1;
    uint64_t u2;
    float f[8];
    char text[128]; // NUL-terminated UTF-8, truncated to 127 bytes by the sender

    // zpp_bits counts aggregate members via brace initialisation, which brace elision breaks for
    // C arrays (it sees 6 + 8 + 128 "members" and fails to compile). State the count explicitly.
    using serialize = zpp::bits::members<8>;
};

static_assert(sizeof(ScriptEventData) == 208, "ScriptEventData layout must match the C# struct");

// FNV-1a 64 -- the same hash the game uses for CNames, so a channel written as n"vh.class" in
// redscript and as "vh.class" in C++/C# lands on the same number.
constexpr uint64_t ScriptEventChannel(const char* name)
{
    uint64_t hash = 0xCBF29CE484222325ull;
    while (*name)
    {
        hash ^= static_cast<uint8_t>(*name++);
        hash *= 0x100000001B3ull;
    }
    return hash;
}
