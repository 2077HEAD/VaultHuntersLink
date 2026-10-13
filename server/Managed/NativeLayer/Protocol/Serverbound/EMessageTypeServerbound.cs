namespace Cyberverse.Server.NativeLayer.Protocol.Serverbound;

public enum EMessageTypeServerbound: ushort
{
    InitAuth = 0,
    PlayerJoinWorld = 1,
    PlayerActionTracked = 2,
    PlayerPositionUpdate = 3,
    PlayerSpawnCar = 4,
    PlayerMountCar = 5, // TODO: Implement
    PlayerUnmountCar = 6,
    PlayerEquipItem = 7,
    PlayerShoot = 8,
    PlayerHealthUpdate = 9,
    PlayerWasHit = 10,
    PlayerScriptEvent = 11, // Vault Hunters co-op
    PlayerSetAvatar = 12    // Vault Hunters co-op
}