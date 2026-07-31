using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Clientbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct EquipItemEntity: IClientBoundPacket
{
    public ulong NetworkedEntityId;
    public ulong Slot;
    public ulong ItemId;
    // 1-byte wire bools — see PlayerEquipItem.cs (default 4-byte bool marshalling corrupts
    // the second flag).
    [MarshalAs(UnmanagedType.I1)] public bool isWeapon;
    [MarshalAs(UnmanagedType.I1)] public bool isUnequipping;

    public EMessageTypeClientbound GetMessageType()
    {
        return EMessageTypeClientbound.EquipItemEntity;
    }
}