using System.Runtime.InteropServices;
using Cyberverse.Server.NativeLayer.Protocol.Common;

namespace Cyberverse.Server.NativeLayer.Protocol.Serverbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct PlayerShoot
{
    public ulong itemIdWeapon;
    public Vector3 startPoint;
    public float charge;
    /// <summary>
    /// Weapon damage per hit, measured on the shooter's own weapon. Only the shooter's machine
    /// has real rolled stats for it; everywhere else it is an NPC puppet's item with none.
    /// </summary>
    public float damagePerHit;
    /// <summary>
    /// World-space point the shot is aimed at, NOT a direction. Relaying yaw/pitch and rebuilding
    /// a point on the observer cannot reproduce the original ray: the projectile leaves the muzzle,
    /// which sits beside the body the direction was measured from, so the line comes out parallel
    /// and displaced (~23 cm at 3.7 m). Zero means "none" — the observer then falls back to its
    /// direction-derived point.
    /// </summary>
    public Vector3 aimPoint;
}