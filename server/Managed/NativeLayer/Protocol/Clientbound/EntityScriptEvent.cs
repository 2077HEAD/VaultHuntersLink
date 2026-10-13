using System.Runtime.InteropServices;
using Cyberverse.Server.NativeLayer.Protocol.Common;

namespace Cyberverse.Server.NativeLayer.Protocol.Clientbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct EntityScriptEvent : IClientBoundPacket
{
    public ScriptEventData Data;

    public EMessageTypeClientbound GetMessageType()
    {
        return EMessageTypeClientbound.EntityScriptEvent;
    }
}
