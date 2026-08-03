using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Serverbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct PlayerHealthUpdate
{
    /// <summary>0..100. Percent, not points — see the damage/health sync design §4.1.</summary>
    public float healthPercent;
    // 1-byte wire bool; without I1 .NET marshals 4 bytes and reads padding (root-caused
    // 2026-07-31 on PlayerEquipItem.isUnequipping, which was always false).
    [MarshalAs(UnmanagedType.I1)] public bool isDead;
}
