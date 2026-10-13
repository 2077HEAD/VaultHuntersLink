module Cyberverse.Network.Managers

public native class PlayerActionTracker {
    public native func RecordPlayerAction(actionName: CName, actionType: gameinputActionType,  value: Float) -> Void;
    public native func OnShoot(event: ref<gameprojectileShootEvent>) -> Void;
    public native func OnPlayerShoot(item: ItemID, startPoint: Vector4, damagePerHit: Float, aimPoint: Vector4) -> Void;
    public native func OnHit(gameObject: ref<GameObject>, event: ref<gameHitEvent>);
    public native func OnMounting(evt: ref<MountingEvent>);
    public native func OnUnmounting(evt: ref<UnmountingEvent>);
    public native func OnItemEquipped(slot: TweakDBID, item: ItemID, isWeapon: Bool);
    public native func OnItemUnequipped(slot: TweakDBID, item: ItemID, isWeapon: Bool);
    public native func OnPlayerHealthChanged(healthPercent: Float, isDead: Bool) -> Void;
    public native func OnPlayerWasHit(shooterNetworkedEntityId: Uint64, damageDealt: Float, isHeadshot: Bool, isDead: Bool) -> Void;
    public native func LogDiag(code: Int32, value: Float) -> Void;
    public native func TrackJump() -> Void;
    // Vault Hunters co-op (2026-10-13): generic script events + class avatar. Prefer the wrappers
    // on NetworkGameSystem (SendScriptEvent / SetAvatar), they validate the payload.
    public native func SendScriptEvent(channel: CName, target: Int32, u0: Int64, u1: Int64, u2: Int64, f: array<Float>, text: String) -> Void;
    public native func SetAvatar(record: TweakDBID) -> Void;
}
