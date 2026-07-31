using System.Runtime.InteropServices;
using Cyberverse.Server.NativeLayer.Protocol.Common;

namespace Cyberverse.Server.NativeLayer.Protocol.Clientbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct EntityShoot : IClientBoundPacket
{
    public ulong NetworkedEntityId;
    public ulong ItemIdWeapon;
    public Vector3 StartPoint;
    public float Charge;

    public EMessageTypeClientbound GetMessageType()
    {
        return EMessageTypeClientbound.EntityShoot;
    }
}
