namespace Cyberverse.Server.Types;

/// <summary>
/// Don't overuse this class, it's just a simple dataclass, we want to handle complex data in a different way
/// </summary>
public class Player
{
    // TODO: Validate by JWT claim
    public string? Name;
    public uint ConnectionId;

    /// <summary>
    /// The player's own puppet entity (set on JoinWorld). Used as the viewer position for
    /// interest management. Null until the player has joined the world.
    /// </summary>
    public Entity? PuppetEntity;

    /// <summary>
    /// Vault Hunters co-op: the character record other clients should render this player as
    /// (the class avatar). 0 = not chosen yet, fall back to upstream's random story NPC.
    /// </summary>
    public ulong AvatarRecordId;

    /// <summary>
    /// Vault Hunters co-op: order in which players entered the world. The earliest one still
    /// connected is the party host (owns shared encounters, see CoopPacketHandler).
    /// </summary>
    public ulong JoinOrder;

    /// <summary>Vault Hunters lobby: order in which players signed in (before the world).</summary>
    public ulong LobbyOrder;

    /// <summary>Vault Hunters lobby: pressed READY on the main menu.</summary>
    public bool LobbyReady;

    /// <summary>Vault Hunters lobby: class index the player announced (0 = unknown).</summary>
    public int LobbyClass;

    /// <summary>A test bot (vh-testbot.exe). Bots never become lobby or party host.</summary>
    public bool IsBot;
}