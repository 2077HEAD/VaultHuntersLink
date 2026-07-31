using Cyberverse.Server.NativeLayer.Protocol.Clientbound;
using Cyberverse.Server.NativeLayer.Protocol.Serverbound;
using Cyberverse.Server.Services;
using Cyberverse.Server.Types;
using NLog;

namespace Cyberverse.Server.PacketHandling;

public class PlayerPacketHandler
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly Random Random = new();
    private static readonly string[] PossiblePlayerNpcChoice = ["Character.Judy", "Character.Panam", "Character.Alt", 
        "Character.Clair", "Character.Dexter", "Character.Evelyn", "Character.Hanako", "Character.Jackie", 
        "Character.Mama_Welles", "Character.Misty", "Character.Stout", "Character.Takemura", "Character.Tbug",
        "Character.wakako_okada", "Character.Yorinobu"];
    
    private readonly TypedPacketHandler<PlayerJoinWorld> _playerJoinHandler;
    private readonly TypedPacketHandler<PlayerPositionUpdate> _playerMoveHandler;
    private readonly TypedPacketHandler<PlayerSpawnCar> _playerSpawnCarHandler;
    private readonly TypedPacketHandler<PlayerUnmountCar> _playerUnmountHandler;
    private readonly TypedPacketHandler<PlayerEquipItem> _playerEquipHandler;
    private readonly TypedPacketHandler<PlayerShoot> _playerShootHandler;
    private readonly TypedPacketHandler<PlayerActionTracked> _playerActionHandler;
    private EntityTracker? _tracker = null;
    private PlayerService? _players = null;

    public PlayerPacketHandler()
    {
        _playerJoinHandler = new TypedPacketHandler<PlayerJoinWorld>(HandleJoinWorld);
        _playerMoveHandler = new TypedPacketHandler<PlayerPositionUpdate>(HandlePositionUpdate);
        _playerSpawnCarHandler = new TypedPacketHandler<PlayerSpawnCar>(HandleSpawnCar);
        _playerUnmountHandler = new TypedPacketHandler<PlayerUnmountCar>(HandleUnmountCar);
        _playerEquipHandler = new TypedPacketHandler<PlayerEquipItem>(HandleEquip);
        _playerShootHandler = new TypedPacketHandler<PlayerShoot>(HandleShoot);
        _playerActionHandler = new TypedPacketHandler<PlayerActionTracked>(HandleActionTracked);
    }

    protected void HandleJoinWorld(GameServer server, EMessageTypeServerbound messageType, byte channelId, uint connectionId, PlayerJoinWorld content)
    {
        if (_players!.ConnectedPlayers.TryGetValue(connectionId, out var player))
        {
            Logger.Trace("Player {0} joined the world at ({1}, {2}, {3})", player.Name, 
                content.position.x, content.position.y, content.position.z);

            var choice = Random.Next(PossiblePlayerNpcChoice.Length);
            var entity = server.EntityService.CreateEntity(PossiblePlayerNpcChoice[choice]);
            entity.WorldTransform = content.position; // Spawn the entity at the right spot already
            entity.NetworkIdOwner = player.ConnectionId;
            player.PuppetEntity = entity;
                
            // Since we only call the tracking for moved entities, force sync every entity to that player:
            _tracker!.InitialSpawnForPlayer(player);
        }
        else
        {
            Logger.Warn($"Could not find player with id {connectionId} in the player list.");
        }
    }

    protected void HandlePositionUpdate(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerPositionUpdate content)
    {
        // diag (2026-07-29, choomlink-7jcw): the client already sends yaw on every position
        // update (used below for entity.Yaw) but it was never logged. This is the only
        // engine-native channel we have for the REAL player's current camera facing (bots
        // report their own yaw via their Behavior pattern, not via reading anything back).
        // Logging it lets a deterministic camera-aiming tool read "where am I currently
        // facing" from this log's tail instead of trial-and-error mouse sweeps. High-frequency
        // by design (fires on every update, same as the bot diag: lines already used
        // throughout this project) — consumers should read the LAST matching line, not all of
        // them.
        if (_players!.ConnectedPlayers.TryGetValue(connectionId, out var updatingPlayer))
        {
            Logger.Trace("diag: pos {0} at ({1:F3}, {2:F3}, {3:F3}) yaw={4:F2} pitch={5:F2}", updatingPlayer.Name,
                content.worldTransform.x, content.worldTransform.y, content.worldTransform.z, content.yaw, content.pitch);
        }

        // // TODO: Implement differently, don't teleport.
        // TeleportEntity teleportEntity = default;
        // teleportEntity.networkedEntityId = 0;
        // teleportEntity.targetPosition = positionUpdate.worldTransform;
        // teleportEntity.yaw = positionUpdate.yaw;
        //                         
        // Message outputMessage = default;
        // outputMessage.MessageTypeClientBound(EMessageTypeClientbound.TeleportEntity);
        // outputMessage.channelId = 1;
        // outputMessage.connectionId = message.connectionId;
        // outputMessage.MarshalFrom(teleportEntity);
        //
        // EnqueueMessage(outputMessage);

        var playerEntities =
            server.EntityService.SpawnedEntities.Values.Where(tty => tty.NetworkIdOwner == connectionId);
        foreach (var entity in playerEntities)
        {
            //Console.WriteLine($"Move {player.Name} ({player.ConnectionId} / {message.connectionId}) to ({positionUpdate.worldTransform.x}, {positionUpdate.worldTransform.y}, {positionUpdate.worldTransform.z})");
            
            // TODO: sometimes the game sends faulty updates to ~0, 3.16, 0.
            // TODO: This is happening before the savegame has loaded. A better solution is to prevent updating networkEntityIds that are not spawned yet,
            // because what happens here is that player.NetworkedEntityId is 0 because it has no entity yet, thus moving the old player.
            // Note: this should already be solved.
            if (content.worldTransform.z == 0 && content.worldTransform.x == 0.010673523f)
            {
                // TODO: we should really remove that.
                Logger.Trace("Skipping position update");
                return;
            }
                    
            entity.WorldTransform = content.worldTransform;
            entity.Yaw = content.yaw;
            entity.Pitch = content.pitch;
            _tracker!.UpdateTrackingOf(entity);
        }
    }

    protected void HandleSpawnCar(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerSpawnCar content)
    {
        var hash = RecordIdUtils.RecordIdToCrcHash(content.recordId);
        var len = RecordIdUtils.RecordIdToNameLength(content.recordId);
        
        Logger.Trace($"Player spawned a {hash} [{len}] at {content.worldTransform}");
        
        DespawnAllVehiclesForPlayer(server, connectionId);

        var entity = server.EntityService.CreateEntity(content.recordId);
        entity.WorldTransform = content.worldTransform; // Spawn the entity at the right spot already
        entity.Yaw = content.yaw;
        entity.NetworkIdOwner = connectionId;
        entity.IsVehicle = true;

        _tracker!.UpdateTrackingOf(entity);
    }

    private void DespawnAllVehiclesForPlayer(GameServer server, uint connectionId)
    {
        // Try to find existing cars for that owner.
        var existingVehicles = server.EntityService.SpawnedEntities
            .Select(x => x.Value)
            .Where(x => x.NetworkIdOwner == connectionId)
            .Where(x => x.IsVehicle)
            .ToList();

        foreach (var vehicle in existingVehicles)
        {
            vehicle.NetworkIdOwner = 0;
            _tracker!.StopTrackingOf(vehicle);
            server.EntityService.RemoveEntity(vehicle.NetworkedEntityId);
        }
    }

    protected void HandleUnmountCar(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerUnmountCar content)
    {
        DespawnAllVehiclesForPlayer(server, connectionId);
    }

    private void HandleEquip(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerEquipItem content)
    {
        // Weapon sync spec §2: equipment is player state on the puppet entity, no world entity.
        if (!_players!.ConnectedPlayers.TryGetValue(connectionId, out var player) || player.PuppetEntity == null)
        {
            Logger.Warn($"PlayerEquipItem from connection {connectionId} without a puppet, dropping");
            return;
        }

        var puppet = player.PuppetEntity;
        if (content.isUnequipping)
        {
            // Idempotent: unequip of an empty/other slot state is a no-op state-wise.
            if (puppet.DrawnWeaponSlot != content.slot)
            {
                return;
            }
            puppet.DrawnWeaponSlot = 0;
            puppet.DrawnWeaponItemId = 0;
        }
        else
        {
            if (puppet.DrawnWeaponSlot == content.slot && puppet.DrawnWeaponItemId == content.itemId)
            {
                return;
            }
            puppet.DrawnWeaponSlot = content.slot;
            puppet.DrawnWeaponItemId = content.itemId;
        }

        Logger.Info($"Equip state {player.Name}: slot {content.slot} item {content.itemId} unequip={content.isUnequipping}");

        var equip = new EquipItemEntity
        {
            NetworkedEntityId = puppet.NetworkedEntityId,
            Slot = content.slot,
            ItemId = content.itemId,
            isWeapon = content.isWeapon,
            isUnequipping = content.isUnequipping
        };
        foreach (var trackingConnectionId in _tracker!.GetPlayersTracking(puppet.NetworkedEntityId))
        {
            server.EnqueueMessage(EMessageTypeClientbound.EquipItemEntity, trackingConnectionId, channelId, equip);
        }
    }

    private void HandleShoot(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerShoot content)
    {
        // Relay the shot to every player tracking the shooter's puppet (pattern: HandleActionTracked).
        var senderEntity = server.EntityService.SpawnedEntities.Values
            .FirstOrDefault(entity => entity.NetworkIdOwner == connectionId && !entity.IsVehicle);
        if (senderEntity == null)
        {
            Logger.Warn($"PlayerShoot from connection {connectionId} without a spawned entity, dropping");
            return;
        }

        Logger.Trace($"Shot by {connectionId}: weapon {content.itemIdWeapon} at {content.startPoint}");

        var shot = new EntityShoot
        {
            NetworkedEntityId = senderEntity.NetworkedEntityId,
            ItemIdWeapon = content.itemIdWeapon,
            StartPoint = content.startPoint,
            Charge = content.charge
        };
        foreach (var trackingConnectionId in _tracker!.GetPlayersTracking(senderEntity.NetworkedEntityId))
        {
            server.EnqueueMessage(EMessageTypeClientbound.EntityShoot, trackingConnectionId, channelId, shot);
        }
    }

    private void HandleActionTracked(GameServer server, EMessageTypeServerbound messageType, byte channelId,
        uint connectionId, PlayerActionTracked content)
    {
        // Relay the action to every other player, attributed to the sender's puppet entity.
        var senderEntity = server.EntityService.SpawnedEntities.Values
            .FirstOrDefault(entity => entity.NetworkIdOwner == connectionId && !entity.IsVehicle);
        if (senderEntity == null)
        {
            Logger.Warn($"PlayerActionTracked from connection {connectionId} without a spawned entity, dropping");
            return;
        }

        Logger.Trace($"Player action {content.action} from {connectionId} at {content.worldTransform}");

        var entityAction = new EntityAction
        {
            networkedEntityId = senderEntity.NetworkedEntityId,
            action = content.action,
            worldTransform = content.worldTransform
        };

        // Interest-managed: only players currently tracking the sender's puppet get the action
        // (a player never tracks their own entity, so no self-check needed).
        foreach (var trackingConnectionId in _tracker!.GetPlayersTracking(senderEntity.NetworkedEntityId))
        {
            server.EnqueueMessage(EMessageTypeClientbound.EntityAction, trackingConnectionId, channelId, entityAction);
        }
    }

    public void RegisterOnServer(GameServer server)
    {
        _tracker = server.EntityTracker; // TODO: Service registry or even using DI
        _players = server.PlayerService;
        
        server.AddPacketHandler(EMessageTypeServerbound.PlayerJoinWorld, _playerJoinHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerPositionUpdate, _playerMoveHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerSpawnCar, _playerSpawnCarHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerUnmountCar, _playerUnmountHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerEquipItem, _playerEquipHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerShoot, _playerShootHandler.HandlePacket);
        server.AddPacketHandler(EMessageTypeServerbound.PlayerActionTracked, _playerActionHandler.HandlePacket);
    }
}
