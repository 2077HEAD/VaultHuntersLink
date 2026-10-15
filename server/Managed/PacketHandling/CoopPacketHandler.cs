using Cyberverse.Server.NativeLayer.Protocol.Clientbound;
using Cyberverse.Server.NativeLayer.Protocol.Common;
using Cyberverse.Server.NativeLayer.Protocol.Serverbound;
using Cyberverse.Server.Types;
using NLog;

namespace Cyberverse.Server.PacketHandling;

/// <summary>
/// Vault Hunters co-op (2026-10-13). Three jobs, all deliberately dumb:
///
/// 1. Relay PlayerScriptEvent to the other players, stamped with the sender's puppet id. The
///    server never interprets the payload; game-mode logic lives in redscript on the clients,
///    with the party host's client acting as the authority for shared encounters.
/// 2. Maintain the party roster and push it to everyone as a "vh.session" script event whenever
///    it changes: who the host is, who is in the party, and -- per recipient -- the recipient's
///    own puppet id, which a client otherwise never learns.
/// 3. Apply PlayerSetAvatar: the class avatar other clients render a player as.
/// </summary>
public class CoopPacketHandler
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public static readonly ulong SessionChannel = ScriptEventData.ChannelHash("vh.session");

    // Pre-game lobby (main menu). Server -> clients: "vh.lobby" (roster) and "vh.lobby.go" (load in).
    // Clients -> server, accepted before the player is in the world:
    //   vh.lobby.hello  send me the roster        vh.lobby.state  U0 ready, U1 class, U2 is-bot
    //   vh.lobby.start  host only: everyone in the lobby loads in now
    public static readonly ulong LobbyChannel = ScriptEventData.ChannelHash("vh.lobby");
    public static readonly ulong LobbyGoChannel = ScriptEventData.ChannelHash("vh.lobby.go");
    public static readonly ulong LobbyHelloChannel = ScriptEventData.ChannelHash("vh.lobby.hello");
    public static readonly ulong LobbyStateChannel = ScriptEventData.ChannelHash("vh.lobby.state");
    public static readonly ulong LobbyStartChannel = ScriptEventData.ChannelHash("vh.lobby.start");

    private readonly TypedPacketHandler<PlayerScriptEvent> _scriptEventHandler;
    private readonly TypedPacketHandler<PlayerSetAvatar> _setAvatarHandler;
    private GameServer? _server;
    private ulong _joinCounter;
    private ulong _lobbyCounter;
    private bool _sessionStarted;

    public CoopPacketHandler()
    {
        _scriptEventHandler = new TypedPacketHandler<PlayerScriptEvent>(HandleScriptEvent);
        _setAvatarHandler = new TypedPacketHandler<PlayerSetAvatar>(HandleSetAvatar);
    }

    public void RegisterOnServer(GameServer server)
    {
        _server = server;
        server.AddPacketHandler(EMessageTypeServerbound.PlayerScriptEvent, _scriptEventHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerSetAvatar, _setAvatarHandler.HandlePacket);
        server.PlayerJoinedWorld += OnPlayerJoinedWorld;
        server.PlayerAuthenticated += OnPlayerAuthenticated;
        server.PlayerLeft += _ =>
        {
            if (!_server!.PlayerService.ConnectedPlayers.Values.Any(p => !p.IsBot))
            {
                _sessionStarted = false; // everyone real left: the next host starts a new session
            }
            BroadcastSession();
            BroadcastLobby();
        };
    }

    /// <summary>Players that are in the world, earliest first. The first one is the host.</summary>
    private List<Player> PartyMembers()
    {
        return _server!.PlayerService.ConnectedPlayers.Values
            .Where(p => p.PuppetEntity != null)
            .OrderBy(p => p.IsBot) // test bots never host
            .ThenBy(p => p.JoinOrder)
            .ToList();
    }

    /// <summary>Everyone signed in, in or out of the world, in sign-in order.</summary>
    private List<Player> LobbyMembers()
    {
        return _server!.PlayerService.ConnectedPlayers.Values.OrderBy(p => p.LobbyOrder).ToList();
    }

    /// <summary>The lobby host: the earliest signed-in player that is not a test bot.</summary>
    private Player? LobbyHost()
    {
        return LobbyMembers().FirstOrDefault(p => !p.IsBot);
    }

    private void OnPlayerAuthenticated(Player player)
    {
        player.LobbyOrder = ++_lobbyCounter;
        Logger.Info($"Co-op lobby: {player.Name} signed in");
        BroadcastLobby();
    }

    private void OnPlayerJoinedWorld(Player player)
    {
        player.JoinOrder = ++_joinCounter;
        Logger.Info($"Co-op: {player.Name} joined the party (puppet {player.PuppetEntity!.NetworkedEntityId})");
        BroadcastSession();
        if (!_sessionStarted && player == LobbyHost())
        {
            // The host is in the world (START or plain Continue): late joiners may now jump in.
            _sessionStarted = true;
            Logger.Info("Co-op lobby: the host is in the world, session started");
        }
        BroadcastLobby();
    }

    private void HandleScriptEvent(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerScriptEvent content)
    {
        if (content.Data.Channel is var ch
            && (ch == LobbyHelloChannel || ch == LobbyStateChannel || ch == LobbyStartChannel))
        {
            if (server.PlayerService.ConnectedPlayers.TryGetValue(connectionId, out var lobbySender))
            {
                HandleLobbyEvent(lobbySender, content.Data);
            }
            return;
        }

        if (!server.PlayerService.ConnectedPlayers.TryGetValue(connectionId, out var sender)
            || sender.PuppetEntity == null)
        {
            // Sent before the world finished loading: there is no puppet id to stamp, and nobody
            // could resolve the sender anyway. The client re-sends its state on "vh.session".
            Logger.Debug($"Script event from connection {connectionId} without a puppet, dropping");
            return;
        }

        var relayed = new EntityScriptEvent { Data = content.Data };
        relayed.Data.Sender = sender.PuppetEntity.NetworkedEntityId; // never trust the client's value
        relayed.Data.F ??= new float[ScriptEventData.FloatCount];
        relayed.Data.Text ??= new byte[ScriptEventData.TextBytes];

        foreach (var member in PartyMembers())
        {
            if (member.ConnectionId == connectionId)
            {
                continue;
            }

            if (content.Data.Target != 0 && member.PuppetEntity!.NetworkedEntityId != content.Data.Target)
            {
                continue;
            }

            server.EnqueueMessage(EMessageTypeClientbound.EntityScriptEvent, member.ConnectionId, 0, relayed);
        }
    }

    private void HandleSetAvatar(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerSetAvatar content)
    {
        if (!server.PlayerService.ConnectedPlayers.TryGetValue(connectionId, out var player))
        {
            return;
        }

        player.AvatarRecordId = content.RecordId;
        var puppet = player.PuppetEntity;
        if (puppet == null || puppet.RecordId == content.RecordId)
        {
            return; // not spawned yet (HandleJoinWorld will use it) or nothing changes
        }

        Logger.Info($"Co-op: {player.Name} changed avatar, respawning their puppet for its viewers");
        puppet.RecordId = content.RecordId;

        // Despawn + spawn for everyone currently seeing the puppet. OnStartTrackingEntity sends
        // SpawnEntity with the new record plus the equip/health snapshots, same as a fresh join.
        foreach (var viewerId in server.EntityTracker.GetPlayersTracking(puppet.NetworkedEntityId).ToArray())
        {
            if (server.PlayerService.ConnectedPlayers.TryGetValue(viewerId, out var viewer))
            {
                server.EntityTracker.OnStopTrackingEntity(viewer, puppet);
                server.EntityTracker.OnStartTrackingEntity(viewer, puppet);
            }
        }
    }

    /// <summary>
    /// "vh.session": U0 = host puppet id, U1 = party size, U2 = the RECIPIENT's own puppet id,
    /// Text = "id:name;id:name;..." in join order. Sent to every member individually.
    /// </summary>
    private void BroadcastSession()
    {
        var members = PartyMembers();
        var host = members.FirstOrDefault();
        var roster = string.Join(";", members.Select(m => $"{m.PuppetEntity!.NetworkedEntityId}:{m.Name}"));

        foreach (var member in members)
        {
            var evt = new EntityScriptEvent { Data = ScriptEventData.Create("vh.session") };
            evt.Data.Sender = 0; // server-generated
            evt.Data.U0 = host?.PuppetEntity?.NetworkedEntityId ?? 0;
            evt.Data.U1 = (ulong)members.Count;
            evt.Data.U2 = member.PuppetEntity!.NetworkedEntityId;
            evt.Data.SetText(roster);
            _server!.EnqueueMessage(EMessageTypeClientbound.EntityScriptEvent, member.ConnectionId, 0, evt);
        }

        Logger.Info($"Co-op: party is now [{roster}], host {host?.Name ?? "none"}");
    }

    // ---------------- pre-game lobby ----------------

    private void HandleLobbyEvent(Player sender, ScriptEventData data)
    {
        if (data.Channel == LobbyHelloChannel)
        {
            SendLobbyTo(sender, LobbyMembers(), LobbyHost());
            return;
        }

        if (data.Channel == LobbyStateChannel)
        {
            sender.LobbyReady = data.U0 != 0;
            sender.LobbyClass = (int)Math.Min(data.U1, 6ul);
            sender.IsBot = data.U2 != 0;
            BroadcastLobby();
            return;
        }

        if (data.Channel == LobbyStartChannel)
        {
            if (sender != LobbyHost())
            {
                Logger.Warn($"Co-op lobby: {sender.Name} tried to start the session but is not the host");
                return;
            }

            _sessionStarted = true;
            Logger.Info($"Co-op lobby: {sender.Name} started the session");
            foreach (var member in LobbyMembers().Where(m => m.PuppetEntity == null))
            {
                var go = new EntityScriptEvent { Data = ScriptEventData.Create("vh.lobby.go") };
                go.Data.Sender = 0;
                _server!.EnqueueMessage(EMessageTypeClientbound.EntityScriptEvent, member.ConnectionId, 0, go);
            }
            BroadcastLobby();
        }
    }

    private static string LobbyName(Player p)
    {
        var name = new string((p.Name ?? "Player").Where(c => c != ':' && c != ';').ToArray());
        return name.Length > 12 ? name[..12] : name;
    }

    /// <summary>
    /// "vh.lobby": U0 = host connection id (0 = none), U1 = 1 once the session started,
    /// U2 = the RECIPIENT's connection id,
    /// Text = "id:name:ready:class:bot;..." in sign-in order (ready/bot are 0/1).
    /// </summary>
    private void SendLobbyTo(Player recipient, List<Player> members, Player? host)
    {
        var roster = string.Join(";", members.Select(m =>
            $"{m.ConnectionId}:{LobbyName(m)}:{(m.LobbyReady ? 1 : 0)}:{m.LobbyClass}:{(m.IsBot ? 1 : 0)}"));
        var evt = new EntityScriptEvent { Data = ScriptEventData.Create("vh.lobby") };
        evt.Data.Sender = 0;
        evt.Data.U0 = host?.ConnectionId ?? 0;
        evt.Data.U1 = _sessionStarted ? 1ul : 0ul;
        evt.Data.U2 = recipient.ConnectionId;
        evt.Data.SetText(roster);
        _server!.EnqueueMessage(EMessageTypeClientbound.EntityScriptEvent, recipient.ConnectionId, 0, evt);
    }

    private void BroadcastLobby()
    {
        var members = LobbyMembers();
        var host = LobbyHost();
        foreach (var member in members)
        {
            SendLobbyTo(member, members, host);
        }
    }
}
