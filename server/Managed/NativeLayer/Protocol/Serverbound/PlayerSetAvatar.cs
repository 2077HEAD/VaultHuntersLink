using System.Runtime.InteropServices;

namespace Cyberverse.Server.NativeLayer.Protocol.Serverbound;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct PlayerSetAvatar
{
    /// <summary>TweakDBID value of the character record (crc32 | length &lt;&lt; 32).</summary>
    public ulong RecordId;
}
