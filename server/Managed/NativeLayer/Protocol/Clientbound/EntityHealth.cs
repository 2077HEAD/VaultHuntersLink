using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Clientbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct EntityHealth : IClientBoundPacket
{
    public ulong NetworkedEntityId;
    /// <summary>0..100.</summary>
    public float HealthPercent;
    // See PlayerHealthUpdate.isDead for why I1 is mandatory here.
    [MarshalAs(UnmanagedType.I1)] public bool IsDead;

    public EMessageTypeClientbound GetMessageType()
    {
        return EMessageTypeClientbound.EntityHealth;
    }
}
