#pragma once

#include <algorithm>
#include <cmath>
#include <random>

#include "MessageFrame.h"

struct Pose
{
    Vector3 position;
    float yaw; // degrees, like the real client (EulerAngles.Yaw)
    float pitch = 0.0f; // degrees, aim pitch (real client: FPP camera local orientation)
};

// Tick-driven movement pattern for one bot. Produces a Pose per tick.
class Behavior
{
public:
    enum class Pattern
    {
        Circle,
        Random,
        Boundary,
        Static,
        Strafe,
        Backpedal,
    };

    Behavior(const Pattern pattern, const Vector3 center, const int botIndex, const float boundaryDistance = 440.0f)
        : m_pattern(pattern), m_center(center),
          m_radius(5.0f + static_cast<float>(botIndex)),
          // Strafe: SHARED facing for every bot (a straight line of bots all facing the same
          // way is far easier to screenshot-compare than bots at different angles/facings
          // around a circle — verification feedback 2026-07-25). All other patterns keep the
          // per-bot angular offset so they don't spawn inside each other.
          m_angle((pattern == Pattern::Strafe || pattern == Pattern::Backpedal)
                      ? 0.0f
                      : static_cast<float>(botIndex) * 0.7f),
          m_boundaryDistance(boundaryDistance),
          m_rng(1337 + botIndex)
    {
        if (pattern == Pattern::Boundary)
        {
            // Spawn ON the oscillation distance — spawning near the center first would let the
            // server track us before we move out, corrupting the spawn/despawn counters.
            m_position = { m_center.x + m_boundaryDistance * std::cos(m_angle),
                           m_center.y + m_boundaryDistance * std::sin(m_angle), m_center.z };
        }
        else if (pattern == Pattern::Strafe || pattern == Pattern::Backpedal)
        {
            // Line formation: bots spread along X, fixed distance from center along Y, all
            // facing the same yaw — a clean row instead of bots circling at different angles.
            constexpr float LINE_SPACING = 2.5f;
            m_lineAnchor = { m_center.x + (static_cast<float>(botIndex) - 1.5f) * LINE_SPACING,
                             m_center.y + 6.0f, m_center.z };
            m_position = m_lineAnchor;
        }
        else
        {
            m_position = PositionOnCircle();
        }
        m_heading = m_angle;
    }

    // Vault Hunters: follow a moving point (the host, from "vh.where").
    void SetCenter(const Vector3 center)
    {
        m_center = center;
    }

    Pose Spawn() const
    {
        return { m_position, 0.0f };
    }

    Pose Tick(const float dt)
    {
        switch (m_pattern)
        {
        case Pattern::Circle:
            return TickCircle(dt);
        case Pattern::Boundary:
            return TickBoundary(dt);
        case Pattern::Static:
            return { m_position, std::fmod(m_heading * 57.29578f, 360.0f) };
        case Pattern::Strafe:
            return TickStrafe(dt);
        case Pattern::Backpedal:
            return TickBackpedal(dt);
        case Pattern::Random:
        default:
            return TickRandom(dt);
        }
    }

private:
    static constexpr float WALK_SPEED = 2.0f;    // m/s
    static constexpr float MAX_WANDER = 30.0f;   // m around center (random pattern)

    Vector3 PositionOnCircle() const
    {
        return { m_center.x + m_radius * std::cos(m_angle), m_center.y + m_radius * std::sin(m_angle), m_center.z };
    }

    Pose TickCircle(const float dt)
    {
        m_angle += (WALK_SPEED / m_radius) * dt;
        m_position = PositionOnCircle();
        // yaw = tangent of the circle, converted to degrees
        const float yaw = (m_angle + 1.5707963f) * 57.29578f;
        return { m_position, std::fmod(yaw, 360.0f) };
    }

    Pose TickRandom(const float dt)
    {
        m_timeToNewHeading -= dt;
        if (m_timeToNewHeading <= 0.0f)
        {
            std::uniform_real_distribution<float> angleDist(0.0f, 6.2831853f);
            std::uniform_real_distribution<float> durationDist(2.0f, 5.0f);
            m_heading = angleDist(m_rng);
            m_timeToNewHeading = durationDist(m_rng);
        }

        // steer back once we stray too far from the center
        const float dx = m_position.x - m_center.x;
        const float dy = m_position.y - m_center.y;
        if (dx * dx + dy * dy > MAX_WANDER * MAX_WANDER)
        {
            m_heading = std::atan2(-dy, -dx);
        }

        m_position.x += std::cos(m_heading) * WALK_SPEED * dt;
        m_position.y += std::sin(m_heading) * WALK_SPEED * dt;
        return { m_position, std::fmod(m_heading * 57.29578f, 360.0f) };
    }

    // Oscillates radially between boundaryDistance-22.5 and boundaryDistance+22.5 around the
    // center — with the default 440 +/- 22.5 that is 417.5..462.5, i.e. crossing the enter
    // radius (425) but never the exit radius (470): the server must spawn us once at the
    // observer and never despawn (hysteresis verification).
    Pose TickBoundary(const float dt)
    {
        m_boundaryPhase += (WALK_SPEED / 22.5f) * dt;
        const float dist = m_boundaryDistance + 22.5f * std::sin(m_boundaryPhase);
        m_position = { m_center.x + dist * std::cos(m_angle), m_center.y + dist * std::sin(m_angle), m_center.z };
        const float yaw = (m_angle + (std::cos(m_boundaryPhase) >= 0.0f ? 0.0f : 3.1415927f)) * 57.29578f;
        return { m_position, std::fmod(yaw, 360.0f) };
    }

    // Sideways oscillation at fixed facing: position pendulums on the axis perpendicular to
    // the (fixed) view yaw — the remote puppet must play strafe cycles, not turn (Task 6
    // Step 3, 8-way direction verification).
    Pose TickStrafe(const float dt)
    {
        // Oscillate around THIS bot's own line-formation anchor (m_lineAnchor, set once at
        // spawn) — not the shared m_center. Using m_center here was the bug that collapsed
        // all bots onto the same spot after the first tick (found 2026-07-25: the diag log
        // showed every bot at an identical position once strafing started).
        m_boundaryPhase += (WALK_SPEED / 3.0f) * dt;
        const float offset = 3.0f * std::sin(m_boundaryPhase);
        const float viewYawRad = m_angle; // fixed per-bot facing
        m_position = { m_lineAnchor.x + offset * std::cos(viewYawRad + 1.5707963f),
                       m_lineAnchor.y + offset * std::sin(viewYawRad + 1.5707963f), m_lineAnchor.z };
        return { m_position, std::fmod(viewYawRad * 57.29578f, 360.0f) };
    }

    // Oscillates ALONG the (fixed) view yaw instead of across it: half the cycle the bot
    // walks forwards (direction 0 deg), the other half backwards (direction 180 deg) — while
    // never turning. Diagnostic counterpart to TickStrafe: walk_0 and walk_180 live in the
    // relaxed animsets, the lateral walk_090/walk_270 only in the combat set, so this pattern
    // answers whether a clip fails because of its NAME or because its SET is not loaded
    // (2026-07-28, D3 Stufe 4).
    // Observer note: the line anchor sits 6 m along +Y, and motion runs along +/-X, so from
    // the default --center (= the player's own position) the bot is seen side-on with its
    // walk direction crossing the view. No center offset needed, unlike Strafe.
    Pose TickBackpedal(const float dt)
    {
        m_boundaryPhase += (WALK_SPEED / 3.0f) * dt;
        const float offset = 3.0f * std::sin(m_boundaryPhase);
        const float viewYawRad = m_angle; // fixed facing — the bot never turns
        m_position = { m_lineAnchor.x + offset * std::cos(viewYawRad),
                       m_lineAnchor.y + offset * std::sin(viewYawRad), m_lineAnchor.z };
        return { m_position, std::fmod(viewYawRad * 57.29578f, 360.0f) };
    }

    Pattern m_pattern;
    Vector3 m_center;
    float m_radius;
    float m_angle;
    float m_boundaryDistance;
    float m_boundaryPhase = 0.0f;
    Vector3 m_position {};
    Vector3 m_lineAnchor {}; // Strafe pattern: this bot's fixed line-formation spot
    float m_heading = 0.0f;
    float m_timeToNewHeading = 0.0f;
    std::mt19937 m_rng;
};
