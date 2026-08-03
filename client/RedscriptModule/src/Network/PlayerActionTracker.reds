module Cyberverse.Network.Managers

public native class PlayerActionTracker {
    public native func RecordPlayerAction(actionName: CName, actionType: gameinputActionType,  value: Float) -> Void;
    public native func OnShoot(event: ref<gameprojectileShootEvent>) -> Void;
    public native func OnPlayerShoot(item: ItemID, startPoint: Vector4, damagePerHit: Float) -> Void;
    public native func OnHit(gameObject: ref<GameObject>, event: ref<gameHitEvent>);
    public native func OnMounting(evt: ref<MountingEvent>);
    public native func OnUnmounting(evt: ref<UnmountingEvent>);
    public native func OnItemEquipped(slot: TweakDBID, item: ItemID, isWeapon: Bool);
    public native func OnItemUnequipped(slot: TweakDBID, item: ItemID, isWeapon: Bool);
    public native func OnPlayerHealthChanged(healthPercent: Float, isDead: Bool) -> Void;
    public native func LogDiag(code: Int32, value: Float) -> Void;
    public native func TrackJump() -> Void;
}
