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

    private readonly TypedPacketHandler<PlayerScriptEvent> _scriptEventHandler;
    private readonly TypedPacketHandler<PlayerSetAvatar> _setAvatarHandler;
    private GameServer? _server;
    private ulong _joinCounter;

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
        server.PlayerLeft += _ => BroadcastSession();
    }

    /// <summary>Players that are in the world, earliest first. The first one is the host.</summary>
    private List<Player> PartyMembers()
    {
        return _server!.PlayerService.ConnectedPlayers.Values
            .Where(p => p.PuppetEntity != null)
            .OrderBy(p => p.JoinOrder)
            .ToList();
    }

    private void OnPlayerJoinedWorld(Player player)
    {
        player.JoinOrder = ++_joinCounter;
        Logger.Info($"Co-op: {player.Name} joined the party (puppet {player.PuppetEntity!.NetworkedEntityId})");
        BroadcastSession();
    }

    private void HandleScriptEvent(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerScriptEvent content)
    {
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
}
