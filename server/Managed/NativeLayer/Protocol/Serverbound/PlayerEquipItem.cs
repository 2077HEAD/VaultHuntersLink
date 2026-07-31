using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Serverbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct PlayerEquipItem
{
    public ulong slot;
    public ulong itemId;
    // Wire bools are 1 byte (zpp::bits/C++), .NET default-marshals bool as 4 bytes — without
    // I1 the second flag reads padding and is always false (upstream's TODO; root-caused
    // 2026-07-31: client sent isUnequipping=true, server logged unequip=False).
    [MarshalAs(UnmanagedType.I1)] public bool isWeapon;
    [MarshalAs(UnmanagedType.I1)] public bool isUnequipping;
}