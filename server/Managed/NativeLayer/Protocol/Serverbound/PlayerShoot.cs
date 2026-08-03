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
}