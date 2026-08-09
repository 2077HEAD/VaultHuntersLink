using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Serverbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct PlayerWasHit
{
    public ulong shooterNetworkedEntityId;
    /// <summary>Points, not percent — see EntityHealth for the percent convention used elsewhere.</summary>
    public float damageDealt;
    // 1-byte wire bool; without I1 .NET marshals 4 bytes and reads padding (root-caused
    // 2026-07-31 on PlayerEquipItem.isUnequipping, which was always false).
    [MarshalAs(UnmanagedType.I1)] public bool isHeadshot;
    [MarshalAs(UnmanagedType.I1)] public bool isDead;
}
