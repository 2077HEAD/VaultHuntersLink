using System.Runtime.InteropServices;
using System.Text;

namespace Cyberverse.Server.NativeLayer.Protocol.Common;

/// <summary>
/// Mirror of shared/protocol/ScriptEvent.h (Vault Hunters co-op, 2026-10-13). 208 bytes, no
/// padding; must stay byte-identical with the C++ struct because the native layer memcpy's it.
/// The server only routes these. Their meaning belongs to the redscript game-mode layer.
/// </summary>
[StructLayout(LayoutKind.Sequential, Pack = 8)]
public struct ScriptEventData
{
    public const int FloatCount = 8;
    public const int TextBytes = 128;

    public ulong Channel;
    public ulong Sender;
    public ulong Target;
    public ulong U0;
    public ulong U1;
    public ulong U2;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = FloatCount)] public float[] F;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = TextBytes)] public byte[] Text;

    public static ScriptEventData Create(string channel)
    {
        return new ScriptEventData
        {
            Channel = ChannelHash(channel),
            F = new float[FloatCount],
            Text = new byte[TextBytes]
        };
    }

    public string GetText()
    {
        if (Text == null) return "";
        var len = Array.IndexOf(Text, (byte)0);
        return Encoding.UTF8.GetString(Text, 0, len < 0 ? Text.Length : len);
    }

    public void SetText(string value)
    {
        Text ??= new byte[TextBytes];
        Array.Clear(Text);
        var bytes = Encoding.UTF8.GetBytes(value);
        Array.Copy(bytes, Text, Math.Min(bytes.Length, TextBytes - 1));
    }

    /// <summary>FNV-1a 64, i.e. the game's CName hash. Must match ScriptEventChannel() in C++.</summary>
    public static ulong ChannelHash(string name)
    {
        var hash = 0xCBF29CE484222325ul;
        foreach (var b in Encoding.UTF8.GetBytes(name))
        {
            hash ^= b;
            hash *= 0x100000001B3ul;
        }
        return hash;
    }
}
