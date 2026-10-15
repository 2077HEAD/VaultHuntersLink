using System.Net;
using System.Net.Sockets;
using System.Text;

namespace VaultHuntersLauncher;

/// <summary>
/// Invite codes: an IPv4 address + port packed into 6 bytes and written in Crockford base32,
/// e.g. "VH-7K2Q9-XMD4A". Easy to read out loud or paste into a chat; no I/O/L confusion.
/// The Join screen also accepts a plain "1.2.3.4:1337", "1.2.3.4" or a host name.
/// </summary>
public static class InviteCode
{
    private const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    public static string Encode(IPAddress address, int port)
    {
        var ip = address.MapToIPv4().GetAddressBytes();
        var bytes = new byte[] { ip[0], ip[1], ip[2], ip[3], (byte)(port >> 8), (byte)(port & 0xff) };
        ulong value = 0;
        foreach (var b in bytes) value = (value << 8) | b;
        // 48 bits -> 10 base32 digits (50 bits)
        var sb = new StringBuilder();
        for (var i = 9; i >= 0; i--)
        {
            sb.Append(Alphabet[(int)((value >> (i * 5)) & 31)]);
        }
        var s = sb.ToString();
        return $"VH-{s[..5]}-{s[5..]}";
    }

    /// <summary>Address and port from a code or a typed address. Null when it can't be understood.</summary>
    public static (string Host, int Port)? Decode(string? input, int defaultPort)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var text = input.Trim();

        var compact = text.ToUpperInvariant().Replace("-", "").Replace(" ", "");
        if (compact.StartsWith("VH")) compact = compact[2..];
        if (compact.Length == 10 && compact.All(c => Alphabet.Contains(Normalize(c))))
        {
            ulong value = 0;
            foreach (var c in compact) value = (value << 5) | (ulong)Alphabet.IndexOf(Normalize(c));
            var port = (int)(value & 0xffff);
            var ip = new IPAddress(new[] { (byte)(value >> 40), (byte)(value >> 32), (byte)(value >> 24), (byte)(value >> 16) });
            if (port > 0) return (ip.ToString(), port);
        }

        // "host:port" or "host"
        var host = text;
        var p = defaultPort;
        var colon = text.LastIndexOf(':');
        if (colon > 0 && int.TryParse(text[(colon + 1)..], out var parsed) && parsed is > 0 and < 65536)
        {
            host = text[..colon];
            p = parsed;
        }
        if (host.Contains(' ') || host.Length == 0) return null;
        if (IPAddress.TryParse(host, out _) || Uri.CheckHostName(host) == UriHostNameType.Dns) return (host, p);
        return null;
    }

    // Crockford: people type O for 0 and I/L for 1.
    private static char Normalize(char c) => c switch { 'O' => '0', 'I' => '1', 'L' => '1', _ => c };

    public static bool IsPrivateOrShared(IPAddress address)
    {
        if (address.AddressFamily != AddressFamily.InterNetwork) return false;
        var b = address.GetAddressBytes();
        return b[0] == 10
            || (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
            || (b[0] == 192 && b[1] == 168)
            || (b[0] == 100 && b[1] >= 64 && b[1] <= 127)   // carrier-grade NAT range
            || b[0] == 127;
    }
}
