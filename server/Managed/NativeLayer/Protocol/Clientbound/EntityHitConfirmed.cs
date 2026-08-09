using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Clientbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct EntityHitConfirmed : IClientBoundPacket
{
    public ulong VictimNetworkedEntityId;
    public float DamageDealt;
    [MarshalAs(UnmanagedType.I1)] public bool IsHeadshot;
    [MarshalAs(UnmanagedType.I1)] public bool IsDead;

    public EMessageTypeClientbound GetMessageType()
    {
        return EMessageTypeClientbound.EntityHitConfirmed;
    }
}
